import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'filter.dart';
import 'fullscreen.dart';
import 'model.dart';
import 'pad.dart';
import 'playback.dart';
import 'wheel.dart';

/// How the pictures are laid out under the finger.
enum StyleMapMode {
  /// The mosaic: neighbours look alike.
  map(Icons.grid_view, 'Mapa'),

  /// Two measured properties as axes.
  pad(Icons.scatter_plot_outlined, 'Osy'),

  /// A ring of dominant hues, the pictures of one inside.
  hue(Icons.palette_outlined, 'Barvy'),

  /// A ring of clusters, the pictures of one inside.
  clusters(Icons.donut_large, 'Skupiny');

  const StyleMapMode(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// The style picker: a mosaic of every picture of a set, and above it the one
/// under the finger. Sliding across the mosaic walks through neighbouring
/// styles, which is what makes it read as an animation.
///
/// One finger selects, two fingers zoom and pan the mosaic (pinch back out
/// to see it whole again). The bar between the two plays the set as a film
/// along [StyleMapPack.route], or scrubs through it; the icons on the preview
/// swap the mosaic for another layout of the same pictures ([StyleMapMode]).
/// The widget only
/// reports the selection ([onChanged]); what a pick means is the caller's.
class StyleMap extends StatefulWidget {
  const StyleMap({
    super.key,
    required this.pack,
    required this.atlas,
    required this.thumbUrl,
    this.headers = const {},
    this.labelOf,
    this.valueLabel,
    this.onChanged,
  });

  final StyleMapPack pack;

  /// The decoded mosaic ([StyleMapPack.atlasPath]).
  final ui.Image atlas;
  final String Function(StyleMapImage) thumbUrl;

  /// Sent with every preview request (CF Access).
  final Map<String, String> headers;

  /// What to print under the preview; defaults to [StyleMapImage.label]. The
  /// pack only knows registry ids, the caller knows their names.
  final String Function(StyleMapImage)? labelOf;

  /// The name of a facet value the pack only knows by registry id (a model).
  final String Function(String key, StyleMapFacetValue value)? valueLabel;
  final ValueChanged<StyleMapImage>? onChanged;

  /// The touch area holding the mosaic.
  static const mosaicKey = ValueKey('stylemap-mosaic');
  static const playKey = ValueKey('stylemap-play');
  static const filterKey = ValueKey('stylemap-filter');
  static const scrubKey = ValueKey('stylemap-scrub');
  static const fullscreenKey = ValueKey('stylemap-fullscreen');

  @override
  State<StyleMap> createState() => _StyleMapState();
}

class _StyleMapState extends State<StyleMap> {
  /// How long the finger has to rest on a cell before its preview is fetched.
  /// A fast drag crosses dozens of cells a second; those only ever show the
  /// atlas crop, which is already in memory.
  static const _settle = Duration(milliseconds: 90);

  /// A pinch ends one finger at a time, and the last one would otherwise be
  /// read as a selection somewhere under the lifted hand.
  static const _afterPinch = Duration(milliseconds: 250);

  /// Pictures per second the speed button steps through; the full-screen
  /// player has a slider for everything in between.
  static const _speeds = [3.0, 6.0, 12.0];

  late StyleMapImage _selected;

  StyleMapMode _mode = StyleMapMode.map;

  /// What is on screen: the whole set, or what the filter left of it.
  late StyleMapPack _pack = widget.pack;
  StyleMapFilter _filter = const StyleMapFilter();

  /// The cells the filter took away, in grid units, to paint them dark.
  Path? _dimmed;

  static Path _holes(StyleMapPack whole, StyleMapPack left) {
    final path = Path();
    for (final im in whole.images) {
      if (left.at(im.col, im.row) == null) {
        path.addRect(Rect.fromLTWH(im.col.toDouble(), im.row.toDouble(), 1, 1));
      }
    }
    return path;
  }

  Future<void> _openFilter() async {
    _pause();
    final whole = widget.pack;
    final next = await showModalBottomSheet<StyleMapFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (_) => StyleMapFilterSheet(
        pack: whole,
        initial: _filter,
        valueLabel: widget.valueLabel,
        textOf: widget.labelOf,
      ),
    );
    if (next == null || !mounted) return;
    final pack = next.isEmpty
        ? whole
        : whole.where((im) => next.matches(im, whole, textOf: widget.labelOf));
    if (pack.images.isEmpty) return;
    final kept = pack.at(_selected.col, _selected.row) != null;
    setState(() {
      _filter = next;
      _pack = pack;
      _dimmed = next.isEmpty ? null : _holes(whole, pack);
      _playback.reset();
      if (!kept) {
        _selected = pack.nearestTo(_selected.col, _selected.row);
        _sharp = _selected;
      }
      // A filter can leave a wheel with a single sector, or none.
      if (!_modes.contains(_mode)) _mode = StyleMapMode.map;
    });
    if (!kept) widget.onChanged?.call(_selected);
  }

  /// The pad's axes, as indices into the pack's.
  late int _padX = _axisOr('warm', 0);
  late int _padY = _axisOr('lum', 1);

  int _axisOr(String key, int fallback) {
    final k = _pack.axis(key);
    return k >= 0 ? k : fallback.clamp(0, _pack.axes.length - 1);
  }

  /// A mode is only offered when the pack has what it draws.
  List<StyleMapMode> get _modes {
    final pack = _pack;
    return [
      StyleMapMode.map,
      if (pack.axes.length >= 2) StyleMapMode.pad,
      if (pack.hueSectors.length > 1) StyleMapMode.hue,
      if (pack.clusterSectors.length > 1) StyleMapMode.clusters,
    ];
  }

  /// A finger on the pad or the wheel.
  void _pick(StyleMapImage im) {
    _pause();
    _show(im);
  }

  late final _playback = StyleMapPlayback(
    pack: () => _pack,
    current: () => _selected,
    fetch: (im) => precacheImage(_thumb(im), context, onError: (_, _) {}),
    show: (im) {
      if (!mounted) return;
      setState(() {
        _selected = im;
        _sharp = im;
      });
      widget.onChanged?.call(im);
    },
    speed: _speeds[1],
  );

  /// The picture whose sharp preview may be shown — [_selected] once settled.
  StyleMapImage? _sharp;
  Timer? _settleTimer;

  StyleMapView? _view;
  StyleMapView? _gestureStart;
  Offset _gestureAnchor = Offset.zero;
  DateTime _lastPinch = DateTime.fromMillisecondsSinceEpoch(0);
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    _selected = _initial();
    _sharp = _selected;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onChanged?.call(_selected);
      _warm(_selected);
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _playback.dispose();
    super.dispose();
  }

