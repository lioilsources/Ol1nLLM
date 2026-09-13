import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/gen_node.dart';
import 'package:ol1n_llm/models/hair_mask.dart';
import 'package:ol1n_llm/models/hairstyle_preset.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

Map<String, dynamic> _load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('hairInpaint graph', () {
    test('SDXL: no hole filling, bench context, inpaint-nodes encoder', () {
      final spec = imageModelById('juggernaut-xl');
      final svc = ComfyUIService()..setPreset(spec.preset!);
      expect(svc.hairUsesInstruction, isFalse);
      final wf = svc.prepareHairInpaint(
        _load(spec.preset!.inpaintAsset!),
        prompt: 'a photo of the same person with a pixie cut',
        batch: 2,
        seed: 7,
        imageName: 'photo.png',
        maskName: 'hairmask.png',
      );
      final dump = jsonEncode(wf);
      expect(dump, isNot(contains('__MASK__')));
      expect(dump, isNot(contains('VAEEncodeForInpaint')));
      Map<String, dynamic> byClass(String c) => wf.values
          .cast<Map<String, dynamic>>()
          .firstWhere((n) => n['class_type'] == c);
      final crop = byClass('InpaintCropImproved')['inputs'];
      expect(crop['mask_fill_holes'], isFalse);
      expect(crop['context_from_mask_extend_factor'], kHairContextFactor);
      final encId = wf.entries
          .firstWhere((e) => e.value['class_type'] == 'INPAINT_VAEEncodeInpaintConditioning')
          .key;
      final ks = byClass('KSampler')['inputs'];
      expect(ks['positive'], [encId, 0]);
      expect(ks['negative'], [encId, 1]);
      expect(byClass('INPAINT_ApplyFooocusInpaint')['inputs']['latent'], [encId, 2]);
      // the batch repeat now reads the sampling latent
      expect(byClass('RepeatLatentBatch')['inputs']['samples'], [encId, 3]);
      final enc = wf[encId]['inputs'];
      expect(enc['positive'], isNot([encId, 0]));
      // a drawn-mask inpaint keeps its own graph
      final plain = svc.prepareForTest(
        _load(spec.preset!.inpaintAsset!),
        prompt: 'x', batch: 1, seed: 7, imageName: 'p.png', maskName: 'm.png',
      );
      expect(jsonEncode(plain), contains('VAEEncodeForInpaint'));
    });

    test('FLUX: Kontext edit pasted back through the mask', () {
      final spec = imageModelById('flux-fill');
      final svc = ComfyUIService()..setPreset(spec.preset!);
      expect(svc.hairUsesInstruction, isTrue);
      final wf = svc.prepareHairInpaint(
        _load('assets/comfyui/flux_hair_kontext.api.json'),
        prompt: "Change the person's hairstyle to a pixie cut.",
        batch: 1,
        seed: 7,
        imageName: 'photo.png',
        maskName: 'hairmask.png',
      );
      final nodes = wf.values.cast<Map<String, dynamic>>();
      final loads = nodes.where((n) => n['class_type'] == 'LoadImage').map((n) => n['inputs']['image']).toSet();
      expect(loads, {'photo.png', 'hairmask.png'});
      expect(nodes.any((n) => n['class_type'] == 'ImageCompositeMasked'), isTrue);
      expect(jsonEncode(wf), contains("Change the person's hairstyle"));
    });

    test('analysis graph has no sampler and passes _prepare untouched', () {
      final svc = ComfyUIService()
        ..setPreset(imageModelById('flux-fill').preset!);
      final wf = svc.prepareForTest(
        _load('assets/comfyui/hair_analyse.api.json'),
        prompt: '',
        batch: 1,
        seed: 0,
        imageName: 'photo.png',
      );
      expect(jsonEncode(wf), isNot(contains('__IMAGE__')));
      expect(
        wf.values.cast<Map<String, dynamic>>().where(
          (n) => n['class_type'] == 'KSampler',
        ),
        isEmpty,
      );
      final prefixes = wf.values
          .cast<Map<String, dynamic>>()
          .where((n) => n['class_type'] == 'SaveImage')
          .map((n) => n['inputs']['filename_prefix'])
          .toSet();
      const p = ComfyUIService.kHairAnalysePrefixes;
      expect(prefixes, {p.hair, p.face, p.hat, p.features});
    });

    test('outputs are matched by filename prefix, not order', () {
      final refs = ComfyUIService.hairOutputRefs({
        'outputs': {
          '13': {
            'images': [
              {
                'filename': 'tsumiki_features_mask_00001_.png',
                'type': 'output',
              },
            ],
          },
          '4': {
            'images': [
              {'filename': 'tsumiki_hair_mask_00001_.png', 'type': 'output'},
              {'filename': 'preview.png', 'type': 'temp'},
            ],
          },
          '7': {
            'images': [
              {'filename': 'tsumiki_face_mask_00001_.png', 'type': 'output'},
            ],
          },
        },
      });
      expect(refs.keys.toSet(), {
        'tsumiki_features_mask',
        'tsumiki_hair_mask',
        'tsumiki_face_mask',
      });
      expect(
        refs['tsumiki_hair_mask']!['filename'],
        startsWith('tsumiki_hair_mask_'),
      );
    });
  });

  group('GenNode.hairstyleId', () {
    test('round-trips, legacy JSON has none, copyWith keeps it', () {
      final node = GenNode.create(
        prompt: 'p',
        hairstyleId: 'wolf-cut',
        maskFileName: 'm.png',
      );
      final back = GenNode.fromJson(node.toJson());
      expect(back.hairstyleId, 'wolf-cut');
      expect(back.copyWith(status: GenStatus.ready).hairstyleId, 'wolf-cut');
      final plain = GenNode.create(prompt: 'p');
      expect(plain.toJson().containsKey('hairstyleId'), isFalse);
      expect(GenNode.fromJson(plain.toJson()).hairstyleId, isNull);
    });
  });

  group('prompt', () {
    const pixie = HairstylePreset(
      id: 'pixie',
      label: 'Pixie',
      group: kHairGroupWomen,
      section: 'Střihy',
      block: "pixie cut, very short cropped women's haircut",
      shape: HairShape(length: HairLength.short),
    );
    test('new colour and keep-cut mirror hairprompt.py', () {
      const auburn = HairColourPreset(id: 'auburn', label: 'Kaštanově zrzavá', phrase: 'deep auburn');
      expect(hairPrompt(pixie, 'brown', newColour: auburn), contains('deep auburn hair'));
      expect(hairPrompt(pixie, 'brown', newColour: auburn), isNot(contains('brown hair')));
      expect(hairPrompt(pixie, 'brown', instruction: true, newColour: auburn), contains('Dye the hair deep auburn.'));
      expect(
        hairPrompt(kKeepCutPreset, 'brown', instruction: true, newColour: auburn),
        startsWith("Change the person's hair colour to deep auburn. Keep the haircut, length and hair texture."),
      );
      expect(
        hairPrompt(kKeepCutPreset, 'brown', newColour: auburn),
        startsWith('a photo of the same person with the same haircut as in the photo, deep auburn hair'),
      );
    });

    test('instruction variant for Kontext', () {
      final t = hairPrompt(pixie, null, instruction: true);
      expect(t, startsWith("Change the person's hairstyle to a pixie cut"));
      expect(t, contains('Keep the natural hair colour.'));
    });

    test('matches Tsumiki with the colour filled in', () {
      expect(
        hairPrompt(pixie, 'brown'),
        "a photo of the same person with a pixie cut, very short cropped women's "
        'haircut, short hair ending above the jaw with the neck clear of hair, '
        'brown hair, natural hair texture, realistic strands, same clothes, '
        'same lighting and background, photorealistic',
      );
      expect(hairPrompt(pixie, null), contains(', natural hair, '));
    });

    test('search folds diacritics', () {
      const s = HairstylePreset(
        id: 'messy-bun',
        label: 'Rozcuchaný drdol',
        group: kHairGroupWomen,
        section: 'Účesy nahoru',
        block: 'messy bun',
        shape: HairShape(length: HairLength.keep, updo: true),
      );
      expect(hairstyleMatchesQuery(s, 'rozcuchany'), isTrue);
      expect(hairstyleMatchesQuery(s, 'bun'), isTrue);
      expect(hairstyleMatchesQuery(s, 'pixie'), isFalse);
    });
  });
}
