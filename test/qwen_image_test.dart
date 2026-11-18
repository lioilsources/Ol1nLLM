import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/providers/image_studio_provider.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

/// Qwen-Image in the app: a dedicated txt2img graph whose numbers stay baked
/// in, which still reads a negative, takes no LoRA, and is offered only where
/// the server has its diffusion weights.
void main() {
  final qwen = imageModelById('qwen-image');

  Map<String, dynamic> template() =>
      jsonDecode(File(qwen.preset!.txt2imgAsset).readAsStringSync())
          as Map<String, dynamic>;

  Map node(Map<String, dynamic> wf, String cls) =>
      wf.values.map((e) => e as Map).firstWhere((n) => n['class_type'] == cls);

  test('is a ComfyUI txt2img model without edit, pose or LoRA', () {
    expect(qwen.kind, ImageBackendKind.comfyUi);
    expect(qwen.txt2img, isTrue);
    expect(qwen.img2img, isFalse);
    expect(qwen.inpaint, isFalse);
    expect(qwen.supportsPose, isFalse);
    expect(qwen.loraFamily, LoraFamily.none);
    expect(qwen.preset!.ckptName, isNull);
    expect(qwen.preset!.unetName, kQwenImageUnet);
  });

  test(
    'the graph keeps its sampler and size, and fills prompt and negative',
    () {
      final svc = ComfyUIService()
        ..setPreset(qwen.preset!)
        // Even a stale LoRA selection must not touch the graph.
        ..setLora('flux-lora-uncensored.safetensors');
      final wf = svc.prepareForTest(
        template(),
        prompt: 'a red excavator, felt toy',
        batch: 2,
        seed: 42,
        userNegative: 'text, watermark',
      );

      final sampler = node(wf, 'KSampler')['inputs'] as Map;
      expect(sampler['steps'], 20);
      expect(sampler['cfg'], 2.5);
      expect(sampler['sampler_name'], 'euler');
      expect(sampler['seed'], 42);

      final latent = node(wf, 'EmptySD3LatentImage')['inputs'] as Map;
      expect(latent['width'], 1328);
      expect(latent['height'], 1328);
      expect(latent['batch_size'], 2);

      final texts = wf.values
          .map((e) => e as Map)
          .where((n) => n['class_type'] == 'CLIPTextEncode')
          .map((n) => (n['inputs'] as Map)['text'])
          .toList();
      expect(texts, contains('a red excavator, felt toy'));
      expect(texts, contains('text, watermark'));
      expect(jsonEncode(wf), isNot(contains('__')));
      expect(
        wf.values.where((n) => (n as Map)['class_type'] == 'LoraLoader'),
        isEmpty,
      );
      expect(
        (node(wf, 'UNETLoader')['inputs'] as Map)['unet_name'],
        kQwenImageUnet,
      );
    },
  );

  test('the picker offers it only where the weights are (or are unknown)', () {
    List<String> ids(ImageStudioState s) =>
        s.availableModels.map((m) => m.id).toList();

    expect(ids(const ImageStudioState()), contains(qwen.id));
    expect(
      ids(const ImageStudioState(availableUnets: ['flux1-dev.safetensors'])),
      isNot(contains(qwen.id)),
    );
    expect(
      ids(const ImageStudioState(availableUnets: [kQwenImageUnet])),
      contains(qwen.id),
    );
    // A session that already uses it keeps it selectable.
    expect(
      ids(
        const ImageStudioState(
          modelId: 'qwen-image',
          availableUnets: ['flux1-dev.safetensors'],
        ),
      ),
      contains(qwen.id),
    );
    // A known checkpoint list says nothing about UNETLoader weights.
    expect(
      ids(
        const ImageStudioState(
          availableCheckpoints: [
            'ponyDiffusionV6XL_v6StartWithThisOne.safetensors',
          ],
        ),
      ),
      contains(qwen.id),
    );
  });

  test('the UNet list survives copyWith', () {
    const base = ImageStudioState(availableUnets: [kQwenImageUnet]);
    expect(base.copyWith(currentNodeId: 'n1').availableUnets, [kQwenImageUnet]);
  });
}
