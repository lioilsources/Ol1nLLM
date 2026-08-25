import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/gen_node.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/models/image_session.dart';
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

  group('adoptableSettings — chips follow the node you navigate to', () {
    final models = imageModelsFor(const []); // catalog unknown ⇒ all offered
    const catalog = [
      'style-anime-screencap.safetensors',
      'flux-lora-uncensored.safetensors',
    ];

    GenNode node({
      String? modelId = 'illustrious-xl',
      String? lora,
      double? strength,
      String? poseId,
    }) => GenNode.create(
      prompt: 'x',
      modelId: modelId,
      loraName: lora,
      loraStrength: strength,
      poseId: poseId,
    );

    test('adopts model, LoRA, strength and pose', () {
      final s = adoptableSettings(
        node(
          lora: 'style-anime-screencap.safetensors',
          strength: 1.25,
          poseId: 'ol3',
        ),
        availableModels: models,
        installedLoras: catalog,
      );
      expect(s?.modelId, 'illustrious-xl');
      expect(s?.lora, 'style-anime-screencap.safetensors');
      expect(s?.loraStrength, 1.25);
      expect(s?.poseId, 'ol3');
    });

    test('a node without a snapshot leaves the chips alone', () {
      // Photo roots and pre-metadata sessions carry no modelId.
      expect(
        adoptableSettings(node(modelId: null),
            availableModels: models, installedLoras: catalog),
        isNull,
      );
    });

    test('a model the server no longer has is not adopted', () {
      final onlyPony = models.where((m) => m.id == 'pony').toList();
      expect(
        adoptableSettings(node(),
            availableModels: onlyPony, installedLoras: catalog),
        isNull,
      );
    });

    test('a LoRA gone from the server is dropped, the model still applies', () {
      final s = adoptableSettings(
        node(lora: 'deleted.safetensors', strength: 1.1),
        availableModels: models,
        installedLoras: catalog,
      );
      expect(s?.modelId, 'illustrious-xl');
      expect(s?.lora, isNull);
    });

    test('a LoRA from another architecture is dropped', () {
      final s = adoptableSettings(
        node(lora: 'flux-lora-uncensored.safetensors'),
        availableModels: models,
        installedLoras: catalog,
      );
      expect(s?.lora, isNull);
    });

    test('an unknown LoRA catalog keeps the node LoRA', () {
      final s = adoptableSettings(
        node(lora: 'style-anime-screencap.safetensors'),
        availableModels: models,
        installedLoras: const [],
      );
      expect(s?.lora, 'style-anime-screencap.safetensors');
    });

    test('nodes from before v1.5.1 fall back to the default strength', () {
      final s = adoptableSettings(
        node(lora: 'style-anime-screencap.safetensors'),
        availableModels: models,
        installedLoras: catalog,
      );
      expect(s?.loraStrength, kDefaultLoraStrength);
    });

    test('a pose is dropped for a model that cannot pose', () {
      final s = adoptableSettings(
        node(modelId: 'flux-manga', poseId: 'ol3'),
        availableModels: models,
        installedLoras: catalog,
      );
      expect(s?.modelId, 'flux-manga');
      expect(s?.poseId, isNull);
    });
  });

  group('style + edit strength are session settings', () {
    test('defaults are off / preset', () {
      const st = ImageStudioState();
      expect(st.selectedStyleId, isNull);
      expect(st.editDenoise, isNull);
    });

    test('survive an unrelated copyWith, clear on demand', () {
      const base = ImageStudioState(
        selectedStyleId: 'ukiyoe',
        editDenoise: kStyleEditDenoise,
      );
      final next = base.copyWith(currentNodeId: 'n1');
      expect(next.selectedStyleId, 'ukiyoe');
      expect(next.editDenoise, kStyleEditDenoise);
      expect(base.copyWith(clearStyle: true).selectedStyleId, isNull);
      expect(base.copyWith(clearEditDenoise: true).editDenoise, isNull);
    });

    test('round-trip through the persisted session', () {
      final s = ImageSession.create(
        nodes: [GenNode.create(prompt: 'x')],
        modelId: 'pony',
        selectedStyleId: 'baroque',
        editDenoise: kStyleEditDenoise,
      );
      final back = ImageSession.fromJson(jsonDecode(jsonEncode(s.toJson()))
          as Map<String, dynamic>);
      expect(back.selectedStyleId, 'baroque');
      expect(back.editDenoise, kStyleEditDenoise);
    });

    test('a session saved before this version reads as defaults', () {
      final back = ImageSession.fromJson({
        'id': 'a', 'title': 't', 'nodes': <Map<String, dynamic>>[],
        'modelId': 'pony', 'updatedAt': DateTime.now().toIso8601String(),
      });
      expect(back.selectedStyleId, isNull);
      expect(back.editDenoise, isNull);
    });
  });
}
