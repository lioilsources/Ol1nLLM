import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'model.dart';

/// The style picker: a mosaic of every picture of a set, and above it the one
/// under the finger. Sliding across the mosaic walks through neighbouring
/// styles, which is what makes it read as an animation.
///
/// One finger selects, two fingers zoom and pan the mosaic (pinch back out
/// to see it whole again). The widget only
/// reports the selection ([onChanged]); what a pick means is the caller's.
class StyleMap extends StatefulWidget {
  const StyleMap({
    super.key,
    required this.pack,
    required this.atlas,
    required this.thumbUrl,
    this.headers = const {},
    this.labelOf,
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
  final ValueChanged<StyleMapImage>? onChanged;

  /// The touch area holding the mosaic.
  static const mosaicKey = ValueKey('stylemap-mosaic');

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

  late StyleMapImage _selected;

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
    super.dispose();
  }

  /// The filled cell nearest the middle of the map.
  StyleMapImage _initial() {
    final pack = widget.pack;
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
    for (final n in widget.pack.neighbours(im)) {
      precacheImage(_thumb(n), context, onError: (_, _) {});
    }
  }

  void _select(Offset local) {
    final view = _view;
    if (view == null) return;
    final u = view.toUnit(local);
    final hit = widget.pack.atUnit(u.dx, u.dy);
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

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    return LayoutBuilder(
      builder: (context, box) {
        // The mosaic takes at most half the height; the preview is the point
        // and gets the rest.
        final mapHeight = (box.maxWidth / pack.aspect).clamp(
          0.0,
          box.maxHeight * 0.5,
        );
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
                    painter: _CellPainter(
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
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
  });

  final ui.Image atlas;
  final Rect rect;
  final int cols, rows, col, row;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      atlas,
      Offset.zero & Size(atlas.width.toDouble(), atlas.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final cw = rect.width / cols, ch = rect.height / rows;
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
      old.atlas != atlas;
}

/// One cell of the atlas blown up to the preview's size — blurry, but there
/// the instant the finger moves, with the sharp preview drawn over it once it
/// has loaded.
class _CellPainter extends CustomPainter {
  _CellPainter(this.atlas, this.src);

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
  bool shouldRepaint(_CellPainter old) => old.src != src || old.atlas != atlas;
}
