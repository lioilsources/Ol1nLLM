import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// MusicStudio client — „vibe z předlohy" on the AiStack audio service
/// (`services/audio`, reached through the gateway at llm.ol1n.com/v1/audio).
///
/// Two phases on purpose: the server first *listens* to the sample (ACE-Step's
/// 5 Hz LM writes a caption, tempo, key) so the user can see and fix what it
/// heard, and only then composes. Both are jobs (`202 {job_id}` → poll), not
/// blocking calls: they share the GPU queue with other music jobs and the
/// first request after the model container starts waits for its weights —
/// longer than Cloudflare's 100 s edge timeout.
class MusicService {
  static const _root = String.fromEnvironment(
    'AUDIO_URL',
    defaultValue: 'https://llm.ol1n.com',
  );
  static const _base = '$_root/v1/audio';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');
  static const _timeout = Duration(seconds: 30);
  static const _uploadTimeout = Duration(minutes: 2);
  static const _downloadTimeout = Duration(minutes: 2);
  static const _pollInterval = Duration(seconds: 2);

  /// Consecutive failed polls tolerated before [MusicInterrupted].
  static const _maxPollFailures = 6;

  MusicService({http.Client? client, Duration? pollInterval})
    : _client = client ?? http.Client(),
      _poll = pollInterval ?? _pollInterval;

  final http.Client _client;
  final Duration _poll;

  /// CF Access is optional so a LAN build (`AUDIO_URL=http://…:8093`) works
  /// without it; through Cloudflare a missing token surfaces as a 403.
  Map<String, String> get _auth => {
    if (_cfId.isNotEmpty) 'CF-Access-Client-Id': _cfId,
    if (_cfSecret.isNotEmpty) 'CF-Access-Client-Secret': _cfSecret,
  };

  /// Body as UTF-8. FastAPI sends `application/json` without a charset, and
  /// `Response.body` would then decode Latin-1 — every Czech error message
  /// from the server would arrive garbled.
  static String _text(http.Response r) =>
      utf8.decode(r.bodyBytes, allowMalformed: true);

  static Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(_text(r)) as Map<String, dynamic>;

  /// Human-readable error from a FastAPI `{"detail": …}` body.
  static String _snippet(http.Response r) {
    var msg = _text(r);
    try {
      final j = jsonDecode(msg);
      if (j is Map && j['detail'] is String) {
        msg = j['detail'] as String;
      } else if (j is Map && j['detail'] is List) {
        final first = (j['detail'] as List).firstOrNull;
        if (first is Map && first['msg'] is String) {
          msg = first['msg'] as String;
        }
      }
    } catch (_) {}
    if (r.statusCode == 403 && msg.contains('<')) {
      msg = 'přístup odepřen (CF Access token)';
    }
    msg = msg.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (msg.length > 160) msg = '${msg.substring(0, 160)}…';
    return 'HTTP ${r.statusCode}${msg.isNotEmpty ? ": $msg" : ""}';
  }

