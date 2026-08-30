import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/video_scene.dart';
import 'image_backend.dart';

/// „Rozhýbat" — turns a still image into a short clip via the video job
/// server on SPARK (`video-stack/serve.py`, reached through the AiStack
/// tunnel at llm.ol1n.com/v1/video/*).
///
/// The render is a minutes-long chain of ComfyUI segments plus ffmpeg and
/// RIFE, orchestrated server-side; this client only submits a job and polls.
/// Same event vocabulary as the image backends so the Image Studio provider
/// treats it like a 3D mesh round: a [GenSubmitted] with a durable job id,
/// queue/progress events, then [GenVideoComplete] with the mp4 bytes.
class VideoService {
  static const _baseUrl = 'https://llm.ol1n.com/v1/video';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');
  static const _timeout = Duration(seconds: 30);
  static const _downloadTimeout = Duration(minutes: 3);
  static const _pollInterval = Duration(seconds: 5);

  /// Consecutive failed polls tolerated before the stream gives up with a
  /// [GenInterrupted] (the provider re-attaches via [follow] later).
  static const _maxPollFailures = 6;

  final http.Client _client = http.Client();

  Map<String, String> get _headers {
    if (_cfId.isEmpty || _cfSecret.isEmpty) {
      throw Exception(
        'CF Access credentials not configured. '
        'Build with --dart-define=CF_ACCESS_CLIENT_ID=... --dart-define=CF_ACCESS_CLIENT_SECRET=...',
      );
    }
    return {
      'Content-Type': 'application/json',
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    };
  }

