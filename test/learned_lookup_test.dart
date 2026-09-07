import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/models/learned_lookup.dart';
import 'package:ol1n_llm/models/style_preset.dart';

/// I1 — **nikdy horší než dnes**. Prázdný overlay musí dát chování shodné
/// s tím před zavedením učení; naměřená hodnota ho **přebíjí, nenahrazuje**.
///
/// Ten první test je jediný důvod, proč se generovaný soubor smí commitnout
/// bez obav: když `lab learn` nic nerozhodne, appka nespadne na nic horšího.
void main() {
  group('prázdný overlay == dnešní konstanty (I1)', () {
    const empty = Learned();

    test('commitnutý kLearned je koherentní, ať už generátor běžel nebo ne', () {
      // Musí platit v obou stavech: čerstvý klon s prázdným overlayem i repo
      // po `make learn`. Test, který by trval na prázdnu, by spadl při prvním
      // opravdovém spuštění generátoru — tedy přesně ve chvíli, kdy to celé
      // začne fungovat.
      if (kLearned.isEmpty) {
        expect(kLearned.snapshotAt, isNull);
        expect(kLearned.models, isEmpty);
        expect(kLearned.loraStrength, isEmpty);
        expect(kLearned.defaultModel, isEmpty);
        expect(kLearned.styleFlags, isEmpty);
        return;
      }
      // Vygenerovaný soubor: snapshot musí být čitelné datum a každá hodnota
      // musí nést důvod (I3) — obojí se rozbije ruční editací, což je jediný
      // způsob, jak se sem něco bez proveniences dostane.
      expect(kLearned.snapshotTime, isNotNull,
          reason: 'nečitelný snapshot: ${kLearned.snapshotAt}');
      expect(kLearned.minRatings, greaterThan(0));
      for (final e in kLearned.loraStrength.entries) {
        expect(e.value.reason.trim(), isNotEmpty, reason: e.key);
      }
      for (final e in kLearned.defaultModel.entries) {
        expect(e.value?.reason.trim() ?? 'x', isNotEmpty, reason: e.key.name);
      }
      for (final byStyle in kLearned.styleFlags.values) {
        for (final e in byStyle.entries) {
          expect(e.value.reason.trim(), isNotEmpty, reason: e.key);
        }
      }
    });

    test('síla LoRA padá na kDefaultLoraStrength', () {
      expect(loraStrengthFor(null, overlay: empty), kDefaultLoraStrength);
      expect(loraStrengthFor('cokoliv.safetensors', overlay: empty),
          kDefaultLoraStrength);
      expect(loraStrengthReason('cokoliv.safetensors', overlay: empty), isNull);
    });

    test('výchozí model padá na kDefaultImageModelId', () {
      for (final i in GenIntent.values) {
        expect(defaultModelFor(i, overlay: empty), kDefaultImageModelId,
            reason: i.name);
        expect(defaultModelReason(i, overlay: empty), isNull, reason: i.name);
      }
    });

    test('o modelu se neví nic a styl nenese příznak', () {
      for (final m in kImageModels) {
        expect(learnedModelFor(m.id, overlay: empty), isNull, reason: m.id);
        expect(styleFlagFor(m.id, 'ukiyoe', overlay: empty), isNull,
            reason: m.id);
      }
    });

    test('prázdný overlay se nikdy netváří jako zastaralý', () {
      // Bez snapshotu není co stárnout — jinak by čerstvý klon appky hlásil
      // „znalost je stará", což je nesmysl a naučilo by to ignorovat varování,
      // které má smysl.
      expect(empty.isStaleAt(DateTime.now()), isFalse);
      expect(empty.ageAt(DateTime.now()), isNull);
    });
  });

  group('overlay přebíjí', () {
    const overlay = Learned(
      snapshotAt: '2026-09-07T14:02:00Z',
      ratedImages: 987,
      totalImages: 1412,
      minRatings: 10,
      models: {
        'pony': LearnedModel(
          poseAdherence: Rate(0.90, lower: 0.75, upper: 0.97, n: 31),
          likeRate: Rate(0.82, lower: 0.66, upper: 0.91, n: 34),
        ),
      },
      loraStrength: {
        'face_v1.safetensors':
            LearnedValue(1.2, reason: 'lower 0.71 > upper 0.58 of 0.40 arm'),
      },
      defaultModel: {
        GenIntent.repose: LearnedChoice('pony', reason: 'pose_adherence 0.75'),
        // Měřeno, nerozhodnuto — pro volajícího totéž co nenaučeno.
        GenIntent.txt2img: null,
      },
      styleFlags: {
        'juggernaut-xl': {
          'assyrian': StyleFlag.weak(reason: 'like lower 0.11, n=15'),
        },
      },
    );

    test('naučená hodnota vyhraje nad konstantou', () {
      expect(loraStrengthFor('face_v1.safetensors', overlay: overlay), 1.2);
      expect(loraStrengthFor('face_v1.safetensors', overlay: overlay),
          isNot(kDefaultLoraStrength));
      expect(loraStrengthReason('face_v1.safetensors', overlay: overlay),
          isNotNull);
      expect(defaultModelFor(GenIntent.repose, overlay: overlay), 'pony');
      expect(learnedModelFor('pony', overlay: overlay)?.poseAdherence?.n, 31);
      expect(styleFlagFor('juggernaut-xl', 'assyrian', overlay: overlay)?.isWeak,
          isTrue);
    });

    test('nenaučený klíč pořád padá na konstantu', () {
      expect(loraStrengthFor('jiná.safetensors', overlay: overlay),
          kDefaultLoraStrength);
      expect(learnedModelFor('sd15', overlay: overlay), isNull);
      expect(styleFlagFor('pony', 'ukiyoe', overlay: overlay), isNull);
    });

    test('„měřeno, nerozhodnuto" se chová jako nenaučeno', () {
      // Klíč tam je, hodnota je null: volající dostane dnešní konstantu, ale
      // generovaný soubor u toho nese důvod, takže při review jde odlišit
      // „ještě málo dat" od „nikdo neměřil".
      expect(overlay.defaultModel.containsKey(GenIntent.txt2img), isTrue);
      expect(defaultModelFor(GenIntent.txt2img, overlay: overlay),
          kDefaultImageModelId);
      expect(defaultModelReason(GenIntent.txt2img, overlay: overlay), isNull);
    });

    test('summary veze n s číslem, ne vedle něj', () {
      final m = learnedModelFor('pony', overlay: overlay)!;
      expect(m.summary, 'póza 90 % (n=31) · like 82 % (n=34)');
      expect(const LearnedModel().summary, isNull);
    });

    test('každá naučená hodnota nese neprázdný důvod (I3)', () {
      for (final v in overlay.loraStrength.values) {
        expect(v.reason.trim(), isNotEmpty);
      }
      for (final v in overlay.defaultModel.values) {
        if (v != null) expect(v.reason.trim(), isNotEmpty);
      }
      for (final byStyle in overlay.styleFlags.values) {
        for (final f in byStyle.values) {
          expect(f.reason.trim(), isNotEmpty);
        }
      }
    });

    test('příznak stylu označí, ale nikdy neskryje (I5)', () {
      final flag = overlay.styleFlags['juggernaut-xl']!['assyrian']!;
      expect(flag.isWeak, isTrue);
      // Registr se učením nemění — skrytý styl by už nikdy nedostal
      // hodnocení a nemohl by se vrátit.
      expect(kStylePresets.map((s) => s.id), contains('assyrian'));
    });

    test('stárnutí snapshotu', () {
      final t = DateTime.parse('2026-09-07T14:02:00Z');
      expect(overlay.isStaleAt(t.add(const Duration(days: 29))), isFalse);
      expect(overlay.isStaleAt(t.add(const Duration(days: 31))), isTrue);
      expect(overlay.ageAt(t.add(const Duration(days: 3))),
          const Duration(days: 3));
    });
  });

  group('Rate', () {
    test('formátuje procenta a rozpětí, ne holý průměr', () {
      const r = Rate(0.62, lower: 0.36, upper: 0.83, n: 13);
      expect(r.percent, '62 %');
      expect(r.range, '36–83 %');
    });
  });
}
