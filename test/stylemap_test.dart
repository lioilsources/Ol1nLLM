import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/stylemap/model.dart';
import 'package:ol1n_llm/stylemap/stylemap.dart';

/// `test/fixtures/stylemap_map.json` is a manifest the pipeline in
/// `tools/stylemap` really wrote (16 pictures of a lab run on a 4×4 grid),
/// with the picture at cell [3, 3] removed so the grid has a hole.
StyleMapPack _pack() => StyleMapPack.fromJson(
  jsonDecode(File('test/fixtures/stylemap_map.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  group('StyleMapPack', () {
    test('reads the pipeline manifest', () {
      final pack = _pack();
      expect((pack.cols, pack.rows), (4, 4));
      expect(pack.images, hasLength(15));
      expect(pack.cellSize, const ui.Size(32, 47));
      expect(pack.axes.map((a) => a.key), containsAll(['lum', 'sat', 'anime']));
      expect(pack.images.first.features, hasLength(pack.axes.length));
      expect(pack.images.first.tag, startsWith('artist:'));
      // 4 columns of 32 px over 4 rows of 47 px.
      expect(pack.aspect, closeTo(32 / 47, 1e-9));
    });

    test('every picture is found at its own cell', () {
      final pack = _pack();
      for (final im in pack.images) {
        expect(pack.at(im.col, im.row)?.id, im.id);
      }
    });

    test('an empty cell and a cell off the grid answer null', () {
      final pack = _pack();
      expect(pack.at(3, 3), isNull);
      expect(pack.at(-1, 0), isNull);
      expect(pack.at(0, 4), isNull);
    });

    test('a point of the mosaic maps to the cell under it', () {
      final pack = _pack();
      final im = pack.at(2, 1)!;
      expect(pack.atUnit(2.5 / 4, 1.5 / 4)?.id, im.id);
      // Just inside the cell's edges still hits it.
      expect(pack.atUnit(2.01 / 4, 1.99 / 4)?.id, im.id);
    });

    test('a finger that slides off the mosaic keeps the edge cell', () {
      final pack = _pack();
      expect(pack.atUnit(-0.3, 0.1)?.id, pack.at(0, 0)!.id);
      expect(pack.atUnit(1.4, 0.1)?.id, pack.at(3, 0)!.id);
      expect(pack.atUnit(1.0, 0.1)?.id, pack.at(3, 0)!.id);
    });

    test('neighbours share an edge and skip the hole', () {
      final pack = _pack();
      final corner = pack.at(3, 2)!; // right edge, above the hole
      final ids = pack.neighbours(corner).map((n) => (n.col, n.row)).toSet();
      expect(ids, {(2, 2), (3, 1)});
    });

    test('preview path and atlas rect follow the picture', () {
      final pack = _pack();
      final im = pack.at(1, 2)!;
      expect(pack.thumbPath(im), 't/${im.index}.webp');
      expect(pack.atlasRect(im), const ui.Rect.fromLTWH(32, 94, 32, 47));
    });

    test('the route visits every picture once', () {
      final pack = _pack();
      expect(pack.images.map((im) => im.route).toSet(), hasLength(15));
    });
  });

  group('StyleMapView', () {
    // A 2:3 mosaic in a viewport wider than it: fitted to the height,
    // centred across.
    const view = StyleMapView(viewport: Size(400, 300), aspect: 2 / 3);

    test('fits the whole mosaic and centres it', () {
      expect(view.rect, const ui.Rect.fromLTWH(100, 0, 200, 300));
      expect(view.toUnit(const ui.Offset(200, 150)), const ui.Offset(0.5, 0.5));
    });

    test('pinching in place keeps the point under the fingers', () {
      const focal = Offset(150, 75); // mosaic point (0.25, 0.25)
      final zoomed = view.zoomedAbout(focal, focal, 3);
      expect(zoomed.zoom, 3);
      final u = zoomed.toUnit(focal);
      expect(u.dx, closeTo(0.25, 1e-9));
      expect(u.dy, closeTo(0.25, 1e-9));
    });

    test('two fingers dragging carry the mosaic with them', () {
      const start = StyleMapView(
        viewport: Size(400, 300),
        aspect: 2 / 3,
        zoom: 4,
        origin: Offset(-200, -450),
      );
      const from = Offset(200, 150), to = Offset(260, 110);
      final moved = start.zoomedAbout(from, to, 4);
      final before = start.toUnit(from), after = moved.toUnit(to);
      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
    });

    test('zoom is clamped and never shows past the mosaic', () {
      expect(view.zoomedAbout(ui.Offset.zero, ui.Offset.zero, 0.2).zoom, 1);
      expect(
        view.zoomedAbout(ui.Offset.zero, ui.Offset.zero, 99).zoom,
        StyleMapView.maxZoom,
      );
      // Dragged far past the top-left corner: the corner stops at the
      // viewport's, it does not come inside.
      final dragged = view
          .zoomedAbout(const ui.Offset(200, 150), const ui.Offset(200, 150), 4)
          .zoomedAbout(const ui.Offset(0, 0), const ui.Offset(900, 900), 4);
      expect(dragged.rect.left, 0);
      expect(dragged.rect.top, 0);
    });

    test('a resize keeps zoom and re-centres', () {
      final resized = view.resized(const ui.Size(200, 300));
      expect(resized.zoom, 1);
      expect(resized.rect, const ui.Rect.fromLTWH(0, 0, 200, 300));
    });
  });

  group('StyleMap widget', () {
    Future<ui.Image> atlas(WidgetTester tester, StyleMapPack pack) async {
      final image = await tester.runAsync(() {
        final rec = ui.PictureRecorder();
        Canvas(rec).drawPaint(Paint()..color = const Color(0xFF336699));
        return rec.endRecording().toImage(
          (pack.cols * pack.cellSize.width).round(),
          (pack.rows * pack.cellSize.height).round(),
        );
      });
      addTearDown(image!.dispose);
      return image;
    }

    testWidgets('a finger sliding across the mosaic walks through cells', (
      tester,
    ) async {
      final pack = _pack();
      final picked = <StyleMapImage>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StyleMap(
              pack: pack,
              atlas: await atlas(tester, pack),
              thumbUrl: (im) => 'http://stylemap.test/${pack.thumbPath(im)}',
              onChanged: picked.add,
            ),
          ),
        ),
      );
      await tester.pump();
      // Starts on a filled cell next to the middle of the grid.
      expect(picked, hasLength(1));
      expect(picked.single.col, inInclusiveRange(1, 2));

      // The mosaic is the lower half of the 800×600 test surface: 300 high,
      // so 4 rows of 75 and — at 32:47 — 4 columns of ~51, centred.
      final map = tester.getRect(find.byKey(StyleMap.mosaicKey));
      expect(map.height, 300);
      final cw = map.height * pack.aspect / 4;
      final left = map.center.dx - 2 * cw;
      Offset cell(int col, int row) =>
          Offset(left + (col + 0.5) * cw, map.top + (row + 0.5) * 75);

      final finger = await tester.startGesture(cell(0, 0));
      await tester.pump();
      for (var col = 1; col < 4; col++) {
        await finger.moveTo(cell(col, 0));
        await tester.pump();
      }
      // Onto the hole at [3, 3]: nothing new is selected.
      await finger.moveTo(cell(3, 3));
      await tester.pump();
      await finger.up();
      await tester.pump(const Duration(milliseconds: 200));

      expect(picked.skip(1).map((im) => (im.col, im.row)), [
        (0, 0),
        (1, 0),
        (2, 0),
        (3, 0),
      ]);
      expect(find.text(pack.at(3, 0)!.label), findsOneWidget);
    });
  });
}