  /// The filled cell nearest the middle of the map.
  StyleMapImage _initial() {
    final pack = _pack;
    final cx = pack.cols / 2, cy = pack.rows / 2;
    return pack.images.reduce((a, b) {
      double d(StyleMapImage m) =>
          (m.col + 0.5 - cx) * (m.col + 0.5 - cx) +
          (m.row + 0.5 - cy) * (m.row + 0.5 - cy);
      return d(a) <= d(b) ? a : b;
    });
  }

  ImageProvider _thumb(StyleMapImage im) =>
      NetworkImage(widget.thumbUrl(im), headers: widget.headers);

  /// Fetch the neighbours ahead of the finger, so the next step is instant.
  void _warm(StyleMapImage im) {
    final pack = _pack;
    final near = {
      ...pack.neighbours(im),
      // The scrub bar steps along the route, not across the grid.
      if (pack.route.length > 2) ...[
        pack.routeFrom(im, 1),
        pack.routeFrom(im, -1),
      ],
    };
    for (final n in near) {
      precacheImage(_thumb(n), context, onError: (_, _) {});
    }
  }

  void _select(Offset local) {
    final view = _view;
    if (view == null) return;
    final u = view.toUnit(local);
    _pause();
    _show(_pack.atUnit(u.dx, u.dy));
  }

