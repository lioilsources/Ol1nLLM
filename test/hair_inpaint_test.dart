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
    for (final id in ['flux-fill', 'juggernaut-xl']) {
      test('$id: no hole filling, bench context, mask substituted', () {
        final spec = imageModelById(id);
        final svc = ComfyUIService()..setPreset(spec.preset!);
        final wf = svc.prepareHairInpaint(
          _load(spec.preset!.inpaintAsset!),
          prompt: 'a photo of the same person with a pixie cut',
          batch: 1,
          seed: 7,
          imageName: 'photo.png',
          maskName: 'hairmask.png',
        );
        final dump = jsonEncode(wf);
        expect(dump, isNot(contains('__MASK__')));
        expect(dump, isNot(contains('__IMAGE__')));
        final crop = wf.values.cast<Map<String, dynamic>>().firstWhere(
          (n) => n['class_type'] == 'InpaintCropImproved',
        );
        expect(crop['inputs']['mask_fill_holes'], isFalse);
        expect(
          crop['inputs']['context_from_mask_extend_factor'],
          kHairContextFactor,
        );
        // a drawn-mask inpaint keeps its own crop settings
        final plain = svc.prepareForTest(
          _load(spec.preset!.inpaintAsset!),
          prompt: 'x',
          batch: 1,
          seed: 7,
          imageName: 'p.png',
          maskName: 'm.png',
        );
        final plainCrop = plain.values.cast<Map<String, dynamic>>().firstWhere(
          (n) => n['class_type'] == 'InpaintCropImproved',
        );
        expect(plainCrop['inputs']['mask_fill_holes'], isTrue);
      });
    }

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
