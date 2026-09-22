import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// One shared player for MusicStudio: starting a track stops the previous
/// one. Runs on `video_player` — AVPlayer / ExoPlayer play mp3 just as well,
/// and the app already ships the plugin (no second native audio stack).
final musicPlaybackProvider = ChangeNotifierProvider.autoDispose(
  (ref) => MusicPlayback(),
);

class MusicPlayback extends ChangeNotifier {
  VideoPlayerController? _controller;
  String? _path;
  bool _disposed = false;

  String? get path => _path;

  bool isCurrent(String path) => _path == path;

  bool isPlaying(String path) =>
      _path == path && (_controller?.value.isPlaying ?? false);

  /// 0–1 progress of [path], 0 when it is not the current track.
  double progress(String path) {
    final v = _controller?.value;
    if (_path != path || v == null || !v.isInitialized) return 0;
    final total = v.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (v.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Duration position(String path) => _path == path
      ? (_controller?.value.position ?? Duration.zero)
      : Duration.zero;

  Future<void> toggle(String path) async {
    final c = _controller;
    if (_path == path && c != null && c.value.isInitialized) {
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        // Finished tracks start over instead of sitting at the end.
        if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
        await c.play();
      }
      _notify();
      return;
    }
    await stop();
    final next = VideoPlayerController.file(File(path));
    _controller = next;
    _path = path;
    next.addListener(_notify);
    _notify();
    try {
      await next.initialize();
      if (_controller != next) return; // another track won meanwhile
      await next.play();
    } catch (e) {
      debugPrint('[music] přehrávání $path selhalo: $e');
      if (_controller == next) await stop();
    }
    _notify();
  }

  Future<void> seek(String path, double fraction) async {
    final c = _controller;
    if (_path != path || c == null || !c.value.isInitialized) return;
    await c.seekTo(c.value.duration * fraction.clamp(0.0, 1.0));
    _notify();
  }

  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    _path = null;
    if (c != null) {
      c.removeListener(_notify);
      await c.dispose();
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final c = _controller;
    _controller = null;
    c?.removeListener(_notify);
    c?.dispose();
    super.dispose();
  }
}
