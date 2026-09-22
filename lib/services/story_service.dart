import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/story_project.dart';
import 'video_service.dart' show mp4LooksComplete;

/// StoryStudio client — minute-long anime stories rendered on SPARK by
/// `video-stack/tools/story.py`, served by the same job server as the
/// „Rozhýbat" scenes (`serve.py`, llm.ol1n.com/v1/video/*).
///
/// A story is one server job that takes most of an hour: keyframes from the
/// cast images (FLUX Kontext), then Wan animation, narration, music and mix.
/// With `review: true` the job stops after the keyframes in status `review`
/// and waits for [approve] — the user sees the shots before an hour of GPU
/// goes into animating them. Jobs are persisted server-side (`jobs/<id>.json`),
/// so the app re-attaches after suspension or a restart of either side.
class StoryService {
  static const _root = String.fromEnvironment(
    'VIDEO_URL',
    defaultValue: 'https://llm.ol1n.com',
  );
  static const _base = '$_root/v1/video';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');
  static const _timeout = Duration(seconds: 30);
  static const _submitTimeout = Duration(minutes: 2);
  static const _downloadTimeout = Duration(minutes: 5);
  static const _pollInterval = Duration(seconds: 10);

  /// Consecutive failed polls tolerated before [StoryInterrupted].
  static const _maxPollFailures = 6;

  StoryService({http.Client? client, Duration? pollInterval})
    : _client = client ?? http.Client(),
      _poll = pollInterval ?? _pollInterval;

  final http.Client _client;
  final Duration _poll;

  /// CF Access is optional so a LAN build (`VIDEO_URL=http://…:8096`) works
  /// without it; through Cloudflare a missing token surfaces as a 403.
  Map<String, String> get _auth => {
    if (_cfId.isNotEmpty) 'CF-Access-Client-Id': _cfId,
    if (_cfSecret.isNotEmpty) 'CF-Access-Client-Secret': _cfSecret,
  };

  static String _text(http.Response r) =>
      utf8.decode(r.bodyBytes, allowMalformed: true);

  static Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(_text(r)) as Map<String, dynamic>;

