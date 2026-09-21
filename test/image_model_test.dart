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

  group('presets stay servable', () {
    // ComfyUI's own vocabulary (GET /object_info/KSampler). Model cards name
    // samplers the A1111 way — "DPM++ 2M SDE Karras" is one sampler there but
    // a sampler *and* a scheduler here, so a transcribed name fails silently
    // at enqueue. This is the oracle that catches it in CI instead.
    const samplers = {
      'euler', 'euler_cfg_pp', 'euler_ancestral', 'euler_ancestral_cfg_pp',
      'heun', 'heunpp2', 'exp_heun_2_x0', 'exp_heun_2_x0_sde', 'dpm_2',
      'dpm_2_ancestral', 'lms', 'dpm_fast', 'dpm_adaptive',
      'dpmpp_2s_ancestral', 'dpmpp_2s_ancestral_cfg_pp', 'dpmpp_sde',
      'dpmpp_sde_gpu', 'dpmpp_2m', 'dpmpp_2m_cfg_pp', 'dpmpp_2m_sde',
      'dpmpp_2m_sde_gpu', 'dpmpp_2m_sde_heun', 'dpmpp_2m_sde_heun_gpu',
      'dpmpp_3m_sde', 'dpmpp_3m_sde_gpu', 'ddpm', 'lcm', 'ipndm', 'ipndm_v',
      'deis', 'res_multistep', 'res_multistep_cfg_pp',
      'res_multistep_ancestral', 'res_multistep_ancestral_cfg_pp',
      'gradient_estimation', 'gradient_estimation_cfg_pp', 'er_sde',
      'seeds_2', 'seeds_3', 'sa_solver', 'sa_solver_pece', 'ddim', 'uni_pc',
      'uni_pc_bh2',
    };
    const schedulers = {
      'simple', 'sgm_uniform', 'karras', 'exponential', 'ddim_uniform',
      'beta', 'normal', 'linear_quadratic', 'kl_optimal',
    };

    test('every preset names a sampler and scheduler ComfyUI knows', () {
      for (final m in kImageModels) {
        final preset = m.preset;
        if (preset == null) continue;
        expect(samplers, contains(preset.samplerName), reason: m.id);
        expect(schedulers, contains(preset.scheduler), reason: m.id);
      }
    });

    test('inpaint-capable models ship an inpaint workflow', () {
      for (final m in kImageModels.where((m) => m.inpaint)) {
        expect(m.kind, ImageBackendKind.comfyUi, reason: m.id);
        expect(m.preset?.inpaintAsset, isNotNull, reason: m.id);
      }
    });
  });
}
