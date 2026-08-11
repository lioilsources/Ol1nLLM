import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

/// Verifies the inpaint request path against the real workflow assets:
/// __MASK__ substitution, full-denoise override (the generic template ships
/// denoise 1.0 and the patcher must NOT lower it to img2imgDenoise), batch
/// wiring through both Repeat nodes, and the flux-fill LoRA ban.
Map<String, dynamic> _loadTemplate(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

String _jsonOf(Map<String, dynamic> wf) => jsonEncode(wf);

void main() {
  final pony = imageModelById('pony');
  final fill = imageModelById('flux-fill');

  group('registry', () {
    test('inpaint capability matches assets', () {
      expect(pony.inpaint, isTrue);
      expect(pony.preset!.inpaintAsset, 'assets/comfyui/sdxl_inpaint.api.json');
      expect(fill.inpaint, isTrue);
      expect(fill.txt2img, isFalse);
      expect(fill.img2img, isFalse);
      expect(fill.capabilityLabel, 'inpaint');
      expect(imageModelById('sd15').inpaint, isFalse);
      expect(imageModelById('flux-manga').inpaint, isFalse);
    });

    test('reference inpaint: SDXL via IPAdapter, Fill via Redux', () {
      expect(pony.inpaintRef, isTrue);
      expect(
        pony.preset!.inpaintRefAsset,
        'assets/comfyui/sdxl_inpaint_ref.api.json',
      );
      expect(fill.inpaintRef, isTrue);
      expect(
        fill.preset!.inpaintRefAsset,
        'assets/comfyui/flux_fill_inpaint_ref.api.json',
      );
      expect(imageModelById('sd15').inpaintRef, isFalse);
    });
  });

  group('FLUX Fill + Redux reference template', () {
    Map<String, dynamic> prepare({String? lora}) {
      final svc = ComfyUIService()..setPreset(fill.preset!);
      if (lora != null) svc.setLora(lora);
      return svc.prepareForTest(
        _loadTemplate(fill.preset!.inpaintRefAsset!),
        prompt: 'a ball',
        batch: 2,
        seed: 3,
        imageName: 'src.png',
        maskName: 'mask.png',
        refName: 'ref.png',
      );
    }

    test('sentinels resolve; Redux chain feeds guidance; baked values live', () {
      final wf = prepare();
      final s = _jsonOf(wf);
      expect(s, isNot(contains('__REF__')));
      expect(s, isNot(contains('__MASK__')));
      expect(s, isNot(contains('__IMAGE__')));

      // Conditioning chain: text encode → StyleModelApply → FluxGuidance.
      final applyKey = wf.entries
          .firstWhere(
            (e) => (e.value as Map)['class_type'] == 'StyleModelApply',
          )
          .key;
      final guidance =
          wf.values.firstWhere((n) => n['class_type'] == 'FluxGuidance');
      expect(guidance['inputs']['conditioning'], [applyKey, 0]);
      expect(guidance['inputs']['guidance'], 30.0);

      final ks = wf.values.firstWhere((n) => n['class_type'] == 'KSampler');
      expect(ks['inputs']['cfg'], 1.0);
      expect(ks['inputs']['denoise'], 1.0);
    });

    test('LoRA stays banned on the dedicated Fill-ref workflow', () {
      final wf = prepare(lora: 'flux-lora-style.safetensors');
      expect(
        wf.values.where((n) => n['class_type'] == 'LoraLoader'),
        isEmpty,
      );
    });
  });

  group('SDXL reference-inpaint template (IPAdapter)', () {
    Map<String, dynamic> prepare() {
      final svc = ComfyUIService()..setPreset(pony.preset!);
      return svc.prepareForTest(
        _loadTemplate(pony.preset!.inpaintRefAsset!),
        prompt: 'a ball',
        batch: 2,
        seed: 5,
        imageName: 'src.png',
        maskName: 'mask.png',
        refName: 'ref.png',
      );
    }

    test('all three image sentinels resolve; denoise stays 1.0', () {
      final wf = prepare();
      final s = _jsonOf(wf);
      expect(s, isNot(contains('__IMAGE__')));
      expect(s, isNot(contains('__MASK__')));
      expect(s, isNot(contains('__REF__')));
      expect(s, contains('ref.png'));
      final ks = wf.values.firstWhere((n) => n['class_type'] == 'KSampler');
      expect(ks['inputs']['denoise'], 1.0);
    });

    test('IPAdapter is mask-restricted and feeds the Fooocus chain', () {
      final wf = prepare();
      final ip = wf.values
          .firstWhere((n) => n['class_type'] == 'IPAdapterAdvanced');
      final cropKey = wf.entries
          .firstWhere(
            (e) => (e.value as Map)['class_type'] == 'InpaintCropImproved',
          )
          .key;
      // attn_mask must be the CROPPED mask (the sampler works on the crop) —
      // without it the reference bleeds into the whole image.
      expect(ip['inputs']['attn_mask'], [cropKey, 2]);

      // Model chain: checkpoint → IPAdapter → Fooocus patch → KSampler.
      final ipKey = wf.entries
          .firstWhere(
            (e) => (e.value as Map)['class_type'] == 'IPAdapterAdvanced',
          )
          .key;
      final apply = wf.values.firstWhere(
        (n) => n['class_type'] == 'INPAINT_ApplyFooocusInpaint',
      );
      expect(apply['inputs']['model'], [ipKey, 0]);
    });
  });

  group('SDXL inpaint template (Fooocus patch)', () {
    Map<String, dynamic> prepare({String? lora}) {
      final svc = ComfyUIService()..setPreset(pony.preset!);
      if (lora != null) svc.setLora(lora);
      return svc.prepareForTest(
        _loadTemplate(pony.preset!.inpaintAsset!),
        prompt: 'a duck',
        batch: 3,
        seed: 7,
        imageName: 'src.png',
        maskName: 'mask.png',
      );
    }

    test('sentinels resolved, denoise stays 1.0, batch patched', () {
      final wf = prepare();
      final s = _jsonOf(wf);
      expect(s, isNot(contains('__MASK__')));
      expect(s, isNot(contains('__IMAGE__')));
      expect(s, isNot(contains('__CKPT__')));
      expect(s, isNot(contains('__PROMPT__')));
      expect(s, isNot(contains('__NEGATIVE__')));

      final ks = wf.values.firstWhere((n) => n['class_type'] == 'KSampler');
      // The whole point of the mask-aware branch: img2imgDenoise (0.72) must
      // NOT apply even though imageName != null.
      expect(ks['inputs']['denoise'], 1.0);
      expect(ks['inputs']['seed'], 7);
      // Preset values still patch in for generic templates.
      expect(ks['inputs']['steps'], pony.preset!.steps);

      final repeat =
          wf.values.firstWhere((n) => n['class_type'] == 'RepeatLatentBatch');
      expect(repeat['inputs']['amount'], 3);
    });

    test('crop&stitch wraps the graph (sharpness fix)', () {
      final wf = prepare();
      final cropKey = wf.entries
          .firstWhere(
            (e) => (e.value as Map)['class_type'] == 'InpaintCropImproved',
          )
          .key;
      // The sampler must work on the upscaled crop, not the full canvas.
      final enc = wf.values
          .firstWhere((n) => n['class_type'] == 'VAEEncodeForInpaint');
      expect(enc['inputs']['pixels'], [cropKey, 1]);
      expect(enc['inputs']['mask'], [cropKey, 2]);
      // And the output goes through the stitch, not a raw composite.
      final stitchKey = wf.entries
          .firstWhere(
            (e) => (e.value as Map)['class_type'] == 'InpaintStitchImproved',
          )
          .key;
      final save =
          wf.values.firstWhere((n) => n['class_type'] == 'SaveImage');
      expect(save['inputs']['images'], [stitchKey, 0]);
    });

    test('Fooocus patch reads the unbatched latent (M1 tensor-mismatch)', () {
      final wf = prepare();
      final apply = wf.values
          .firstWhere((n) => n['class_type'] == 'INPAINT_ApplyFooocusInpaint');
      final vaeEncodeKey = wf.entries
          .firstWhere(
            (e) => (e.value as Map)['class_type'] == 'VAEEncodeForInpaint',
          )
          .key;
      expect(apply['inputs']['latent'], [vaeEncodeKey, 0],
          reason: 'batched latent here breaks noise_mask broadcasting');
    });

    test('SDXL inpaint keeps LoRA support', () {
      final wf = prepare(lora: 'style.safetensors');
      expect(
        wf.values.where((n) => n['class_type'] == 'LoraLoader'),
        hasLength(1),
      );
    });
  });

  group('FLUX Fill template', () {
    Map<String, dynamic> prepare({String? lora}) {
      final svc = ComfyUIService()..setPreset(fill.preset!);
      if (lora != null) svc.setLora(lora);
      return svc.prepareForTest(
        _loadTemplate(fill.preset!.inpaintAsset!),
        prompt: 'a duck',
        batch: 2,
        seed: 9,
        imageName: 'src.png',
        maskName: 'mask.png',
      );
    }

    test('sentinels resolved, baked values untouched, batch patched', () {
      final wf = prepare();
      final s = _jsonOf(wf);
      expect(s, isNot(contains('__MASK__')));
      expect(s, isNot(contains('__IMAGE__')));
      expect(s, isNot(contains('__PROMPT__')));

      final ks = wf.values.firstWhere((n) => n['class_type'] == 'KSampler');
      // Dedicated workflow (ckptName == null): baked cfg/steps must survive.
      expect(ks['inputs']['cfg'], 1.0);
      expect(ks['inputs']['steps'], 28);
      expect(ks['inputs']['seed'], 9);

      final guidance =
          wf.values.firstWhere((n) => n['class_type'] == 'FluxGuidance');
      expect(guidance['inputs']['guidance'], 30.0);

      final repeat =
          wf.values.firstWhere((n) => n['class_type'] == 'RepeatLatentBatch');
      expect(repeat['inputs']['amount'], 2);
    });

    test('LoRA is banned on the dedicated Fill workflow', () {
      final wf = prepare(lora: 'flux-lora-style.safetensors');
      expect(
        wf.values.where((n) => n['class_type'] == 'LoraLoader'),
        isEmpty,
        reason: 'Fill + LoRA is banned until the M5 experiment',
      );
    });
  });
}