  static String _snippet(http.Response r) {
    String msg = r.body;
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['error'] is String) msg = j['error'] as String;
    } catch (_) {}
    msg = msg.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (msg.length > 160) msg = '${msg.substring(0, 160)}…';
    return 'HTTP ${r.statusCode}${msg.isNotEmpty ? ": $msg" : ""}';
  }

  /// Server-side scene catalog. Throws on network/HTTP failure — the caller
  /// decides whether an empty catalog is fatal (the studio just hides the
  /// button).
  Future<List<VideoScene>> fetchScenes() async {
    final r = await _client
        .get(Uri.parse('$_baseUrl/scenes'), headers: _headers)
        .timeout(_timeout);
    if (r.statusCode != 200) throw Exception(_snippet(r));
    final list = (jsonDecode(r.body) as Map<String, dynamic>)['scenes'] as List;
    return [
      for (final s in list) VideoScene.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// Submit [image] (PNG/JPEG bytes) for [sceneId] and stream it to
  /// completion. [seed] is persisted on the node by the provider so a
  /// re-run is reproducible.
  Stream<GenEvent> animate({
    required Uint8List image,
    required String sceneId,
    required int seed,
  }) async* {
    debugPrint('[video] POST /jobs scene=$sceneId');
    final http.Response r;
    try {
      r = await _client
          .post(
            Uri.parse('$_baseUrl/jobs'),
            headers: _headers,
            body: jsonEncode({
              'scene': sceneId,
              'image': base64Encode(image),
              'seed': seed,
            }),
          )
          .timeout(_timeout);
    } on Exception catch (e) {
      yield GenFailed('Video server nedostupný: $e');
      return;
    }
    if (r.statusCode != 202) {
      yield GenFailed(_snippet(r));
      return;
    }
    final jobId = (jsonDecode(r.body) as Map<String, dynamic>)['job_id'] as String;
    debugPrint('[video] job $jobId accepted');
    yield GenSubmitted(jobId);
    yield* follow(jobId);
  }

  /// Poll job [jobId] until it is done, then download the mp4. Progress is
  /// reported as [GenRunning] (beats finished / beats total); the provider
  /// turns that into „Beat n/m" and, once all beats are in, „slepuji…".
  Stream<GenEvent> follow(String jobId) async* {
    int failures = 0;
    while (true) {
      Map<String, dynamic> j;
      try {
        final r = await _client
            .get(Uri.parse('$_baseUrl/jobs/$jobId'), headers: _headers)
            .timeout(_timeout);
        if (r.statusCode == 404) {
          yield const GenFailed('Video job na serveru už neexistuje');
          return;
        }
        if (r.statusCode != 200) throw Exception(_snippet(r));
        j = jsonDecode(r.body) as Map<String, dynamic>;
        failures = 0;
      } on Exception catch (e) {
        if (++failures >= _maxPollFailures) {
          debugPrint('[video] job $jobId: poll failed $failures× ($e)');
          yield GenInterrupted(jobId);
          return;
        }
        await Future<void>.delayed(_pollInterval);
        continue;
      }

      final status = j['status'] as String;
      final beats = j['beats'] as int? ?? 0;
      switch (status) {
        case 'queued':
          yield GenQueued(j['position'] as int? ?? 0);
        case 'running':
          yield GenRunning(j['beat'] as int? ?? 0, beats);
        case 'error':
          yield GenFailed(j['error'] as String? ?? 'Render selhal');
          return;
        case 'done':
          yield const GenDownloading(0, 1);
          try {
            // Dvakrát: uříznuté stažení projde jako HTTP 200 a mp4 s moov
            // vpředu se i uříznutý tváří přehratelně — ale import do Fotek
            // na něm spadne („unsupported format"). Integrita se proto
            // kontroluje proti content-length i průchodem mp4 atomů.
            Uint8List? bytes;
            for (var attempt = 0; attempt < 2; attempt++) {
              final r = await _client
                  .get(Uri.parse('$_baseUrl/jobs/$jobId/result'), headers: _headers)
                  .timeout(_downloadTimeout);
              if (r.statusCode != 200) throw Exception(_snippet(r));
              final declared = int.tryParse(r.headers['content-length'] ?? '');
              if (mp4LooksComplete(r.bodyBytes, declared)) {
                bytes = r.bodyBytes;
                break;
              }
              debugPrint('[video] job $jobId: neúplné stažení '
                  '(${r.bodyBytes.length}/$declared B), pokus ${attempt + 1}');
            }
            if (bytes == null) {
              throw Exception('stažené video je neúplné');
            }
            debugPrint('[video] job $jobId: ${bytes.length} B mp4');
            yield GenVideoComplete(bytes);
          } on Exception catch (e) {
            debugPrint('[video] job $jobId: download failed ($e)');
            yield GenInterrupted(jobId);
          }
          return;
        default:
          yield GenFailed('Neznámý stav jobu: $status');
          return;
      }
      await Future<void>.delayed(_pollInterval);
    }
  }

  void dispose() => _client.close();
}

/// Whether [bytes] form a structurally complete MP4: the length matches the
/// server-declared one (when known) and the top-level atoms (ftyp/moov/mdat)
/// add up exactly to the file size. A truncated `mdat` still plays (moov is
/// up front) but Photos rejects it on import — catch it before saving.
bool mp4LooksComplete(Uint8List bytes, int? declaredLength) {
  if (declaredLength != null && bytes.length != declaredLength) return false;
  final data = ByteData.sublistView(bytes);
  var pos = 0;
  final seen = <String>{};
  while (pos + 8 <= bytes.length) {
    var size = data.getUint32(pos);
    final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
    seen.add(type);
    if (size == 0) return seen.containsAll(const ['ftyp', 'moov', 'mdat']);
    if (size == 1) {
      if (pos + 16 > bytes.length) return false;
      size = data.getUint64(pos + 8);
    }
    if (size < 8 || pos + size > bytes.length) return false;
    pos += size;
  }
  return pos == bytes.length && seen.containsAll(const ['ftyp', 'moov', 'mdat']);
}

/// True when the error looks like a plain connectivity problem rather than
/// a server-side verdict — used by callers deciding between retry and fail.
bool isNetworkError(Object e) => e is SocketException || e is TimeoutException;
