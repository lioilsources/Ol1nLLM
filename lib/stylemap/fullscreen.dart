import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;

import 'model.dart';
import 'playback.dart';
import 'stylemap.dart' show StyleMapCellPainter;

/// Where the full-screen player was when it closed, so the map can carry on
/// from there.
class StyleMapFullscreenResult {
  const StyleMapFullscreenResult(this.image, this.speed);
  final StyleMapImage image;
  final double speed;
}

/// The film of a style map on the whole screen: nothing but the picture, with
/// the controls over it until a tap sends them away. Starts playing at once.
class StyleMapFullscreen extends StatefulWidget {
  const StyleMapFullscreen({
    super.key,
    required this.pack,
    required this.atlas,
    required this.thumbOf,
    required this.start,
    this.speed = 6,
    this.labelOf,
  });

  /// What plays — the whole set, or what a filter left of it.
  final StyleMapPack pack;
  final ui.Image atlas;
  final ImageProvider Function(StyleMapImage) thumbOf;
  final StyleMapImage start;
  final double speed;
  final String Function(StyleMapImage)? labelOf;

  static const speedKey = ValueKey('stylemap-full-speed');
  static const playKey = ValueKey('stylemap-full-play');
  static const closeKey = ValueKey('stylemap-full-close');

  @override
  State<StyleMapFullscreen> createState() => _StyleMapFullscreenState();
}

class _StyleMapFullscreenState extends State<StyleMapFullscreen> {
  late StyleMapImage _current = widget.start;
  bool _controls = true;

  late final _playback = StyleMapPlayback(
    pack: () => widget.pack,
    current: () => _current,
    fetch: (im) =>
        precacheImage(widget.thumbOf(im), context, onError: (_, _) {}),
    show: (im) {
      if (mounted) setState(() => _current = im);
    },
    speed: widget.speed,
  );

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_playback.play);
    });
  }

  @override
  void dispose() {
    _playback.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _close() => Navigator.of(
    context,
  ).pop(StyleMapFullscreenResult(_current, _playback.speed));

  void _toggle() =>
      setState(() => _playback.playing ? _playback.pause() : _playback.play());

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    return PopScope(
      // The system back gesture hands the position back too.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _controls = !_controls),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: StyleMapCellPainter(
                  widget.atlas,
                  pack.atlasRect(_current),
                ),
              ),
              Image(
                key: ValueKey(_current.index),
                image: widget.thumbOf(_current),
                fit: BoxFit.contain,
                // The preview is small; let the screen smooth it rather
                // than show its pixels.
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              if (_controls) ...[
                Positioned(top: 0, left: 0, right: 0, child: _top(context)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _bottom(context, pack),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _top(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: Colors.black45),
    child: SafeArea(
      bottom: false,
      child: Row(
        children: [
          IconButton(
            key: StyleMapFullscreen.closeKey,
            tooltip: 'Zavřít',
            onPressed: _close,
            color: Colors.white,
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              widget.labelOf?.call(_current) ?? _current.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    ),
  );

  Widget _bottom(BuildContext context, StyleMapPack pack) {
    final theme = SliderTheme.of(context).copyWith(
      trackHeight: 2,
      overlayShape: SliderComponentShape.noOverlay,
      activeTrackColor: Colors.white,
      inactiveTrackColor: Colors.white24,
      thumbColor: Colors.white,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black45),
      child: SafeArea(
        top: false,
        child: SliderTheme(
          data: theme,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    key: StyleMapFullscreen.playKey,
                    onPressed: _toggle,
                    color: Colors.white,
                    icon: Icon(
                      _playback.playing ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      max: (pack.route.length - 1).toDouble(),
                      value: pack.routePosition(_current).toDouble(),
                      onChanged: (v) => setState(() {
                        _playback.pause();
                        _current = pack.route[v.round()];
                      }),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
              Row(
                children: [
                  const SizedBox(
                    width: 48,
                    child: Icon(Icons.speed, color: Colors.white70, size: 20),
                  ),
                  Expanded(
                    child: Slider(
                      key: StyleMapFullscreen.speedKey,
                      min: StyleMapPlayback.minSpeed,
                      max: StyleMapPlayback.maxSpeed,
                      divisions:
                          (StyleMapPlayback.maxSpeed -
                                  StyleMapPlayback.minSpeed)
                              .round(),
                      value: _playback.speed,
                      onChanged: (v) => setState(() => _playback.speed = v),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${_playback.speed.round()}/s',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
