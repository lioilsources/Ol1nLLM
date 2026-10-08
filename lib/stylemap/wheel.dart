import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model.dart';

/// The wheel: a ring cut into sectors (clusters, or dominant hues), and
/// inside it the pictures of the sector the selection is in. The ring picks a
/// neighbourhood, the grid inside picks a picture — two steps instead of
/// hunting for a 6-point cell among thousands.
class StyleMapWheel extends StatefulWidget {
  const StyleMapWheel({
    super.key,
    required this.pack,
    required this.atlas,
    required this.sectors,
    required this.selected,
    required this.onPick,
  });

  final StyleMapPack pack;
  final ui.Image atlas;
  final List<StyleMapSector> sectors;
  final StyleMapImage selected;
  final ValueChanged<StyleMapImage> onPick;

  static const wheelKey = ValueKey('stylemap-wheel');

  /// Width of the ring, as a share of the wheel's radius.
  static const ring = 0.2;

  /// The sector holding [im] (every picture is in exactly one).
  static int sectorOf(List<StyleMapSector> sectors, StyleMapImage im) {
    final k = sectors.indexWhere(
      (s) => s.images.any((o) => o.index == im.index),
    );
    return k < 0 ? 0 : k;
  }

  /// The rectangle the sector's grid is drawn in: the largest one of the
  /// grid's shape that fits inside the ring.
  static Rect gridRect(Size size, StyleMapSectorGrid grid, double cellAspect) {
    final r = size.shortestSide / 2 * (1 - ring) - 6;
    final aspect = grid.cols * cellAspect / grid.rows;
    // Half-diagonal of a w×h rectangle is r: w = 2r·a/√(a²+1).
    final h = 2 * r / math.sqrt(aspect * aspect + 1);
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: h * aspect,
      height: h,
    );
  }

  @override
  State<StyleMapWheel> createState() => _StyleMapWheelState();
}

class _StyleMapWheelState extends State<StyleMapWheel> {
  /// A drag that began on the ring stays a ring drag when the finger wanders
  /// inside, and the other way round.
  bool _onRing = false;

  void _touch(Offset p, Size size, {required bool down}) {
    final sectors = widget.sectors;
    final c = size.center(Offset.zero);
    final d = p - c;
    final outer = size.shortestSide / 2;
    if (down) _onRing = d.distance > outer * (1 - StyleMapWheel.ring);
    final current = StyleMapWheel.sectorOf(sectors, widget.selected);
    if (_onRing) {
      // Turns clockwise from the top.
      final turn = (math.atan2(d.dx, -d.dy) / (2 * math.pi)) % 1.0;
      final k = sectors.indexWhere((s) => s.holds(turn));
      if (k >= 0 && k != current) widget.onPick(sectors[k].images.first);
      return;
    }
    final sector = sectors[current];
    final grid = StyleMapSectorGrid(
      sector.images.length,
      widget.pack.cellSize.aspectRatio,
    );
    final rect = StyleMapWheel.gridRect(
      size,
      grid,
      widget.pack.cellSize.aspectRatio,
    );
    final k = grid.at(
      (p.dx - rect.left) / rect.width,
      (p.dy - rect.top) / rect.height,
    );
    if (k != null) widget.onPick(sector.images[k]);
  }

  @override
  Widget build(BuildContext context) {
    final sectors = widget.sectors;
    final current = StyleMapWheel.sectorOf(sectors, widget.selected);
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return Listener(
          key: StyleMapWheel.wheelKey,
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _touch(e.localPosition, size, down: true),
          onPointerMove: (e) => _touch(e.localPosition, size, down: false),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _WheelPainter(
                  pack: widget.pack,
                  atlas: widget.atlas,
                  sectors: sectors,
                  current: current,
                  selected: widget.selected,
                ),
              ),
              Positioned(
                left: 8,
                bottom: 4,
                child: Text(
                  '${sectors[current].label} · ${sectors[current].images.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.pack,
    required this.atlas,
    required this.sectors,
    required this.current,
    required this.selected,
  });

  final StyleMapPack pack;
  final ui.Image atlas;
  final List<StyleMapSector> sectors;
  final int current;
  final StyleMapImage selected;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 2;
    final width = size.shortestSide / 2 * StyleMapWheel.ring - 6;
    final arc = Rect.fromCircle(center: c, radius: outer - width / 2);
    const gap = 0.004; // turns
    for (var k = 0; k < sectors.length; k++) {
      final s = sectors[k];
      final on = k == current;
      canvas.drawArc(
        arc,
        (s.start + gap / 2) * 2 * math.pi - math.pi / 2,
        math.max(s.sweep - gap, 0.002) * 2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? width : width * 0.6
          ..color = s.color.withValues(alpha: on ? 1 : 0.55),
      );
    }

    final sector = sectors[current];
    final aspect = pack.cellSize.aspectRatio;
    final grid = StyleMapSectorGrid(sector.images.length, aspect);
    final rect = StyleMapWheel.gridRect(size, grid, aspect);
    final cw = rect.width / grid.cols, ch = rect.height / grid.rows;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    Rect? marked;
    for (var k = 0; k < sector.images.length; k++) {
      final im = sector.images[k];
      final dst = Rect.fromLTWH(
        rect.left + (k % grid.cols) * cw,
        rect.top + (k ~/ grid.cols) * ch,
        cw,
        ch,
      );
      canvas.drawImageRect(atlas, pack.atlasRect(im), dst, paint);
      if (im.index == selected.index) marked = dst;
    }
    if (marked != null) {
      canvas.drawRect(
        marked,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.black87,
      );
      canvas.drawRect(
        marked,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.selected.index != selected.index ||
      old.current != current ||
      old.sectors != sectors ||
      old.atlas != atlas;
}
