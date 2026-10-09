import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/stylemap/fullscreen.dart';
import 'package:ol1n_llm/stylemap/model.dart';
import 'package:ol1n_llm/stylemap/pad.dart';
import 'package:ol1n_llm/stylemap/stylemap.dart';
import 'package:ol1n_llm/stylemap/wheel.dart';

/// `test/fixtures/stylemap_map.json` is a manifest the pipeline in
/// `tools/stylemap` really wrote (16 pictures of a lab run on a 4×4 grid),
/// with the picture at cell [3, 3] removed so the grid has a hole.
StyleMapPack _pack() => StyleMapPack.fromJson(
  jsonDecode(File('test/fixtures/stylemap_map.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// The fixture as it would be after `tag_images.py`.
Map<String, dynamic> tagged() {
  final json =
      jsonDecode(File('test/fixtures/stylemap_map.json').readAsStringSync())
          as Map<String, dynamic>;
  // What tag_images.py adds once the VLM has run: every other picture
  // warm, the rest cool, and a keyword on the first.
  final images = (json['images'] as List).cast<Map<String, dynamic>>();
  for (var k = 0; k < images.length; k++) {
    (images[k]['tags'] as Map<String, dynamic>)['palette'] = k.isEven
        ? 'warm'
        : 'cool';
  }
  images.first['words'] = ['chiaroscuro', 'baroque'];
  (json['facets'] as List).add({
    'key': 'palette',
    'label': 'Paleta',
    'values': [
      {'id': 'warm', 'label': 'teplá', 'n': 8},
      {'id': 'cool', 'label': 'studená', 'n': 7},
    ],
  });
  return json;
}

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

    test('the route is the pictures in playing order, without gaps', () {
      final pack = _pack();
      expect(pack.route, hasLength(15));
      for (var k = 1; k < pack.route.length; k++) {
        expect(pack.route[k].route, greaterThan(pack.route[k - 1].route));
        expect(pack.routePosition(pack.route[k]), k);
      }
      // With a picture taken out the numbers skip one, and a position is
      // no longer the number itself.
      final gone = pack.route[3];
      final rest = pack.where((im) => im.index != gone.index);
      expect(rest.route, hasLength(14));
      expect(rest.routePosition(pack.route[4]), 3);
      expect(rest.routePosition(pack.route.last), 13);
    });

    test('the route wraps at both ends', () {
      final pack = _pack();
      expect(pack.routeFrom(pack.route.last, 1).id, pack.route.first.id);
      expect(pack.routeFrom(pack.route.first, -1).id, pack.route.last.id);
      expect(pack.routeFrom(pack.route[3], 2).id, pack.route[5].id);
    });

    test('the pad gives the picture nearest the finger', () {
      final pack = _pack();
      final x = pack.axis('sat'), y = pack.axis('lum');
      expect(pack.axis('no such axis'), -1);
      for (final im in pack.images) {
        final at = pack.padPoint(im, x, y);
        final hit = pack.nearestOnPad(x, y, at);
        // Two pictures may share a spot; the answer is then one of them.
        expect(pack.padPoint(hit, x, y), at);
      }
      // The lightest picture is at the top.
      final lightest = pack.images.reduce(
        (a, b) => a.features[y] >= b.features[y] ? a : b,
      );
      expect(pack.padPoint(lightest, x, y).dy, lessThanOrEqualTo(0.001));
    });

    test('sectors hold every picture once and go round the whole ring', () {
      final pack = _pack();
      for (final sectors in [pack.clusterSectors, pack.hueSectors]) {
        expect(sectors.length, greaterThan(1));
        final ids = [
          for (final s in sectors) ...s.images.map((im) => im.index),
        ];
        expect(ids, hasLength(15));
        expect(ids.toSet(), hasLength(15));
        expect(sectors.first.start, 0);
        expect(sectors.last.start + sectors.last.sweep, closeTo(1, 1e-9));
        for (final s in sectors) {
          expect(s.sweep, greaterThanOrEqualTo(0.03));
          expect(s.holds(s.start + s.sweep / 2), isTrue);
          expect(s.holds(s.start + s.sweep), isFalse);
        }
      }
    });

    test('a sector grid is near square and knows its unfilled end', () {
      // 10 portrait cells (2:3): 4 across, 3 down, the last row half full.
      final grid = StyleMapSectorGrid(10, 2 / 3);
      expect((grid.cols, grid.rows), (4, 3));
      expect(grid.at(0.1, 0.1), 0);
      expect(grid.at(0.9, 0.5), 7);
      expect(grid.at(0.3, 0.9), 9);
      expect(grid.at(0.9, 0.9), isNull);
      expect(StyleMapSectorGrid(1, 2 / 3).cols, 2);
    });

    test('the pipeline manifest carries facets and tags', () {
      final pack = _pack();
      final medium = pack.facets.singleWhere((f) => f.key == 'medium');
      expect(medium.label, 'Médium');
      expect(medium.values.length, greaterThan(1));
      for (final im in pack.images) {
        expect(medium.values.map((v) => v.id), contains(im.tags['medium']));
      }
    });

    test('a filter: any value within a facet, every facet, every word', () {
      final pack = StyleMapPack.fromJson(tagged());
      int count(StyleMapFilter f) =>
          pack.images.where((im) => f.matches(im, pack)).length;

      expect(const StyleMapFilter().isEmpty, isTrue);
      expect(count(const StyleMapFilter()), 15);
      final warm = const StyleMapFilter().toggled('palette', 'warm');
      expect(warm.isEmpty, isFalse);
      expect(count(warm), 8);
      expect(count(warm.toggled('palette', 'cool')), 15);
      // Toggling back off leaves a facet without a choice — no restriction.
      expect(warm.toggled('palette', 'warm').isEmpty, isTrue);

      final medium = pack.images.first.tags['medium']!;
      final both = warm.toggled('medium', medium);
      expect(
        count(both),
        pack.images
            .where(
              (im) =>
                  im.tags['palette'] == 'warm' && im.tags['medium'] == medium,
            )
            .length,
      );

      // The VLM's keywords, a facet value's Czech label without diacritics,
      // a picture's own label.
      expect(count(const StyleMapFilter(query: 'Chiaroscuro baroque')), 1);
      expect(count(const StyleMapFilter(query: 'chiaroscuro rococo')), 0);
      expect(count(const StyleMapFilter(query: 'tepla')), 8);
      final label = pack.images[4].label;
      expect(
        count(StyleMapFilter(query: label)),
        pack.images.where((im) => im.label.contains(label)).length,
      );
      // What the caller adds to the haystack.
      expect(
        pack.images
            .where(
              (im) => const StyleMapFilter(
                query: 'xyzzy',
              ).matches(im, pack, textOf: (im) => im.index == 2 ? 'Xyzzy' : ''),
            )
            .length,
        1,
      );
    });

    test('a filtered pack keeps the cells and loses the pictures', () {
      final pack = StyleMapPack.fromJson(tagged());
      final warm = const StyleMapFilter().toggled('palette', 'warm');
      final left = pack.where((im) => warm.matches(im, pack));
      expect(left.images, hasLength(8));
      expect((left.cols, left.rows), (pack.cols, pack.rows));
      for (final im in pack.images) {
        final there = left.at(im.col, im.row);
        expect(there?.id, im.tags['palette'] == 'warm' ? im.id : null);
      }
      expect(left.route, hasLength(8));
      final gone = pack.images.firstWhere((im) => im.tags['palette'] == 'cool');
      final near = left.nearestTo(gone.col, gone.row);
      expect(near.tags['palette'], 'warm');
    });

    test('a pack with a tour plays that, not the Hilbert curve', () {
      final json =
          jsonDecode(File('test/fixtures/stylemap_map.json').readAsStringSync())
              as Map<String, dynamic>;
      final images = json['images'] as List;
      // The tour the other way round from the order the pictures are listed.
      for (var k = 0; k < images.length; k++) {
        (images[k] as Map<String, dynamic>)['tour'] = images.length - 1 - k;
      }
      final pack = StyleMapPack.fromJson(json);
      expect(pack.route.first.index, pack.images.last.index);
      expect(pack.route.last.index, pack.images.first.index);
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

    Future<List<StyleMapImage>> pump(
      WidgetTester tester,
      StyleMapPack pack,
    ) async {
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
      return picked;
    }

    testWidgets('play walks the route and wraps, a touch stops it', (
      tester,
    ) async {
      final pack = _pack();
      final picked = await pump(tester, pack);
      final start = pack.routePosition(picked.single);

      await tester.tap(find.byKey(StyleMap.playKey));
      // Two seconds at 6 pictures a second, however long a frame waited for
      // its preview: well past the end of a 15-picture route.
      for (var k = 0; k < 40; k++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final played = picked.skip(1).toList();
      expect(played.length, greaterThanOrEqualTo(8));
      for (var k = 0; k < played.length; k++) {
        expect(
          pack.routePosition(played[k]),
          (start + 1 + k) % pack.route.length,
        );
      }

      // A finger on the mosaic takes over.
      final map = tester.getRect(find.byKey(StyleMap.mosaicKey));
      await tester.tapAt(map.center);
      await tester.pump(const Duration(milliseconds: 300));
      final count = picked.length;
      await tester.pump(const Duration(seconds: 1));
      expect(picked, hasLength(count));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('the pad picks by two axes and lets them be changed', (
      tester,
    ) async {
      final pack = _pack();
      final picked = await pump(tester, pack);
      await tester.tap(find.byKey(const ValueKey('stylemap-mode-pad')));
      await tester.pump();

      final warm = pack.axis('warm'), lum = pack.axis('lum');
      final pad = tester.getRect(find.byKey(StyleMapPad.padKey));
      // Top-right corner: the warmest and lightest the set has.
      await tester.tapAt(pad.topRight + const Offset(-13, 13));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        picked.last.id,
        pack.nearestOnPad(warm, lum, const Offset(1, 0)).id,
      );

      await tester.tap(find.text(pack.axes[warm].label));
      await tester.pumpAndSettle();
      final sat = pack.axis('sat');
      await tester.tap(find.text(pack.axes[sat].label));
      await tester.pumpAndSettle();
      await tester.tapAt(pad.bottomLeft + const Offset(13, -13));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        picked.last.id,
        pack.nearestOnPad(sat, lum, const Offset(0, 1)).id,
      );
    });

    testWidgets('the wheel: the ring picks a sector, the grid a picture', (
      tester,
    ) async {
      final pack = _pack();
      final picked = await pump(tester, pack);
      await tester.tap(find.byKey(const ValueKey('stylemap-mode-clusters')));
      await tester.pump();

      final sectors = pack.clusterSectors;
      final wheel = tester.getRect(find.byKey(StyleMapWheel.wheelKey));
      final r = wheel.shortestSide / 2 * (1 - StyleMapWheel.ring / 2);
      Offset onRing(StyleMapSector s) {
        final a = (s.start + s.sweep / 2) * 2 * math.pi;
        return wheel.center + Offset(math.sin(a), -math.cos(a)) * r;
      }

      final other =
          sectors[(StyleMapWheel.sectorOf(sectors, picked.last) + 1) %
              sectors.length];
      await tester.tapAt(onRing(other));
      await tester.pump(const Duration(milliseconds: 200));
      expect(picked.last.id, other.images.first.id);

      // The first cell of the grid inside is that sector's first picture,
      // the one next to it its second.
      final aspect = pack.cellSize.aspectRatio;
      final grid = StyleMapSectorGrid(other.images.length, aspect);
      final rect = StyleMapWheel.gridRect(
        wheel.size,
        grid,
        aspect,
      ).shift(wheel.topLeft);
      final cw = rect.width / grid.cols, ch = rect.height / grid.rows;
      await tester.tapAt(rect.topLeft + Offset(cw * 1.5, ch * 0.5));
      await tester.pump(const Duration(milliseconds: 200));
      expect(picked.last.id, other.images[1].id);
    });

    testWidgets('the filter narrows the map and the playback', (tester) async {
      final pack = StyleMapPack.fromJson(tagged());
      final picked = await pump(tester, pack);

      await tester.tap(find.byKey(StyleMap.filterKey));
      await tester.pumpAndSettle();
      expect(find.text('15 z 15 obrázků'), findsOneWidget);
      await tester.tap(find.text('studená 7'));
      await tester.pump();
      expect(find.text('7 z 15 obrázků'), findsOneWidget);
      await tester.tap(find.text('Použít'));
      await tester.pumpAndSettle();
      // The selection moves onto a picture the filter kept.
      expect(picked.last.tags['palette'], 'cool');

      // A finger on a picture the filter took away selects nothing.
      final map = tester.getRect(find.byKey(StyleMap.mosaicKey));
      final warm = pack.images.firstWhere((im) => im.tags['palette'] == 'warm');
      final cw = map.height * pack.aspect / 4;
      final count = picked.length;
      await tester.tapAt(
        Offset(
          map.center.dx - 2 * cw + (warm.col + 0.5) * cw,
          map.top + (warm.row + 0.5) * 75,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(picked, hasLength(count));

      await tester.tap(find.byKey(StyleMap.playKey));
      for (var k = 0; k < 30; k++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.byKey(StyleMap.playKey));
      await tester.pump();
      expect(picked.length, greaterThan(count + 3));
      expect(
        picked.skip(count).every((im) => im.tags['palette'] == 'cool'),
        isTrue,
      );

      // Clearing brings the whole set back.
      await tester.tap(find.byKey(StyleMap.filterKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zrušit filtr'));
      await tester.pumpAndSettle();
      await tester.tapAt(
        Offset(
          map.center.dx - 2 * cw + (warm.col + 0.5) * cw,
          map.top + (warm.row + 0.5) * 75,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(picked.last.id, warm.id);
    });

    testWidgets('full screen plays on, takes a speed, hands both back', (
      tester,
    ) async {
      final pack = _pack();
      final picked = await pump(tester, pack);
      final start = pack.routePosition(picked.single);

      await tester.tap(find.byKey(StyleMap.fullscreenKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StyleMapFullscreen), findsOneWidget);
      // The map stays in the tree under the player, with a speed of its own.
      Finder inPlayer(Finder f) =>
          find.descendant(of: find.byType(StyleMapFullscreen), matching: f);
      // Starts playing by itself, at the map's speed.
      expect(inPlayer(find.byIcon(Icons.pause)), findsOneWidget);
      expect(inPlayer(find.text('6/s')), findsOneWidget);
      for (var k = 0; k < 20; k++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // The map behind hears nothing while the film runs in front of it.
      expect(picked, hasLength(1));

      // The speed slider, pulled to its far end.
      final bar = tester.getRect(find.byKey(StyleMapFullscreen.speedKey));
      await tester.tapAt(Offset(bar.right - 2, bar.center.dy));
      await tester.pump();
      expect(inPlayer(find.text('24/s')), findsOneWidget);

      // A tap on the picture hides the controls, another brings them back.
      await tester.tapAt(const Offset(400, 200));
      await tester.pump();
      expect(find.byKey(StyleMapFullscreen.speedKey), findsNothing);
      await tester.tapAt(const Offset(400, 200));
      await tester.pump();

      await tester.tap(find.byKey(StyleMapFullscreen.playKey));
      await tester.pump();
      await tester.tap(find.byKey(StyleMapFullscreen.closeKey));
      await tester.pumpAndSettle();
      expect(find.byType(StyleMapFullscreen), findsNothing);

      // Back on the map: where the film stopped, at the speed it had.
      expect(picked, hasLength(2));
      final moved =
          (pack.routePosition(picked.last) - start) % pack.route.length;
      expect(moved, greaterThanOrEqualTo(3));
      expect(find.text(picked.last.label), findsOneWidget);
      expect(find.text('24/s'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      // The speed button steps on from wherever the slider left it.
      await tester.tap(find.text('24/s'));
      await tester.pump();
      expect(find.text('3/s'), findsOneWidget);
    });

    testWidgets('the scrub bar spans the route', (tester) async {
      final pack = _pack();
      final picked = await pump(tester, pack);
      final bar = tester.getRect(find.byKey(StyleMap.scrubKey));

      await tester.tapAt(Offset(bar.right - 1, bar.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(picked.last.id, pack.route.last.id);

      await tester.tapAt(Offset(bar.left + 1, bar.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(picked.last.id, pack.route.first.id);
    });
  });
}
