import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/gen_node.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

/// Verifies the LoRA gets wired into the model/clip path for BOTH ComfyUI
/// families — the generic SDXL template (CheckpointLoaderSimple) and the
/// dedicated flux graph (UNETLoader + DualCLIPLoader). The failure mode this
/// guards against is a *dangling* LoraLoader: ComfyUI silently prunes any node
/// not connected to an output, so a mis-wired LoRA is a no-op, not an error.
Map<String, dynamic> _loadTemplate(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Finds the single injected LoRA node's key, or fails.
String _loraKey(Map<String, dynamic> wf) {
  final keys = wf.entries
      .where((e) => (e.value as Map)['class_type'] == 'LoraLoader')
      .map((e) => e.key)
      .toList();
  expect(keys, hasLength(1), reason: 'exactly one LoraLoader expected');
  return keys.first;
}

/// Every [nodeId, port] edge referenced anywhere in the graph.
List<List> _allEdges(Map<String, dynamic> wf) => [
  for (final e in wf.values)
    for (final v in ((e as Map)['inputs'] as Map? ?? {}).values)
      if (v is List && v.length == 2 && v[0] is String) v,
];

void main() {
  final pony = imageModelById('pony');
  final flux = imageModelById('flux-manga');

  group('LoRA injection wires into the model/clip path', () {
    test('SDXL family (CheckpointLoaderSimple)', () {
      final svc = ComfyUIService()
        ..setPreset(pony.preset!)
        ..setLora('style-anime-screencap.safetensors');
      final wf = svc.prepareForTest(
        _loadTemplate(pony.preset!.txt2imgAsset),
        prompt: 'x',
        batch: 2,
        seed: 1,
      );

      final lora = _loraKey(wf);
      final ckpt = wf.entries
          .firstWhere(
            (e) => (e.value as Map)['class_type'] == 'CheckpointLoaderSimple',
          )
          .key;

      // LoRA reads model(0)/clip(1) straight from the checkpoint.
      final li = (wf[lora]['inputs'] as Map);
      expect(li['lora_name'], 'style-anime-screencap.safetensors');
      expect(li['model'], [ckpt, 0]);
      expect(li['clip'], [ckpt, 1]);

      // Sampler now takes its model from the LoRA, encoders take clip from it.
      final ks = wf.values.firstWhere((n) => n['class_type'] == 'KSampler');
      expect(ks['inputs']['model'], [lora, 0]);
      for (final enc
          in wf.values.where((n) => n['class_type'] == 'CLIPTextEncode')) {
        expect(enc['inputs']['clip'], [lora, 1]);
      }

      // VAE still comes from the checkpoint (index 2) — LoRA must not touch it.
      final vae = wf.values.firstWhere((n) => n['class_type'] == 'VAEDecode');
      expect(vae['inputs']['vae'], [ckpt, 2]);

      // Nothing except the LoRA node still consumes the checkpoint's model(0)
      // or clip(1) — i.e. the LoRA is not dangling.
      final leaks = _allEdges(wf).where(
        (e) =>
            e[0] == ckpt &&
            (e[1] == 0 || e[1] == 1) &&
            !identical(e, li['model']) &&
            !identical(e, li['clip']),
      );
      expect(leaks, isEmpty, reason: 'model/clip must route through the LoRA');
    });

    test('flux family (UNETLoader + DualCLIPLoader)', () {
      final svc = ComfyUIService()
        ..setPreset(flux.preset!)
        ..setLora('flux-lora-uncensored.safetensors');
      final wf = svc.prepareForTest(
        _loadTemplate(flux.preset!.txt2imgAsset),
        prompt: 'x',
        batch: 2,
        seed: 1,
      );

      final lora = _loraKey(wf);
      final unet = wf.entries
          .firstWhere((e) => (e.value as Map)['class_type'] == 'UNETLoader')
          .key;
      final dclip = wf.entries
          .firstWhere((e) => (e.value as Map)['class_type'] == 'DualCLIPLoader')
          .key;

      // LoRA reads model from the UNET, clip from the dual CLIP loader.
      final li = (wf[lora]['inputs'] as Map);
      expect(li['lora_name'], 'flux-lora-uncensored.safetensors');
      expect(li['model'], [unet, 0]);
      expect(li['clip'], [dclip, 0]);

      final ks = wf.values.firstWhere((n) => n['class_type'] == 'KSampler');
      expect(ks['inputs']['model'], [lora, 0]);
      for (final enc
          in wf.values.where((n) => n['class_type'] == 'CLIPTextEncode')) {
        expect(enc['inputs']['clip'], [lora, 1]);
      }

      // No other node still consumes UNET(0) or DualCLIP(0) — not dangling.
      final leaks = _allEdges(wf).where(
        (e) =>
            (e[0] == unet && e[1] == 0 || e[0] == dclip && e[1] == 0) &&
            !identical(e, li['model']) &&
            !identical(e, li['clip']),
      );
      expect(leaks, isEmpty, reason: 'model/clip must route through the LoRA');
    });

    test('no LoRA selected → no LoraLoader injected', () {
      final svc = ComfyUIService()..setPreset(pony.preset!);
      final wf = svc.prepareForTest(
        _loadTemplate(pony.preset!.txt2imgAsset),
        prompt: 'x',
        batch: 2,
        seed: 1,
      );
      expect(
        wf.values.where((n) => n['class_type'] == 'LoraLoader'),
        isEmpty,
      );
    });
  });

  group('LoRA strength is part of the node snapshot', () {
    test('round-trips, including a negative (inverted) strength', () {
      for (final v in [0.9, 1.4, -0.6]) {
        final json = GenNode.create(
          prompt: 'x',
          loraName: 'style-anime-screencap.safetensors',
          loraStrength: v,
        ).toJson();
        expect(json['loraStrength'], v);
        expect(GenNode.fromJson(json).loraStrength, v);
      }
    });

    test('absent when no LoRA applies, and survives copyWith', () {
      final plain = GenNode.create(prompt: 'x');
      expect(plain.toJson().containsKey('loraStrength'), isFalse);
      final withLora = GenNode.create(
        prompt: 'x',
        loraName: 'style-anime-screencap.safetensors',
        loraStrength: 1.1,
      ).copyWith(status: GenStatus.ready);
      expect(withLora.loraStrength, 1.1);
    });
  });
}
