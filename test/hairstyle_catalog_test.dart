import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/hair_mask.dart';
import 'package:ol1n_llm/models/hairstyle_preset.dart';
import 'package:ol1n_llm/models/image_model.dart';

/// Both measured models plus one that is neither, to prove the plan never
/// reaches for a checkpoint no verdict covers.
final _server = [
  for (final id in ['flux-fill', 'juggernaut-xl', 'illustrious-xl'])
    kImageModels.firstWhere((m) => m.id == id),
];

HairstylePreset _style(List<HairEngine> engines) => HairstylePreset(
  id: 'x',
  label: 'x',
  group: kHairGroupWomen,
  section: '',
  block: 'x',
  shape: const HairShape(length: HairLength.keep),
  engines: engines,
);

HairColourPreset _colour(List<HairEngine> engines) =>
    HairColourPreset(id: 'c', label: 'Barva', phrase: 'x', engines: engines);

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

  test('every catalog entry names at least one engine', () {
    // An entry that passed nowhere must not be exported at all — an empty list
    // would make planHairRun return null and the action would just fail.
    for (final s in kHairstyles) {
      expect(s.engines, isNotEmpty, reason: s.id);
    }
    for (final c in kHairColours) {
      expect(c.engines, isNotEmpty, reason: c.id);
    }
    // The gate is worth having only if the two engines really do disagree.
    expect(kHairstyles.where((s) => s.engines.length == 1), isNotEmpty);
  });

  group('planHairRun', () {
    HairPlan? plan(
      HairstylePreset style, {
      HairColourPreset? colour,
      String current = 'flux-fill',
      List<ImageModelSpec>? server,
    }) => planHairRun(
      available: server ?? _server,
      currentModelId: current,
      style: style,
      colour: colour,
    );

    test('the style picks the engine, not the selected model', () {
      // On Juggernaut, a Kontext-only style still switches to flux-fill — the
      // opposite (model decides) would ship what no verdict covers.
      final p = plan(_style([HairEngine.kontext]), current: 'juggernaut-xl');
      expect(p!.modelId, 'flux-fill');
      expect(plan(_style([HairEngine.sdxl]))!.modelId, 'juggernaut-xl');
    });

    test('a style measured on both stays on the current model', () {
      expect(plan(_style(HairEngine.values))!.modelId, 'flux-fill');
      expect(
        plan(_style(HairEngine.values), current: 'juggernaut-xl')!.modelId,
        'juggernaut-xl',
      );
      // …but an unmeasured checkpoint is never kept, however capable.
      expect(
        plan(_style(HairEngine.values), current: 'illustrious-xl')!.modelId,
        'flux-fill',
      );
    });

    test('the colour narrows the engine when it can', () {
      final p = plan(
        _style(HairEngine.values),
        colour: _colour([HairEngine.sdxl]),
      );
      expect(p!.modelId, 'juggernaut-xl');
      expect(p.note, isNull);
    });

    test('style and colour with no engine in common: style wins, with a note', () {
      // A blond lob: blonde passed only on Kontext, a lob only on SDXL.
      // Refusing it would be worse than running it and saying so.
      final p = plan(
        _style([HairEngine.sdxl]),
        colour: _colour([HairEngine.kontext]),
      );
      expect(p!.engine, HairEngine.sdxl);
      expect(p.note, contains('Barva'));
    });

    test('null when the engine\'s model is not on the server', () {
      final onlyFlux = [_server.first];
      expect(plan(_style([HairEngine.sdxl]), server: onlyFlux), isNull);
      // A both-engines style still runs — it falls back to the engine there is.
      expect(
        plan(_style(HairEngine.values), server: onlyFlux)!.modelId,
        'flux-fill',
      );
    });
  });
}
