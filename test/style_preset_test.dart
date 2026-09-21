import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/gen_node.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/models/style_preset.dart';

/// The style blocks are the ones measured in the 10×25 matrix — the ids are
/// persisted on nodes, so renaming one silently breaks old sessions.
void main() {
  group('kStylePresets', () {
    test('ids are unique and stable', () {
      final ids = kStylePresets.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, containsAll(['ukiyoe', 'chineseink', 'egyptian', 'baroque']));
      // Second wave, kept only where a model demonstrably reacted.
      expect(ids, containsAll(['byzantine', 'stainedglass', 'artdeco',
          'constructivist', 'impressionist', 'thangka']));
      // Dropped on purpose: the metric moved but the style never landed —
      // the model just tinted its own default scene.
      expect(ids, isNot(contains('suprematism')));
      expect(ids, isNot(contains('wayang')));
      // Dropped as duplicates of a style already here.
      expect(ids, isNot(contains('sumie'))); // = chineseink
      expect(ids, isNot(contains('mughal'))); // = persian
      // Third wave: styles after named artists, measured on five models with
      // a text per prompt dialect.
      expect(ids, containsAll(['vangogh-arles', 'vangogh-saintremy', 'kubista',
          'lada', 'josef-capek', 'mucha-slav-epic', 'klimt-golden', 'seurat']));
      // Dropped: only a tint or a backdrop — the artist's hand never came.
      expect(ids, isNot(contains('zrzavy')));
      expect(ids, isNot(contains('modigliani')));
      expect(ids, isNot(contains('hockney-joiner')));
      // Dropped: content instead of style, it puts a ballerina into any prompt.
      expect(ids, isNot(contains('degas')));
      // Dropped as duplicates; Mucha's text went into artnouveau instead.
      expect(ids, isNot(contains('rembrandt'))); // = baroque
      expect(ids, isNot(contains('mucha-poster'))); // → artnouveau
      expect(kStylePresets.length, 82);
    });

    test('every artist style carries its period and a tag variant', () {
      final artists = kStylePresets.where((s) => s.artist != null).toList();
      expect(artists.length, 42);
      for (final s in artists) {
        expect(s.period, isNotNull, reason: s.id);
        expect(s.booru, isNotNull, reason: s.id);
      }
      // The poster text was the better Art Nouveau on juggernaut and equal
      // elsewhere, so it replaced the generic block — under the old id, which
      // is persisted on nodes, and still filed with cultures and epochs.
      final nouveau = styleById('artnouveau')!;
      expect(nouveau.block, contains('Alphonse Mucha'));
      expect(nouveau.booru, isNotNull);
      expect(nouveau.artist, isNull);
    });

    test('every preset carries a non-empty label and block', () {
      for (final s in kStylePresets) {
        expect(s.label.trim(), isNotEmpty, reason: s.id);
        expect(s.block.trim().length, greaterThan(20), reason: s.id);
      }
    });

    test('styleById falls back to null, not to a default', () {
      expect(styleById(null), isNull);
      expect(styleById('nope'), isNull);
      expect(styleById('ukiyoe')?.label, 'Ukiyo-e woodblock');
    });
  });

  group('applyStyle', () {
    test('appends the block after the user prompt', () {
      final out = applyStyle('a ballerina', 'ukiyoe');
      expect(out, startsWith('a ballerina, '));
      expect(out, contains('japanese woodblock print aesthetic'));
    });

    test('no style leaves the prompt untouched', () {
      expect(applyStyle('a ballerina', null), 'a ballerina');
      expect(applyStyle('a ballerina', 'nope'), 'a ballerina');
    });

    test('an empty prompt stays empty — a style is not a subject', () {
      // Photo roots carry an empty prompt; appending a style block there
      // would make the style the entire request.
      expect(applyStyle('', 'ukiyoe'), '');
      expect(applyStyle('   ', 'ukiyoe'), '   ');
    });
  });

  group('dialects', () {
    const tagged = StylePreset(
      id: 'x',
      label: 'X',
      block: 'portrait painting, thick impasto brushstrokes',
      booru: 'oil painting (medium), impasto',
    );
    const plain = StylePreset(id: 'y', label: 'Y', block: 'flat colour areas');

    test('an anime model gets the tags, everything else the block', () {
      expect(tagged.blockFor(PromptDialect.booru), tagged.booru);
      expect(tagged.blockFor(PromptDialect.natural), tagged.block);
      expect(
        applyStylePreset('a ballerina', tagged, dialect: PromptDialect.booru),
        'a ballerina, oil painting (medium), impasto',
      );
    });

    test('a style without tags sends what it always sent', () {
      expect(plain.blockFor(PromptDialect.booru), plain.block);
      expect(
        applyStyle('a ballerina', 'ukiyoe', dialect: PromptDialect.booru),
        applyStyle('a ballerina', 'ukiyoe'),
      );
    });

    test('no tag variant names the artist', () {
      // Pony V6 hashed artist names; on Illustrious and NoobAI the artist tag
      // did nothing, or pulled the render back towards the default scene.
      for (final s in kStylePresets) {
        final tags = s.booru?.toLowerCase();
        if (tags == null) continue;
        expect(tags, isNot(contains(' by ')), reason: s.id);
        for (final part in (s.artist ?? '').toLowerCase().split(' ')) {
          if (part.length < 4) continue; // "van", "de", "da"
          expect(tags, isNot(contains(part)), reason: '${s.id}: $part');
        }
      }
    });

    test('anime lineages read tags, the rest phrases', () {
      // Explicit per model, not derived from loraFamily: animagine-xl loads
      // plain SDXL LoRAs but was captioned with danbooru tags.
      final booru = {
        for (final m in kImageModels)
          if (m.promptDialect == PromptDialect.booru) m.id,
      };
      expect(booru, {
        'pony',
        'atomix-pony-anime',
        'autismmix-pony',
        'illustrious-xl',
        'noobai-xl',
        'wai-illustrious',
        'hassaku-illustrious',
        'animagine-xl',
      });
      expect(imageModelById('animagine-xl').loraFamily, LoraFamily.sdxl);
    });
  });

  group('styleMatchesQuery', () {
    const zrzavy = StylePreset(
      id: 'zrzavy',
      label: 'Zrzavý — symbolistní figura',
      block: 'dreamlike melancholic figure',
      artist: 'Jan Zrzavý',
    );

    test('matches label and artist, blind to case and accents', () {
      // Typed on a phone, a Czech name mostly arrives without its accents.
      expect(styleMatchesQuery(zrzavy, 'zrzavy'), isTrue);
      expect(styleMatchesQuery(zrzavy, 'JAN'), isTrue);
      expect(styleMatchesQuery(zrzavy, 'symbolisticka'), isFalse);
      expect(styleMatchesQuery(zrzavy, 'symbolist'), isTrue);
      expect(styleMatchesQuery(zrzavy, 'kubišta'), isFalse);
    });

    test('an empty query keeps everything', () {
      expect(styleMatchesQuery(zrzavy, ''), isTrue);
      expect(styleMatchesQuery(zrzavy, '   '), isTrue);
    });

    test('a style without an artist matches by label alone', () {
      expect(styleMatchesQuery(styleById('ukiyoe')!, 'ukiyo'), isTrue);
      expect(styleMatchesQuery(styleById('ukiyoe')!, 'woodblock'), isTrue);
    });

    test('the block is not searched', () {
      // Every block says "painting" or "style" — matching it would turn any
      // query into the whole list.
      expect(styleMatchesQuery(zrzavy, 'melancholic'), isFalse);
    });
  });

  group('GenNode.styleId', () {
    test('round-trips and is omitted when unset', () {
      final json = GenNode.create(prompt: 'x', styleId: 'baroque').toJson();
      expect(json['styleId'], 'baroque');
      expect(GenNode.fromJson(json).styleId, 'baroque');
      expect(GenNode.create(prompt: 'x').toJson().containsKey('styleId'),
          isFalse);
    });

    test('survives copyWith', () {
      final n = GenNode.create(prompt: 'x', styleId: 'persian')
          .copyWith(status: GenStatus.ready);
      expect(n.styleId, 'persian');
    });
  });

  group('model style notes', () {
    test('every ComfyUI model that can be picked carries one', () {
      for (final m in kImageModels) {
        expect(m.styleNote, isNotNull, reason: '${m.id} has no styleNote');
        expect(m.styleNote!.trim(), isNotEmpty, reason: m.id);
      }
    });
  });
}
