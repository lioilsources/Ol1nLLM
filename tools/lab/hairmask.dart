// Builds the Kadeřník masks for one reference from its face-parsing output,
// with the app's own code (lib/models/hair_mask.dart) — `lab hairmasks` does
// the network part and runs this for the geometry:
//
//   ANALYSIS_DIR=… PHOTO=ref.png HAIR_FILE=candidates/hairstyles.json OUT_DIR=… \
//     flutter test tools/lab/hairmask.dart
//
// Writes <shape key>.png for every distinct shape in HAIR_FILE plus
// masks.json: {colour, shapes: {key: {file, area} | {error}}}. A refused shape
// (no face, too little hair) is recorded, not fatal — the dump skips its cells
// with the reason.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ol1n_llm/models/hair_mask.dart';

import 'hair_candidates.dart';

void main() {
  test('build hair masks', () {
    final env = Platform.environment;
    final analysis = Directory(env['ANALYSIS_DIR']!);
    BoolMask load(String name) =>
        decodeMaskPng(File('${analysis.path}/$name.png').readAsBytesSync());
    final a = HairAnalysis(
      hair: load('hair'),
      face: load('face'),
      hat: load('hat'),
      features: load('features'),
    );
    final out = Directory(env['OUT_DIR']!)..createSync(recursive: true);
    final cands = parseHairCandidates(
      jsonDecode(File(env['HAIR_FILE']!).readAsStringSync()) as List<dynamic>,
    );

    String? colour;
    final photo = img.decodeImage(File(env['PHOTO']!).readAsBytesSync());
    if (photo != null) {
      final oriented = img.bakeOrientation(photo);
      if (oriented.width == a.hair.w && oriented.height == a.hair.h) {
        colour = estimateHairColour(oriented, a.hair);
      }
    }

    final shapes = <String, Map<String, dynamic>>{};
    for (final c in cands) {
      final key = c.shape.key;
      if (shapes.containsKey(key)) continue;
      try {
        final r = buildHairMask(a, c.shape);
        File('${out.path}/$key.png').writeAsBytesSync(maskToPng(r.mask));
        shapes[key] = {'file': '$key.png', 'area': r.area};
      } on HairMaskException catch (e) {
        shapes[key] = {'error': e.code};
      }
    }
    File('${out.path}/masks.json').writeAsStringSync(
      const JsonEncoder.withIndent(
        ' ',
      ).convert({'colour': colour, 'shapes': shapes}),
    );
    stdout.writeln('HAIRMASKS ${shapes.length} tvarů · barva ${colour ?? '—'}');
    expect(shapes, isNotEmpty);
  });
}
