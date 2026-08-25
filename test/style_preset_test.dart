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
      expect(kStylePresets.length, 25);
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
