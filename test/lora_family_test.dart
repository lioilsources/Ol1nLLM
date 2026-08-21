import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';

/// The registry is evidence-based: every expectation below matches what the
/// file's own safetensors metadata says (ss_base_model_version /
/// ss_sd_model_name, read from ComfyUI's /view_metadata/loras). Names are the
/// real server catalog, so a wrong guess here is a wrong offer in the picker.
void main() {
  group('familyOfLora — curated registry', () {
    const cases = <String, LoraFamily>{
      // FLUX (base flux1)
      'flux-lora-uncensored.safetensors': LoraFamily.flux,
      'pussydiffusion-flux1.safetensors': LoraFamily.flux,
      'lora-000013.TA_trained.safetensors': LoraFamily.flux,
      'sldr_flux_nsfw_v2-studio.safetensors': LoraFamily.flux,
      // Illustrious / NoobAI
      'style-anime-screencap.safetensors': LoraFamily.illustrious,
      'style-usnr-thin-paint.safetensors': LoraFamily.illustrious,
      'util-stabilizer-il.safetensors': LoraFamily.illustrious,
      // Pony
      'Starship_Hulls_-_Pony_r1.safetensors': LoraFamily.pony,
      'Spacecraft.safetensors': LoraFamily.pony,
      // vanilla SDXL
      'real-pussy-lily-xl.safetensors': LoraFamily.sdxl,
      'sdxl_lightning_8step_lora.safetensors': LoraFamily.sdxl,
      // SD 1.5 / NAI — the trap: these read like SDXL character LoRAs
      'sexy_attire.safetensors': LoraFamily.sd15,
      'CARDOGGY.safetensors': LoraFamily.sd15,
      'povFacesitting.safetensors': LoraFamily.sd15,
      'spaceship.safetensors': LoraFamily.sd15,
      // other architectures
      'Wan2.2-T2V-A14B-4steps-lora-rank64-Seko-V1.1_high_noise_model.safetensors':
          LoraFamily.wan,
      'heelsup_v2_22.safetensors': LoraFamily.zimage,
      // no metadata, no telling name
      'Shenhe_Hard.safetensors': LoraFamily.unknown,
      'avatar/testface.safetensors': LoraFamily.unknown,
    };
    cases.forEach((name, want) {
      test('$name → ${want.name}', () => expect(familyOfLora(name), want));
    });

    test('subfolder and case do not matter', () {
      expect(familyOfLora('sub/SEXY_ATTIRE.safetensors'), LoraFamily.sd15);
    });
  });

  group('familyOfLora — filename fallback', () {
    test('names that say their lineage', () {
      expect(familyOfLora('some-new-flux-thing.safetensors'), LoraFamily.flux);
      expect(familyOfLora('cute-pony-style.safetensors'), LoraFamily.pony);
      expect(familyOfLora('freckles-il.safetensors'), LoraFamily.illustrious);
      expect(familyOfLora('noobai-hands.safetensors'), LoraFamily.illustrious);
      expect(familyOfLora('detail-tweaker-xl.safetensors'), LoraFamily.sdxl);
    });

    test('a name that says nothing stays unknown (offered, flagged)', () {
      expect(familyOfLora('mystery_v3.safetensors'), LoraFamily.unknown);
    });
  });

  group('loraFit', () {
    test('same lineage is native', () {
      expect(loraFit(LoraFamily.pony, LoraFamily.pony), LoraFit.native);
    });

    test('SDXL lineages cross over weakly', () {
      expect(
        loraFit(LoraFamily.illustrious, LoraFamily.sdxl),
        LoraFit.weak,
      );
      expect(loraFit(LoraFamily.sdxl, LoraFamily.pony), LoraFit.weak);
    });

    test('different architecture is incompatible', () {
      // The whole point: an SD 1.5 LoRA on SDXL half-loads through the shared
      // CLIP-L and corrupts the prompt instead of applying its concept.
      expect(loraFit(LoraFamily.sd15, LoraFamily.sdxl), LoraFit.incompatible);
      expect(loraFit(LoraFamily.flux, LoraFamily.illustrious),
          LoraFit.incompatible);
      expect(loraFit(LoraFamily.sdxl, LoraFamily.flux), LoraFit.incompatible);
      expect(loraFit(LoraFamily.wan, LoraFamily.pony), LoraFit.incompatible);
      expect(loraFit(LoraFamily.zimage, LoraFamily.sdxl),
          LoraFit.incompatible);
    });

    test('unknown origin is offered but flagged', () {
      expect(loraFit(LoraFamily.unknown, LoraFamily.pony), LoraFit.unknown);
    });

    test('a model that takes no LoRA accepts nothing', () {
      expect(loraFit(LoraFamily.flux, LoraFamily.none), LoraFit.incompatible);
    });
  });

  group('lorasForFamily', () {
    const catalog = [
      'sexy_attire.safetensors', // sd15 — must vanish for SDXL models
      'flux-lora-uncensored.safetensors', // flux
      'style-anime-screencap.safetensors', // illustrious
      'real-pussy-lily-xl.safetensors', // sdxl
      'Spacecraft.safetensors', // pony
      'Shenhe_Hard.safetensors', // unknown
      'Wan2.2-T2V-A14B-4steps-lora-rank64-Seko-V1.1_high_noise_model.safetensors',
    ];

    test('illustrious model: native first, then other SDXL, then unknown', () {
      expect(lorasForFamily(catalog, LoraFamily.illustrious), [
        'style-anime-screencap.safetensors',
        'real-pussy-lily-xl.safetensors',
        'Spacecraft.safetensors',
        'Shenhe_Hard.safetensors',
      ]);
    });

    test('SD 1.5, FLUX and video files never reach an SDXL model', () {
      final offered = lorasForFamily(catalog, LoraFamily.sdxl);
      expect(offered, isNot(contains('sexy_attire.safetensors')));
      expect(offered, isNot(contains('flux-lora-uncensored.safetensors')));
      expect(offered.any((n) => n.startsWith('Wan2.2')), isFalse);
      expect(offered.first, 'real-pussy-lily-xl.safetensors');
    });

    test('flux model gets flux files, plus unknowns flagged at the end', () {
      // Unknown origin is never hidden: a brand-new LoRA whose name says
      // nothing would otherwise be invisible until someone edits the
      // registry — the same trap curated checkpoints already have.
      expect(lorasForFamily(catalog, LoraFamily.flux), [
        'flux-lora-uncensored.safetensors',
        'Shenhe_Hard.safetensors',
      ]);
    });

    test('a no-LoRA model gets an empty list', () {
      expect(lorasForFamily(catalog, LoraFamily.none), isEmpty);
    });
  });

  group('model registry', () {
    test('lineages match the checkpoints', () {
      LoraFamily famOf(String id) => imageModelById(id).loraFamily;
      expect(famOf('pony'), LoraFamily.pony);
      expect(famOf('atomix-pony-anime'), LoraFamily.pony);
      expect(famOf('illustrious-xl'), LoraFamily.illustrious);
      expect(famOf('noobai-xl'), LoraFamily.illustrious);
      expect(famOf('wai-illustrious'), LoraFamily.illustrious);
      expect(famOf('juggernaut-xl'), LoraFamily.sdxl);
      expect(famOf('juggernaut-xl-lightning'), LoraFamily.sdxl);
      expect(famOf('flux-manga'), LoraFamily.flux);
      // sd15 and the NIM models declare no LoRA support at all.
      expect(famOf('sd15'), LoraFamily.none);
      expect(famOf('flux-schnell'), LoraFamily.none);
    });

    test('no model offers a cross-architecture LoRA', () {
      const catalog = [
        'sexy_attire.safetensors',
        'flux-lora-uncensored.safetensors',
        'style-anime-screencap.safetensors',
      ];
      for (final m in kImageModels) {
        for (final n in lorasForFamily(catalog, m.loraFamily)) {
          expect(fitOfLora(n, m.loraFamily), isNot(LoraFit.incompatible),
              reason: '${m.id} offers $n');
        }
      }
    });
  });
}
