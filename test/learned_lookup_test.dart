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

    test('kLearned v repu je prázdný, dokud generátor neběžel', () {
      // Až `lab learn` poprvé doběhne, tenhle test se změní na kontrolu
      // snapshotu — do té doby hlídá, že se do generovaného souboru nedostalo
      // nic ručně.
      expect(kLearned.isEmpty, isTrue,
          reason: 'lib/generated/learned.dart se needituje ručně');
      expect(kLearned.snapshotAt, isNull);
    });

    test('síla LoRA padá na kDefaultLoraStrength', () {
      expect(empty.loraStrength, isEmpty);
      expect(loraStrengthFor(null), kDefaultLoraStrength);
      expect(loraStrengthFor('cokoliv.safetensors'), kDefaultLoraStrength);
      expect(loraStrengthReason('cokoliv.safetensors'), isNull);
    });

    test('výchozí model padá na kDefaultImageModelId', () {
      for (final i in Intent.values) {
        expect(defaultModelFor(i), kDefaultImageModelId, reason: i.name);
        expect(defaultModelReason(i), isNull, reason: i.name);
      }
    });

    test('o modelu se neví nic a styl nenese příznak', () {
      for (final m in kImageModels) {
        expect(learnedModelFor(m.id), isNull, reason: m.id);
        expect(styleFlagFor(m.id, 'ukiyoe'), isNull, reason: m.id);
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
        Intent.repose: LearnedChoice('pony', reason: 'pose_adherence 0.75'),
        // Měřeno, nerozhodnuto — pro volajícího totéž co nenaučeno.
        Intent.txt2img: null,
      },
      styleFlags: {
        'juggernaut-xl': {
          'assyrian': StyleFlag.weak(reason: 'like lower 0.11, n=15'),
        },
      },
    );

    test('naučená hodnota vyhraje nad konstantou', () {
      expect(overlay.loraStrength['face_v1.safetensors']!.value, 1.2);
      expect(overlay.loraStrength['face_v1.safetensors']!.value,
          isNot(kDefaultLoraStrength));
    });

    test('nenaučený klíč pořád padá na konstantu', () {
      expect(overlay.loraStrength['jiná.safetensors'], isNull);
    });

    test('„měřeno, nerozhodnuto" se chová jako nenaučeno', () {
      expect(overlay.defaultModel.containsKey(Intent.txt2img), isTrue);
      expect(overlay.defaultModel[Intent.txt2img], isNull);
      expect(overlay.defaultModel[Intent.repose]!.value, 'pony');
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
