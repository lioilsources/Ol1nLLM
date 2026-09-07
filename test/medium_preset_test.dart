import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/gen_node.dart';
import 'package:ol1n_llm/models/medium_preset.dart';
import 'package:ol1n_llm/models/style_preset.dart';

/// The medium axis is an A/B experiment before it is a feature, so most of
/// what is worth testing here is that the control arm stayed a control arm.
void main() {
  group('kMediumPresets', () {
    test('ids are unique, prefixed and stable', () {
      final ids = kMediumPresets.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
      // Persisted on nodes and exported to the gallery as medium_id: renaming
      // one detaches every rating already collected under the old id.
      expect(ids, containsAll(['medium_photoreal', 'medium_illustration',
          'medium_relief', 'medium_print']));
      for (final id in ids) {
        expect(id, startsWith('medium_'), reason: id);
      }
    });

    test('no id collides with a style id — both are columns of one row', () {
      final styles = kStylePresets.map((s) => s.id).toSet();
      for (final m in kMediumPresets) {
        expect(styles, isNot(contains(m.id)), reason: m.id);
      }
    });

    test('every preset carries a non-empty label and block', () {
      for (final m in kMediumPresets) {
        expect(m.label.trim(), isNotEmpty, reason: m.id);
        expect(m.block.trim().length, greaterThan(20), reason: m.id);
      }
    });

    test('blocks stay orthogonal to the style axis', () {
      // A medium block that named a tradition would move two variables at
      // once, and the A/B could no longer attribute the difference.
      const traditions = [
        'ukiyo', 'baroque', 'egyptian', 'assyrian', 'byzantine', 'persian',
        'aztec', 'maya', 'gothic', 'japanese', 'chinese', 'art nouveau',
      ];
      for (final m in kMediumPresets) {
        final block = m.block.toLowerCase();
        for (final t in traditions) {
          expect(block, isNot(contains(t)), reason: '${m.id} names $t');
        }
      }
    });

    test('mediumById falls back to null, not to a default', () {
      expect(mediumById(null), isNull);
      expect(mediumById('nope'), isNull);
      // No medium is the control arm: it must never resolve to some preset.
      expect(mediumById('')?.id, isNull);
      expect(mediumById('medium_relief')?.label, 'Reliéf');
    });
  });

  group('composePrompt', () {
    test('without a medium it is byte-identical to applyStyle', () {
      // The whole A/B rests on this: the control arm has to be exactly what
      // the app sent before the axis existed, or it compares two changes.
      for (final s in [null, ...kStylePresets.map((s) => s.id)]) {
        expect(composePrompt('a ballerina', styleId: s),
            applyStyle('a ballerina', s),
            reason: 'style $s');
      }
      expect(composePrompt('a ballerina'), 'a ballerina');
    });

    test('the medium block leads the prompt, the style block trails it', () {
      final out = composePrompt('a ballerina',
          styleId: 'ukiyoe', mediumId: 'medium_relief');
      expect(out, startsWith('a carved relief'));
      expect(out, contains(', a ballerina, '));
      expect(out, endsWith(styleById('ukiyoe')!.block));
      // Front placement is the hypothesis, not a detail: early tokens weigh
      // most, which is why a trailing mention loses to the style block.
      expect(out.indexOf('carved relief'),
          lessThan(out.indexOf('woodblock print aesthetic')));
    });

    test('a medium works without a style', () {
      expect(composePrompt('a ballerina', mediumId: 'medium_ink'),
          '${mediumById('medium_ink')!.block}, a ballerina');
    });

    test('an unknown medium id changes nothing', () {
      expect(composePrompt('a ballerina', mediumId: 'nope'), 'a ballerina');
    });

    test('an empty prompt stays empty — a medium is not a subject', () {
      // Photo roots carry an empty prompt; leading it with a medium block
      // would turn a reference upload into a generation request.
      expect(composePrompt('', mediumId: 'medium_relief'), '');
      expect(composePrompt('   ', mediumId: 'medium_relief'), '   ');
      expect(composePrompt('', styleId: 'ukiyoe', mediumId: 'medium_relief'),
          '');
    });

    test('composePromptWith takes presets the registry does not have', () {
      // The lab vets candidates before they land in a registry; looking them
      // up by id would silently drop their text.
      const candidate = MediumPreset(
          id: 'medium_candidate', label: 'x', block: 'a candidate medium');
      expect(composePromptWith('a ballerina', medium: candidate),
          'a candidate medium, a ballerina');
    });
  });

  group('GenNode.mediumId', () {
    test('round-trips and is omitted when unset', () {
      final json = GenNode.create(prompt: 'x', mediumId: 'medium_relief')
          .toJson();
      expect(json['mediumId'], 'medium_relief');
      expect(GenNode.fromJson(json).mediumId, 'medium_relief');
      expect(GenNode.create(prompt: 'x').toJson().containsKey('mediumId'),
          isFalse);
    });

    test('survives copyWith', () {
      final n = GenNode.create(prompt: 'x', mediumId: 'medium_ink')
          .copyWith(status: GenStatus.ready);
      expect(n.mediumId, 'medium_ink');
    });

    test('a node written before the axis existed still parses', () {
      final old = GenNode.create(prompt: 'x', styleId: 'ukiyoe').toJson();
      expect(GenNode.fromJson(old).mediumId, isNull);
    });
  });
}
