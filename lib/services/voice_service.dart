import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/voice.dart';
import 'music_service.dart';

/// Voice Studio client — speech on the AiStack audio service
/// (`/v1/audio/tts`, `/v1/audio/voices`), the same orchestrator and job
/// queue as MusicStudio, so polling and downloads go through [MusicService].
///
/// CPU voices (Kokoro, Piper) are up whenever the service is; the cloning
/// engines (XTTS-v2, Chatterbox) need the GPU and run only in some SPARK
/// profiles — the server then refuses the request at once with a 503 and a
/// sentence for the user, never a job that fails after queueing.
class VoiceService {
  static const _base = '${MusicService.root}/v1/audio';
  static const _timeout = Duration(seconds: 30);
  static const _uploadTimeout = Duration(minutes: 2);

  /// Pause before the one retry of a failed synthesis: a restarted engine
  /// container answers again after about 15 s.
  static const _retryDelay = Duration(seconds: 15);

  VoiceService({
    http.Client? client,
    Duration? pollInterval,
    Duration? retryDelay,
  }) : _client = client ?? http.Client(),
       _retry = retryDelay ?? _retryDelay {
    _jobs = MusicService(client: _client, pollInterval: pollInterval);
  }

  final http.Client _client;
  final Duration _retry;
  late final MusicService _jobs;

  Map<String, String> get _auth => MusicService.auth;

  Never _fail(http.Response r) =>
      throw VoiceServiceException(MusicService.errorSnippet(r));

  /// Every voice the server knows: presets, the GPU engines' built-in voices
  /// (only while their container runs) and stored clones.
  Future<List<Voice>> voices() async {
    final r = await _client
        .get(Uri.parse('$_base/voices'), headers: _auth)
        .timeout(_timeout);
    if (r.statusCode != 200) _fail(r);
    return Voice.fromRows(jsonDecode(MusicService.bodyText(r)) as List);
  }

  Future<StoredVoice> stored(String voiceId) async {
    final r = await _client
        .get(Uri.parse('$_base/voices/$voiceId'), headers: _auth)
        .timeout(_timeout);
    if (r.statusCode != 200) _fail(r);
    return StoredVoice.fromJson(MusicService.bodyJson(r));
  }

  /// Store a reference sample as voice [voiceId]. The server trims silence,
  /// keeps ≤ 30 s and normalises; `rights` and `source` are mandatory and
  /// travel into the manifest of every job that uses the voice.
  Future<StoredVoice> upload({
    required File sample,
    required String fileName,
    required String voiceId,
    required String name,
    required String language,
    required String rights,
    required String source,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/voices'))
      ..headers.addAll(_auth)
      ..fields.addAll({
        'voice_id': voiceId,
        'name': name,
        'language': language,
        'rights': rights,
        'source': source,
      })
      ..files.add(
        await http.MultipartFile.fromPath(
          'sample',
          sample.path,
          filename: fileName,
        ),
      );
    final r = await http.Response.fromStream(
      await _client.send(req).timeout(_uploadTimeout),
    );
    if (r.statusCode != 201) _fail(r);
    return StoredVoice.fromJson(MusicService.bodyJson(r));
  }

  Future<void> delete(String voiceId) async {
    final r = await _client
        .delete(Uri.parse('$_base/voices/$voiceId'), headers: _auth)
        .timeout(_timeout);
    // Already gone is what was asked for.
    if (r.statusCode != 200 && r.statusCode != 404) _fail(r);
  }

  /// The stored reference (mono WAV) of a cloned voice.
  Future<Uint8List> reference(String voiceId) =>
      _guard(() => _jobs.download('/v1/audio/voices/$voiceId/sample'));

  /// Synthesise [body] (see [speechRequest]) and return the audio bytes.
  /// One call, start to finish: a piece of speech takes seconds, so unlike a
  /// composition there is no job to resume later.
  ///
  /// A job that was accepted and then died is tried once more after a pause:
  /// that is what an engine container restarting mid-sentence looks like
  /// (seen 2026-10-06, "chatterbox nedostupný: Server disconnected"). A
  /// request the server *refuses* is not retried — a 503 says in words that
  /// the voice is not running now, and waiting would only delay that answer.
  Future<Uint8List> speak(Map<String, dynamic> body) async {
    try {
      return await _speakOnce(body);
    } on VoiceServiceException catch (e) {
      if (!e.transient) rethrow;
      debugPrint('[voice] syntéza selhala (${e.detail}), zkouším znovu');
      await Future<void>.delayed(_retry);
      return _speakOnce(body);
    }
  }

  Future<Uint8List> _speakOnce(Map<String, dynamic> body) async {
    final r = await _client
        .post(
          Uri.parse('$_base/tts'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (r.statusCode != 202) _fail(r);
    final jobId = MusicService.bodyJson(r)['job_id'] as String;
    await for (final event in _jobs.follow(jobId)) {
      switch (event) {
        case MusicQueued() || MusicRunning():
          break;
        case MusicFailed(:final message):
          // The job's own error is the orchestrator talking to itself
          // ("varianta 0: chatterbox → HTTP 502 …"), not a sentence for a
          // reader; it stays in the log.
          throw VoiceServiceException(
            'Hlas se nepodařilo přečíst, zkus to znovu.',
            transient: true,
            detail: message,
          );
        case MusicInterrupted():
          throw const VoiceServiceException(
            'Spojení se serverem vypadlo, zkus to znovu.',
            transient: true,
          );
        case MusicDone(:final job):
          final output = (job['outputs'] as List?)?.firstOrNull;
          if (output is! Map || output['url'] is! String) {
            throw const VoiceServiceException('Server nevrátil žádný zvuk');
          }
          return _guard(
            () => _jobs.download(
              output['url'] as String,
              expectedBytes: (output['bytes'] as num?)?.toInt(),
            ),
          );
      }
    }
    throw const VoiceServiceException('Syntéza skončila bez výsledku');
  }

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on MusicServiceException catch (e) {
      throw VoiceServiceException(e.message);
    }
  }

  void dispose() => _client.close();
}

class VoiceServiceException implements Exception {
  final String message;

  /// The job was accepted and then failed — worth one more try.
  final bool transient;

  /// The server's own wording when [message] replaces it.
  final String? detail;

  const VoiceServiceException(
    this.message, {
    this.transient = false,
    this.detail,
  });
  @override
  String toString() => message;
}
