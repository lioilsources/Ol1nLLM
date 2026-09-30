// prepareForTest is the service's test seam.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

/// flux-schnell-comfy runs dedicated UNETLoader graphs like flux-manga, but
/// its img2img is a real VAEEncode → KSampler(denoise < 1) graph, so the edit
/// strength has to reach the sampler (the app's chip and the lab's
/// `param.editDenoise` sweep) while the baked-in schnell sampler stays put.
Map<String, dynamic> _load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _node(Map<String, dynamic> wf, String cls) =>
    ((wf.values.firstWhere((n) => (n as Map)['class_type'] == cls)
                as Map)['inputs']
            as Map)
        .cast<String, dynamic>();

Set<String> _classes(Map<String, dynamic> wf) => {
  for (final n in wf.values) (n as Map)['class_type'] as String,
};

void _expectEdgesResolve(Map<String, dynamic> wf) {
  for (final n in wf.values) {
    for (final v in ((n as Map)['inputs'] as Map).values) {
      if (v is List && v.length == 2 && v[0] is String) {
        expect(wf.containsKey(v[0]), isTrue, reason: 'dangling edge $v');
      }
    }
  }
}

void _expectSchnellSampler(Map<String, dynamic> ks) {
  expect(ks['steps'], 4);
  expect(ks['cfg'], 1.0);
  expect(ks['sampler_name'], 'euler');
  expect(ks['scheduler'], 'simple');
}

void main() {
  final spec = imageModelById('flux-schnell-comfy');
  final preset = spec.preset!;
  ComfyUIService svc() => ComfyUIService()..setPreset(preset);

  group('txt2img', () {
    final wf = svc().prepareForTest(
      _load(preset.txt2imgAsset),
      prompt: 'a fox',
      batch: 3,
      seed: 42,
      editDenoise: 0.5, // must not leak into txt2img
    );

    test('loads schnell with the shared flux encoders and VAE', () {
      expect(_node(wf, 'UNETLoader')['unet_name'], preset.unetName);
      final clip = _node(wf, 'DualCLIPLoader');
      expect(clip['type'], 'flux');
      expect(
        {clip['clip_name1'], clip['clip_name2']},
        {'t5xxl_fp16.safetensors', 'clip_l.safetensors'},
      );
      expect(_node(wf, 'VAELoader')['vae_name'], 'ae.safetensors');
    });

    test('no guidance / shift nodes — schnell is guidance-distilled', () {
      expect(_classes(wf), isNot(contains('FluxGuidance')));
      expect(_classes(wf), isNot(contains('ModelSamplingFlux')));
      expect(_classes(wf), contains('EmptySD3LatentImage'));
    });

    test('prompt, batch, seed patched; sampler baked; full denoise', () {
      expect(jsonEncode(wf), isNot(contains('__PROMPT__')));
      expect(
        wf.values.any(
          (n) =>
              (n as Map)['class_type'] == 'CLIPTextEncode' &&
              n['inputs']['text'] == 'a fox',
        ),
        isTrue,
      );
      expect(_node(wf, 'EmptySD3LatentImage')['batch_size'], 3);
      final ks = _node(wf, 'KSampler');
      expect(ks['seed'], 42);
      _expectSchnellSampler(ks);
      expect(ks['denoise'], 1.0);
      _expectEdgesResolve(wf);
    });
  });

  group('img2img', () {
    Map<String, dynamic> edit({double? editDenoise}) => svc().prepareForTest(
      _load(preset.img2imgAsset),
      prompt: 'pixar style',
      batch: 2,
      seed: 7,
      imageName: 'src.png',
      editDenoise: editDenoise,
    );

    test('a real img2img graph: LoadImage → VAEEncode → KSampler', () {
      final wf = edit();
      expect(_node(wf, 'LoadImage')['image'], 'src.png');
      expect(_classes(wf), containsAll(['VAEEncode', 'RepeatLatentBatch']));
      // Not Kontext — that lives on flux-dev only.
      expect(_classes(wf), isNot(contains('ReferenceLatent')));
      expect(_classes(wf), isNot(contains('EmptySD3LatentImage')));
      expect(_node(wf, 'RepeatLatentBatch')['amount'], 2);
      final ks = _node(wf, 'KSampler');
      final latent = ks['latent_image'] as List;
      expect(wf[latent[0]]['class_type'], 'RepeatLatentBatch');
      _expectEdgesResolve(wf);
    });

    test('preset denoise by default', () {
      final ks = _node(edit(), 'KSampler');
      expect(ks['denoise'], preset.img2imgDenoise);
      expect(ks['denoise'], lessThan(1.0));
      _expectSchnellSampler(ks);
    });

    test('edit strength overrides denoise and nothing else', () {
      for (final d in [0.5, 0.65, 0.8]) {
        final ks = _node(edit(editDenoise: d), 'KSampler');
        expect(ks['denoise'], d);
        expect(ks['seed'], 7);
        _expectSchnellSampler(ks);
      }
    });

    test('LoRA wires between the loaders and the sampler', () {
      final wf = (svc()..setLora('flux-lora-uncensored.safetensors'))
          .prepareForTest(
            _load(preset.img2imgAsset),
            prompt: 'x',
            batch: 1,
            seed: 1,
            imageName: 'src.png',
          );
      expect(_node(wf, 'KSampler')['model'], ['__lora__', 0]);
      _expectEdgesResolve(wf);
    });
  });

  test('flux-manga Kontext keeps its baked full denoise', () {
    final manga = imageModelById('flux-manga').preset!;
    final wf = (ComfyUIService()..setPreset(manga)).prepareForTest(
      _load(manga.img2imgAsset),
      prompt: 'x',
      batch: 1,
      seed: 1,
      imageName: 'src.png',
      editDenoise: 0.5,
    );
    expect(_node(wf, 'KSampler')['denoise'], 1.0);
  });
}
