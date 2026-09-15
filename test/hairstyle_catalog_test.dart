import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/hairstyle_preset.dart';

void main() {
  test('every catalog entry ships its preview; colours ship a measured swatch',
      () {
    // The sheet shows the bench's own output per style — a missing file would
    // fall back to the scissors and nobody would notice in CI. Both come out
    // of MangaPrompts export_catalog.py --bench / --colours-bench.
    for (final s in kHairstyles) {
      expect(File(s.preview).existsSync(), isTrue, reason: s.preview);
    }
    for (final c in kHairColours) {
      expect(c.swatch, isNotNull, reason: c.id);
      expect(c.swatch! >> 24, 0xFF, reason: '${c.id}: opaque ARGB');
    }
  });

  test('no stale preview outlives its style', () {
    final ids = kHairstyles.map((s) => s.id).toSet();
    for (final f in Directory('assets/hair').listSync()) {
      final id = f.uri.pathSegments.last.replaceAll('.jpg', '');
      expect(ids, contains(id), reason: f.path);
    }
  });
}