  /// `serve.py` answers errors as `{"error": "…"}` in Czech.
  static String _snippet(http.Response r) {
    var msg = _text(r);
    try {
      final j = jsonDecode(msg);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    if (r.statusCode == 403 && msg.contains('<')) {
      msg = 'přístup odepřen (CF Access token)';
    }
    msg = msg.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (msg.length > 160) msg = '${msg.substring(0, 160)}…';
    return 'HTTP ${r.statusCode}${msg.isNotEmpty ? ": $msg" : ""}';
  }

  Future<http.Response> _get(String path, {Duration? timeout}) => _client
      .get(Uri.parse('$_base$path'), headers: _auth)
      .timeout(timeout ?? _timeout);

  Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) => _client
      .post(
        Uri.parse('$_base$path'),
        headers: {..._auth, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(timeout ?? _timeout);

  /// Server catalog, in the order the server wants them shown.
  Future<List<StoryInfo>> fetchStories() async {
    final r = await _get('/stories');
    if (r.statusCode == 404) {
      throw const StoryServiceException(
        'Server příběhy zatím nezná (starší video-stack)',
      );
    }
    if (r.statusCode != 200) throw StoryServiceException(_snippet(r));
    return [
      for (final s in (_json(r)['stories'] as List))
        StoryInfo.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// Start a story. [characters] = role → image bytes (PNG/JPEG); roles left
  /// out are played by the server's default picture, if it has one.
  Future<StoryAccepted> submit({
    required String storyId,
    required Map<String, Uint8List> characters,
    required String lang,
    required bool review,
    required bool hd,
    int? seed,
  }) async {
    final r = await _post('/stories/jobs', {
      'story': storyId,
      'characters': {
        for (final e in characters.entries) e.key: base64Encode(e.value),
      },
      'lang': lang,
      'review': review,
      'hd': hd,
      'seed': ?seed,
    }, timeout: _submitTimeout);
    if (r.statusCode != 202) throw StoryServiceException(_snippet(r));
    return StoryAccepted.fromJson(_json(r));
  }

  Future<StoryJobView> job(String jobId) async {
    final r = await _get('/jobs/$jobId');
    if (r.statusCode == 404) throw const StoryJobGoneException();
    if (r.statusCode != 200) throw StoryServiceException(_snippet(r));
    return StoryJobView.fromJson(_json(r));
  }

  /// Poll [jobId] until it needs the user (review) or ends. A run of network
  /// failures ends in [StoryInterrupted] — the job keeps running on SPARK and
  /// the provider re-attaches later, even hours later.
  Stream<StoryJobEvent> follow(String jobId) async* {
    var failures = 0;
    while (true) {
      StoryJobView v;
      try {
        v = await job(jobId);
        failures = 0;
      } on StoryJobGoneException {
        yield const StoryJobFailed('Job na serveru už neexistuje', gone: true);
        return;
      } on Exception catch (e) {
        if (++failures >= _maxPollFailures) {
          debugPrint('[story] job $jobId: poll failed $failures× ($e)');
          yield const StoryInterrupted();
          return;
        }
        await Future<void>.delayed(_poll);
        continue;
      }
      switch (v.status) {
        case 'queued' || 'running':
          yield StoryProgress(v);
        case 'review':
          yield StoryAwaitingReview(v);
          return;
        case 'done':
          yield StoryFinished(v);
          return;
        case 'error':
          final err = v.error?.trim();
          yield StoryJobFailed(
            err == null || err.isEmpty ? 'Render selhal' : err,
          );
          return;
        default:
          yield StoryJobFailed('Neznámý stav jobu: ${v.status}');
          return;
      }
      await Future<void>.delayed(_poll);
    }
  }

  /// The shots waiting for review, with the text each was painted from.
  Future<List<StoryKeyframe>> keyframes(String jobId) async {
    final r = await _get('/jobs/$jobId/keyframes');
    if (r.statusCode != 200) throw StoryServiceException(_snippet(r));
    return [
      for (final s in (_json(r)['shots'] as List))
        StoryKeyframe.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// One keyframe as JPEG.
  Future<Uint8List> keyframeImage(String jobId, String shot) async {
    final r = await _get('/jobs/$jobId/keyframes/$shot');
    if (r.statusCode != 200) throw StoryServiceException(_snippet(r));
    return r.bodyBytes;
  }

  /// After review: no [redo] and no [edits] = animate; otherwise repaint the
  /// listed shots (with a new seed, or from the edited description) and come
  /// back to review.
  Future<void> approve(
    String jobId, {
    List<String> redo = const [],
    Map<String, String> edits = const {},
  }) async {
    final r = await _post('/jobs/$jobId/approve', {
      if (redo.isNotEmpty) 'redo': redo,
      if (edits.isNotEmpty) 'keyframe': edits,
    });
    if (r.statusCode != 202) throw StoryServiceException(_snippet(r));
  }

  /// The finished mp4; [variant] `sub` (burned-in subtitles) or `16x9`.
  /// Checked twice like the scene clips: a truncated body still arrives as
  /// 200 and plays, but Photos rejects it on import.
  Future<Uint8List> result(String jobId, {String variant = ''}) async {
    final q = variant.isEmpty ? '' : '?variant=$variant';
    for (var attempt = 0; ; attempt++) {
      final r = await _get('/jobs/$jobId/result$q', timeout: _downloadTimeout);
      if (r.statusCode != 200) throw StoryServiceException(_snippet(r));
      final declared = int.tryParse(r.headers['content-length'] ?? '');
      if (mp4LooksComplete(r.bodyBytes, declared)) return r.bodyBytes;
      if (attempt >= 1) {
        throw StoryServiceException(
          'stažené video je neúplné (${r.bodyBytes.length}/$declared B)',
        );
      }
    }
  }

  void dispose() => _client.close();
}

class StoryAccepted {
  final String jobId;
  final int shots;
  final int beats;
  final double seconds;
  final int minutesEst;

  const StoryAccepted({
    required this.jobId,
    required this.shots,
    required this.beats,
    required this.seconds,
    required this.minutesEst,
  });

  factory StoryAccepted.fromJson(Map<String, dynamic> j) => StoryAccepted(
    jobId: j['job_id'] as String,
    shots: (j['shots'] as num?)?.toInt() ?? 0,
    beats: (j['beats'] as num?)?.toInt() ?? 0,
    seconds: (j['seconds'] as num?)?.toDouble() ?? 0,
    minutesEst: (j['minutes_est'] as num?)?.toInt() ?? 0,
  );
}

sealed class StoryJobEvent {
  const StoryJobEvent();
}

/// queued or running — the view carries phase and counters.
class StoryProgress extends StoryJobEvent {
  final StoryJobView view;
  const StoryProgress(this.view);
}

/// Keyframes are ready and the job waits for [StoryService.approve].
class StoryAwaitingReview extends StoryJobEvent {
  final StoryJobView view;
  const StoryAwaitingReview(this.view);
}

class StoryFinished extends StoryJobEvent {
  final StoryJobView view;
  const StoryFinished(this.view);
}

class StoryJobFailed extends StoryJobEvent {
  final String message;

  /// The server no longer knows the job (data cleaned up).
  final bool gone;
  const StoryJobFailed(this.message, {this.gone = false});
}

/// Transient: network gone mid-poll. Not a failure — the job keeps running.
class StoryInterrupted extends StoryJobEvent {
  const StoryInterrupted();
}

class StoryServiceException implements Exception {
  final String message;
  const StoryServiceException(this.message);
  @override
  String toString() => message;
}

class StoryJobGoneException implements Exception {
  const StoryJobGoneException();
  @override
  String toString() => 'job na serveru už neexistuje';
}
