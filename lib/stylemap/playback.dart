import 'dart:async';
import 'dart:math' as math;

import 'model.dart';

/// Plays a style map as a film: one picture of the route after another, each
/// shown once its preview is there — so the film is sharp, and slows down on
/// a bad connection instead of going blurry.
///
/// Knows nothing about widgets: who owns it says what the pack and the current
/// picture are, how a preview is fetched and what showing one means. The map
/// and its full-screen player both run on it.
class StyleMapPlayback {
  StyleMapPlayback({
    required this.pack,
    required this.current,
    required this.fetch,
    required this.show,
    this.speed = 6,
  });

  /// Asked every frame — a filter swaps the pack under a running film.
  final StyleMapPack Function() pack;
  final StyleMapImage Function() current;

  /// Completes when the preview has arrived, or failed.
  final Future<void> Function(StyleMapImage) fetch;
  final void Function(StyleMapImage) show;

  /// Pictures per second. Changing it takes effect with the next frame.
  double speed;

  static const minSpeed = 1.0;
  static const maxSpeed = 24.0;

  /// How long a frame is held for a preview that has not arrived — past that
  /// the blurry atlas crop is better than a film that stands still.
  static const _maxWait = Duration(milliseconds: 800);

  bool get playing => _playing;
  bool _playing = false;
  Timer? _timer;
  DateTime? _waitingSince;

  /// Previews of the frames ahead: asked for, and of those the ones that
  /// have arrived (or failed — playback does not wait for those either).
  final _requested = <int>{};
  final _ready = <int>{};

  Duration get _frame =>
      Duration(microseconds: (1e6 / speed.clamp(minSpeed, maxSpeed)).round());

  void play() {
    if (_playing) return;
    _playing = true;
    _fetchAhead();
    _timer = Timer(_frame, _advance);
  }

  void pause() {
    _timer?.cancel();
    _waitingSince = null;
    _playing = false;
  }

  /// Forget what was fetched — the pack changed.
  void reset() {
    _requested.clear();
    _ready.clear();
  }

  void dispose() => pause();

  void _advance() {
    if (!_playing) return;
    final next = pack().routeFrom(current(), 1);
    final since = _waitingSince ??= DateTime.now();
    if (!_ready.contains(next.index) &&
        DateTime.now().difference(since) < _maxWait) {
      _timer = Timer(const Duration(milliseconds: 30), _advance);
      return;
    }
    _waitingSince = null;
    show(next);
    if (!_playing) return; // the owner went away while being told
    _fetchAhead();
    _timer = Timer(_frame, _advance);
  }

  void _fetchAhead() {
    final pack = this.pack();
    final from = current();
    // A third of a second ahead at least: eight frames at the slow speeds,
    // more when the film runs fast.
    final ahead = math.max(8, speed.ceil());
    final window = <int, StyleMapImage>{
      for (var k = 1; k <= ahead && k < pack.route.length; k++)
        pack.routeFrom(from, k).index: pack.routeFrom(from, k),
    };
    // Only the window ahead is tracked: the image cache evicts, and a frame
    // that comes round again on the next loop has to be asked for again.
    _requested.retainAll(window.keys);
    _ready.retainAll(window.keys);
    for (final im in window.values) {
      if (!_requested.add(im.index)) continue;
      fetch(im).whenComplete(() {
        if (_requested.contains(im.index)) _ready.add(im.index);
      });
    }
  }
}
