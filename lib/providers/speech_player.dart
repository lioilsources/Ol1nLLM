import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/voice.dart';
import '../widgets/music_playback.dart';
import 'voice_studio_provider.dart';

/// One reader for the whole app: starting an answer stops the one before.
/// AutoDispose like the player it drives, and listening to it keeps that
/// player alive for as long as something is being read.
final speechPlayerProvider = ChangeNotifierProvider.autoDispose<SpeechPlayer>((
  ref,
) {
  ref.listen(musicPlaybackProvider, (_, _) {});
  return SpeechPlayer(
    synthesise: ref.read(voiceStudioProvider.notifier).speakPrepared,
    output: ref.read(musicPlaybackProvider),
  );
});

enum SpeechStatus {
  idle,

  /// Waiting for audio — the first piece, or the next one mid-answer.
  loading,
  playing,
  paused,
}

/// Reads an answer aloud piece by piece (see [speechChunks]): the pieces are
/// synthesised in order, one at a time, and each plays as soon as it is ready
/// and the one before has finished. Sound starts after the first short piece
/// instead of after the whole answer.
class SpeechPlayer extends ChangeNotifier {
  SpeechPlayer({required this.synthesise, required this.output}) {
    output.addListener(_onOutput);
  }

  /// Audio file for one prepared piece of text in a voice.
  final Future<String> Function(String spoken, String voiceId) synthesise;
  final AudioOutput output;

  /// Bumped whenever what is being read changes; loops of an older reading
  /// see it and step aside.
  int _session = 0;
  String? _key;

  /// File of the piece playing now; null while waiting for one.
  String? _path;

  /// [_path] was handed to the output and it took it.
  bool _started = false;
  bool _paused = false;
  Completer<void>? _pieceDone;
  ({String key, String message})? _error;
  bool _disposed = false;

  /// [variant] tells apart readings of the same text in the same voice that
  /// sound different (the rhythm it is read in).
  static String keyOf(String text, String voiceId, [String variant = '']) =>
      '$voiceId\n$variant\n$text';

  SpeechStatus status(String key) {
    if (key != _key) return SpeechStatus.idle;
    final path = _path;
    if (path == null) return SpeechStatus.loading;
    if (_paused) return SpeechStatus.paused;
    return output.isPlaying(path) ? SpeechStatus.playing : SpeechStatus.loading;
  }

  /// Why reading [key] stopped, once — the button that asked shows it.
  String? takeError(String key) {
    final e = _error;
    if (e == null || e.key != key) return null;
    _error = null;
    return e.message;
  }

  /// Start reading, pause / resume it, or — while it is still waiting for
  /// audio — give up on it.
  Future<void> toggle(
    String text,
    String voiceId, {
    String variant = '',
  }) async {
    final key = keyOf(text, voiceId, variant);
    if (key == _key) {
      final path = _path;
      if (path == null || !_started) return stop();
      _paused = !_paused;
      _notify();
      return output.toggle(path);
    }
    await stop();
    final chunks = speechChunks(speakableText(text));
    if (chunks.isEmpty) {
      _error = (key: key, message: 'V odpovědi není co číst.');
      _notify();
      return;
    }
    final session = ++_session;
    _key = key;
    _notify();
    unawaited(_read(session, key, chunks, voiceId));
  }

  Future<void> stop() async {
    _session++;
    final path = _path;
    _reset();
    _notify();
    if (path != null && output.path == path) await output.stop();
  }

  Future<void> _read(
    int session,
    String key,
    List<String> chunks,
    String voiceId,
  ) async {
    final ready = [for (final _ in chunks) Completer<String>()];
    for (final r in ready) {
      // A piece that fails after reading was stopped has no one to tell.
      r.future.ignore();
    }
    // Producer: strictly one piece at a time. The engine works through its
    // queue in order anyway, and stopping then wastes one piece at most.
    unawaited(() async {
      for (var i = 0; i < chunks.length; i++) {
        if (session != _session) return;
        try {
          ready[i].complete(await synthesise(chunks[i], voiceId));
        } catch (e) {
          ready[i].completeError(e);
          return;
        }
      }
    }());
    try {
      for (final r in ready) {
        final path = await r.future;
        if (session != _session) return;
        final done = _pieceDone = Completer<void>();
        _path = path;
        _started = false;
        _notify();
        await output.toggle(path);
        if (session != _session) return;
        // The player could not open the file.
        if (output.path != path) break;
        _started = true;
        _onOutput();
        await done.future;
        if (session != _session) return;
        _path = null;
        _notify();
      }
    } catch (e) {
      if (session != _session) return;
      _error = (key: key, message: '$e');
    }
    if (session != _session) return;
    _session++;
    _reset();
    _notify();
  }

  void _onOutput() {
    final path = _path;
    final done = _pieceDone;
    if (path == null || !_started || done == null || done.isCompleted) return;
    if (output.path != path) {
      // Something else took the player (music, another screen's stop).
      _session++;
      _reset();
    } else if (output.isCompleted(path)) {
      done.complete();
      return;
    }
    _notify();
  }

  void _reset() {
    _key = null;
    _path = null;
    _started = false;
    _paused = false;
    _pieceDone = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    output.removeListener(_onOutput);
    super.dispose();
  }
}
