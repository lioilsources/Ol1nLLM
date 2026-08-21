import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/providers/image_studio_provider.dart';

void main() {
  const loras = [
    'flux-lora-uncensored.safetensors', // flux
    'style-anime-screencap.safetensors', // illustrious (SDXL lineage)
    'sexy_attire.safetensors', // SD 1.5 — offerable to nothing we run
  ];
  const ckpts = ['ponyDiffusionV6XL_v6StartWithThisOne.safetensors'];

  test('server catalog survives copyWith', () {
    const base = ImageStudioState(
      availableLoras: loras,
      availableCheckpoints: ckpts,
    );
    final next = base.copyWith(currentNodeId: 'n1');
    expect(next.availableLoras, loras);
    expect(next.availableCheckpoints, ckpts);
  });

  test('filteredLoras follows the active model lineage', () {
    const base = ImageStudioState(availableLoras: loras);
    expect(base.copyWith(modelId: 'flux-manga').filteredLoras,
        ['flux-lora-uncensored.safetensors']);
    // Illustrious file is offered to Pony (same architecture, weaker fit);
    // the SD 1.5 one is dropped — on SDXL it half-loads through the shared
    // text encoder and corrupts the prompt instead of applying its concept.
    expect(base.copyWith(modelId: 'pony').filteredLoras,
        ['style-anime-screencap.safetensors']);
    expect(base.copyWith(modelId: 'illustrious-xl').filteredLoras,
        ['style-anime-screencap.safetensors']);
    // sd15 declares no LoRA family — the chip is meant to disappear there.
    expect(base.copyWith(modelId: 'sd15').filteredLoras, isEmpty);
  });

  test('an unknown checkpoint list leaves the picker unfiltered', () {
    const base = ImageStudioState(availableLoras: loras);
    expect(base.availableModels, kImageModels);
  });

  test('a known checkpoint list prunes the picker', () {
    const base = ImageStudioState(availableCheckpoints: ckpts);
    final ids = base.availableModels.map((m) => m.id);
    expect(ids, contains('pony'));
    expect(ids, isNot(contains('juggernaut-xl')));
    // Default model is flux-manga (no checkpoint) — must stay selectable.
    expect(ids, contains(kDefaultImageModelId));
  });

  group('repose mode state', () {
    test('defaults to off', () {
      expect(const ImageStudioState().reposeSourceImageId, isNull);
    });

    test('survives an unrelated copyWith', () {
      const base = ImageStudioState(reposeSourceImageId: 'img');
      expect(base.copyWith(currentNodeId: 'n1').reposeSourceImageId, 'img');
    });

    test('clearRepose nulls it', () {
      const base = ImageStudioState(reposeSourceImageId: 'img');
      expect(base.copyWith(clearRepose: true).reposeSourceImageId, isNull);
    });

    test('clearSelected leaves it alone (exclusivity lives in the notifier)',
        () {
      const base = ImageStudioState(
        reposeSourceImageId: 'img',
        selectedImageId: 'sel',
      );
      final next = base.copyWith(clearSelected: true);
      expect(next.selectedImageId, isNull);
      expect(next.reposeSourceImageId, 'img');
    });
  });
}
