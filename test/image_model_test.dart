import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';

void main() {
  group('imageModelsFor', () {
    final allCkpts = [
      for (final m in kImageModels)
        if (m.preset?.ckptName != null) m.preset!.ckptName!,
    ];

    test('empty list means unknown — the whole registry stays visible', () {
      expect(imageModelsFor(const []), kImageModels);
    });

    test('every registry checkpoint installed → nothing is dropped', () {
      expect(imageModelsFor(allCkpts), kImageModels);
    });

    test('drops models whose checkpoint is missing on the server', () {
      final without = allCkpts
          .where((c) => c != 'Illustrious-XL-v2.0.safetensors')
          .toList();
      final ids = imageModelsFor(without).map((m) => m.id);
      expect(ids, isNot(contains('illustrious-xl')));
      expect(ids, contains('pony'));
    });

    test('checkpoint-less models survive an empty server catalog', () {
      // One unrelated checkpoint: the list is "known" but matches nothing.
      final ids = imageModelsFor(const ['nothing.safetensors'])
          .map((m) => m.id)
          .toList();
      // NIM backends (no preset) and flux-manga (UNETLoader, ckptName == null).
      expect(ids, containsAll(['flux-schnell', 'flux-kontext', 'flux-manga']));
      expect(ids, isNot(contains('pony')));
    });

    test('keepId survives even when its checkpoint is gone', () {
      final ids = imageModelsFor(
        const ['nothing.safetensors'],
        keepId: 'pony',
      ).map((m) => m.id);
      expect(ids, contains('pony'));
      expect(ids, isNot(contains('juggernaut-xl')));
    });

    test('registry order is preserved', () {
      final filtered = imageModelsFor(allCkpts).map((m) => m.id).toList();
      expect(filtered, kImageModels.map((m) => m.id).toList());
    });
  });

  test('model ids are unique', () {
    final ids = kImageModels.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