  /// Selects [hit] by hand — a finger on the mosaic or on the scrub bar.
  void _show(StyleMapImage? hit) {
    if (hit == null || hit.index == _selected.index) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = hit);
    widget.onChanged?.call(hit);
    _settleTimer?.cancel();
    _settleTimer = Timer(_settle, () {
      if (!mounted) return;
      setState(() => _sharp = hit);
      _warm(hit);
    });
  }

  void _togglePlay() {
    if (_playback.playing) return _pause();
    _settleTimer?.cancel();
    setState(_playback.play);
  }

  void _pause() {
    if (!_playback.playing) return;
    setState(_playback.pause);
  }

  /// The film on the whole screen. It plays what is on the map now — a
  /// filter included — and the map carries on from where it was closed.
  Future<void> _openFullscreen() async {
    _pause();
    _settleTimer?.cancel();
    final closed = await Navigator.of(context).push<StyleMapFullscreenResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StyleMapFullscreen(
          pack: _pack,
          atlas: widget.atlas,
          thumbOf: _thumb,
          start: _selected,
          speed: _playback.speed,
          labelOf: widget.labelOf,
        ),
      ),
    );
    if (closed == null || !mounted) return;
    final moved = closed.image.index != _selected.index;
    setState(() {
      _playback.speed = closed.speed;
      _selected = closed.image;
      _sharp = closed.image;
    });
    if (moved) widget.onChanged?.call(closed.image);
  }

  /// On to the next preset above the current speed — which may be anything,
  /// once the full-screen slider has been at it.
  void _nextSpeed() {
    setState(() {
      _playback.speed = _speeds.firstWhere(
        (v) => v > _playback.speed + 0.5,
        orElse: () => _speeds.first,
      );
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _gestureStart = _view;
    _gestureAnchor = d.localFocalPoint;
    if (d.pointerCount == 1 && !_justPinched) _select(d.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final start = _gestureStart;
    if (start == null) return;
    if (d.pointerCount >= 2) {
      _lastPinch = DateTime.now();
      setState(() {
        _view = start.zoomedAbout(
          _gestureAnchor,
          d.localFocalPoint,
          start.zoom * d.scale,
        );
      });
    } else if (!_justPinched) {
      _select(d.localFocalPoint);
    }
  }

  bool get _justPinched => DateTime.now().difference(_lastPinch) < _afterPinch;

  /// Play / pause, the scrub bar over the route, and the speed.
  Widget _transport(StyleMapPack pack) => SizedBox(
    height: 44,
    child: Row(
      children: [
        IconButton(
          key: StyleMap.playKey,
          onPressed: _togglePlay,
          color: Colors.white,
          icon: Icon(_playback.playing ? Icons.pause : Icons.play_arrow),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              key: StyleMap.scrubKey,
              max: (pack.route.length - 1).toDouble(),
              value: pack.routePosition(_selected).toDouble(),
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChanged: (v) {
                _pause();
                _show(pack.route[v.round()]);
              },
            ),
          ),
        ),
        TextButton(
          onPressed: _nextSpeed,
          child: Text(
            '${_playback.speed.round()}/s',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        IconButton(
          key: StyleMap.fullscreenKey,
          tooltip: 'Na celou obrazovku',
          onPressed: _openFullscreen,
          color: Colors.white,
          icon: const Icon(Icons.fullscreen),
        ),
      ],
    ),
  );

  Widget _modeSwitch() => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in _modes.length > 1 ? _modes : const <StyleMapMode>[])
          IconButton(
            key: ValueKey('stylemap-mode-${mode.name}'),
            tooltip: mode.label,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _mode = mode),
            color: mode == _mode ? Colors.white : Colors.white54,
            icon: Icon(mode.icon, size: 20),
          ),
        IconButton(
          key: StyleMap.filterKey,
          tooltip: 'Filtr',
          visualDensity: VisualDensity.compact,
          onPressed: _openFilter,
          color: _filter.isEmpty ? Colors.white54 : Colors.amber,
          icon: Icon(
            _filter.isEmpty ? Icons.filter_list : Icons.filter_alt,
            size: 20,
          ),
        ),
      ],
    ),
  );

  Widget _mosaic(StyleMapPack pack, StyleMapView view, Size viewport) =>
      SizedBox(
        key: StyleMap.mosaicKey,
        width: viewport.width,
        height: viewport.height,
        // The touch itself selects — a scale gesture only starts once
        // the finger has moved past the slop, and a tap must pick too.
        child: Listener(
          onPointerDown: (e) {
            _pointers++;
            if (_pointers == 1 && !_justPinched) {
              _select(e.localPosition);
            }
          },
          onPointerUp: (_) => _pointers--,
          onPointerCancel: (_) => _pointers--,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: ClipRect(
              child: CustomPaint(
                painter: _MapPainter(
                  atlas: widget.atlas,
                  rect: view.rect,
                  cols: pack.cols,
                  rows: pack.rows,
                  col: _selected.col,
                  row: _selected.row,
                  dimmed: _dimmed,
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return LayoutBuilder(
      builder: (context, box) {
        // The mosaic takes at most half the height; the preview is the point
        // and gets the rest.
        // The pad and the wheel are square.
        final mapHeight =
            (_mode == StyleMapMode.map
                    ? box.maxWidth / pack.aspect
                    : box.maxWidth)
                .clamp(0.0, box.maxHeight * 0.5);
        final viewport = Size(box.maxWidth, mapHeight);
        final view = _view =
            (_view ?? StyleMapView(viewport: viewport, aspect: pack.aspect))
                .resized(viewport);
        final sharp = _sharp?.index == _selected.index;
        return Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: StyleMapCellPainter(
                      widget.atlas,
                      pack.atlasRect(_selected),
                    ),
                  ),
                  if (sharp)
                    Image(
                      key: ValueKey(_selected.index),
                      image: _thumb(_selected),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  Positioned(top: 4, right: 4, child: _modeSwitch()),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 8,
                    child: Text(
                      widget.labelOf?.call(_selected) ?? _selected.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (pack.route.length > 1) _transport(pack),
            switch (_mode) {
              StyleMapMode.map => _mosaic(pack, view, viewport),
              StyleMapMode.pad => SizedBox.fromSize(
                size: viewport,
                child: StyleMapPad(
                  pack: pack,
                  selected: _selected,
                  x: _padX,
                  y: _padY,
                  onPick: _pick,
                  onAxes: (x, y) => setState(() {
                    _padX = x;
                    _padY = y;
                  }),
                ),
              ),
              StyleMapMode.hue || StyleMapMode.clusters => SizedBox.fromSize(
                size: viewport,
                child: StyleMapWheel(
                  pack: pack,
                  atlas: widget.atlas,
                  sectors: _mode == StyleMapMode.hue
                      ? pack.hueSectors
                      : pack.clusterSectors,
                  selected: _selected,
                  onPick: _pick,
                ),
              ),
            },
          ],
        );
      },
    );
  }
}

/// The whole mosaic with the selected cell marked.
class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.atlas,
    required this.rect,
    required this.cols,
    required this.rows,
    required this.col,
    required this.row,
    this.dimmed,
  });

  final ui.Image atlas;
  final Rect rect;
  final int cols, rows, col, row;

  /// Cells to darken, in grid units.
  final Path? dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      atlas,
      Offset.zero & Size(atlas.width.toDouble(), atlas.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final cw = rect.width / cols, ch = rect.height / rows;
    final dimmed = this.dimmed;
    if (dimmed != null) {
      canvas.save();
      canvas.translate(rect.left, rect.top);
      canvas.scale(cw, ch);
      canvas.drawPath(dimmed, Paint()..color = const Color(0xC8000000));
      canvas.restore();
    }
    var cell = Rect.fromLTWH(rect.left + col * cw, rect.top + row * ch, cw, ch);
    // At zoom 1 a cell is a few points wide — the marker stays big enough
    // to find, growing around the cell rather than shrinking with it.
    final grow = ((14 - cw) / 2).clamp(1.0, 14.0);
    cell = cell.inflate(grow);
    canvas.drawRect(
      cell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.black87,
    );
    canvas.drawRect(
      cell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.rect != rect ||
      old.col != col ||
      old.row != row ||
      old.dimmed != dimmed ||
      old.atlas != atlas;
}

/// One cell of the atlas blown up to the preview's size — blurry, but there
/// the instant the finger moves, with the sharp preview drawn over it once it
/// has loaded.
class StyleMapCellPainter extends CustomPainter {
  StyleMapCellPainter(this.atlas, this.src);

  final ui.Image atlas;
  final Rect src;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, src.size, size);
    final dst = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      atlas,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(StyleMapCellPainter old) =>
      old.src != src || old.atlas != atlas;
}