  /// Upload the sample. The server decodes it (any format ffmpeg reads, video
  /// too), keeps the loudest ≤ 60 s, and returns its analysis if the same
  /// file was analysed before — the id is a hash of the bytes.
  Future<UploadedSample> uploadSample(File file, String name) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/vibe/samples'))
      ..headers.addAll(_auth)
      ..files.add(
        await http.MultipartFile.fromPath('sample', file.path, filename: name),
      );
    final r = await http.Response.fromStream(
      await _client.send(req).timeout(_uploadTimeout),
    );
    if (r.statusCode != 200) throw MusicServiceException(_snippet(r));
    return UploadedSample.fromJson(_json(r));
  }

  Future<String> analyze(String sampleId) =>
      _submit('/vibe/analyze', {'sample_id': sampleId});

  Future<String> generate(Map<String, dynamic> body) =>
      _submit('/vibe/generate', body);

  Future<String> _submit(String path, Map<String, dynamic> body) async {
    final r = await _client
        .post(
          Uri.parse('$_base$path'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (r.statusCode == 404) throw const SampleGoneException();
    if (r.statusCode != 202) throw MusicServiceException(_snippet(r));
    return _json(r)['job_id'] as String;
  }

  /// Poll job [jobId] to a terminal state. A run of network failures ends in
  /// [MusicInterrupted] (the job lives on in the server's SQLite, so the
  /// provider re-attaches later — even after hours).
  Stream<MusicJobEvent> follow(String jobId) async* {
    var failures = 0;
    while (true) {
      Map<String, dynamic> j;
      try {
        final r = await _client
            .get(Uri.parse('$_base/jobs/$jobId'), headers: _auth)
            .timeout(_timeout);
        if (r.statusCode == 404) {
          yield const MusicFailed('Job na serveru už neexistuje');
          return;
        }
        if (r.statusCode != 200) throw MusicServiceException(_snippet(r));
        j = _json(r);
        failures = 0;
      } on Exception catch (e) {
        if (++failures >= _maxPollFailures) {
          debugPrint('[music] job $jobId: poll failed $failures× ($e)');
          yield const MusicInterrupted();
          return;
        }
        await Future<void>.delayed(_poll);
        continue;
      }
      switch (j['status']) {
        case 'queued':
          yield MusicQueued((j['queue_position'] as num?)?.toInt());
        case 'running':
          yield const MusicRunning();
        case 'done':
          yield MusicDone(j);
          return;
        case 'error':
          final err = (j['error'] as String?)?.trim();
          yield MusicFailed(
            err == null || err.isEmpty ? 'Generování selhalo' : err,
          );
          return;
        default:
          yield MusicFailed('Neznámý stav jobu: ${j['status']}');
          return;
      }
      await Future<void>.delayed(_poll);
    }
  }

  /// Download an output (`url` as the server lists it, relative). Checked
  /// against content-length: a truncated body still arrives as 200.
  Future<Uint8List> download(String url, {int? expectedBytes}) async {
    for (var attempt = 0; ; attempt++) {
      final r = await _client
          .get(Uri.parse('$_root$url'), headers: _auth)
          .timeout(_downloadTimeout);
      if (r.statusCode != 200) throw MusicServiceException(_snippet(r));
      final declared =
          expectedBytes ?? int.tryParse(r.headers['content-length'] ?? '');
      if (declared == null || r.bodyBytes.length == declared) {
        return r.bodyBytes;
      }
      if (attempt >= 1) {
        throw MusicServiceException(
          'staženo ${r.bodyBytes.length} z $declared B',
        );
      }
    }
  }

  void dispose() => _client.close();
}

class UploadedSample {
  final String sampleId;
  final double durationS;
  final double sourceDurationS;
  final double windowStartS;

  /// Earlier analysis of the same bytes, if any.
  final Map<String, dynamic>? analysis;

  const UploadedSample({
    required this.sampleId,
    required this.durationS,
    required this.sourceDurationS,
    required this.windowStartS,
    this.analysis,
  });

  factory UploadedSample.fromJson(Map<String, dynamic> j) => UploadedSample(
    sampleId: j['sample_id'] as String,
    durationS: (j['duration_s'] as num).toDouble(),
    sourceDurationS: (j['source_duration_s'] as num).toDouble(),
    windowStartS: (j['window_start_s'] as num?)?.toDouble() ?? 0,
    analysis: j['analysis'] as Map<String, dynamic>?,
  );
}

sealed class MusicJobEvent {
  const MusicJobEvent();
}

class MusicQueued extends MusicJobEvent {
  final int? position;
  const MusicQueued(this.position);
}

class MusicRunning extends MusicJobEvent {
  const MusicRunning();
}

class MusicDone extends MusicJobEvent {
  /// Whole job status: `outputs` for a composition, `result` = analysis or
  /// manifest.
  final Map<String, dynamic> job;
  const MusicDone(this.job);
}

class MusicFailed extends MusicJobEvent {
  final String message;
  const MusicFailed(this.message);
}

/// Transient: network gone mid-poll. Not a failure — the job keeps running.
class MusicInterrupted extends MusicJobEvent {
  const MusicInterrupted();
}

class MusicServiceException implements Exception {
  final String message;
  const MusicServiceException(this.message);
  @override
  String toString() => message;
}

/// The server no longer knows the sample (data wiped) — upload it again.
class SampleGoneException implements Exception {
  const SampleGoneException();
  @override
  String toString() => 'předloha na serveru není';
}
