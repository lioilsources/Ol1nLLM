import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import 'model.dart';

/// The pad: every picture a dot placed by two measured properties, one per
/// axis. Where the map answers „what looks like this", the pad answers
/// „darker", „more saturated", „more like a photo" — the finger gets the
/// picture nearest to where it is.
class StyleMapPad extends StatelessWidget {
  const StyleMapPad({
    super.key,
    required this.pack,
    required this.selected,
    required this.x,
    required this.y,
    required this.onPick,
    required this.onAxes,
  });

  final StyleMapPack pack;
  final StyleMapImage selected;

  /// Indices into [StyleMapPack.axes].
  final int x, y;
  final ValueChanged<StyleMapImage> onPick;
  final void Function(int x, int y) onAxes;

  static const padKey = ValueKey('stylemap-pad');
  static const _inset = 12.0;

  Future<void> _choose(BuildContext context, bool horizontal) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var k = 0; k < pack.axes.length; k++)
              ListTile(
                dense: true,
                title: Text(
                  pack.axes[k].label,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: k == (horizontal ? x : y)
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
                onTap: () => Navigator.of(context).pop(k),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    horizontal ? onAxes(picked, y) : onAxes(x, picked);
  }

  @override
  Widget build(BuildContext context) {
    Widget axis(IconData icon, int k, bool horizontal) => Expanded(
      child: InkWell(
        onTap: () => _choose(context, horizontal),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  pack.axes[k].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            axis(Icons.swap_horiz, x, true),
            axis(Icons.swap_vert, y, false),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final area = (Offset.zero & box.biggest).deflate(_inset);
              void pick(Offset p) => onPick(
                pack.nearestOnPad(
                  x,
                  y,
                  Offset(
                    (p.dx - area.left) / area.width,
                    (p.dy - area.top) / area.height,
                  ),
                ),
              );
              return Listener(
                key: padKey,
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => pick(e.localPosition),
                onPointerMove: (e) => pick(e.localPosition),
                child: CustomPaint(
                  size: box.biggest,
                  painter: _PadPainter(pack, selected, x, y, area),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.pack, this.selected, this.x, this.y, this.area);

  final StyleMapPack pack;
  final StyleMapImage selected;
  final int x, y;
  final Rect area;

  Offset _at(StyleMapImage im) {
    final p = pack.padPoint(im, x, y);
    return Offset(area.left + p.dx * area.width, area.top + p.dy * area.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      area,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white12,
    );
    // One draw call per cluster rather than one per picture.
    final colors = {for (final c in pack.clusters) c.id: c.color};
    final byCluster = <int, List<Offset>>{};
    for (final im in pack.images) {
      (byCluster[im.cluster] ??= []).add(_at(im));
    }
    final radius = pack.images.length > 1000 ? 3.0 : 5.0;
    byCluster.forEach((cluster, points) {
      canvas.drawPoints(
        PointMode.points,
        points,
        Paint()
          ..strokeWidth = radius
          ..strokeCap = StrokeCap.round
          ..color = (colors[cluster] ?? Colors.white70).withValues(alpha: 0.8),
      );
    });
    final at = _at(selected);
    canvas.drawCircle(at, 9, Paint()..color = Colors.black87);
    canvas.drawCircle(
      at,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.selected.index != selected.index ||
      old.x != x ||
      old.y != y ||
      old.area != area ||
      old.pack != pack;
}
