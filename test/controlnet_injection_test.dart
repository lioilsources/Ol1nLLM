import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';
import 'package:ol1n_llm/services/image_backend.dart';

/// Verifies ControlNet injection precedence in img2img:
///   • a picked template pose (OpenPose skeleton) overrides everything
///   • otherwise the source photo's structure is carried over via a depth map
///   • txt2img / no-source never gets the depth path
///   • repose: an explicit depth reference pins a txt2img render (denoise 1.0)
///     and beats a template pose
/// and that whichever runs actually rewires the sampler's conditioning through
/// a ControlNetApplyAdvanced (not left dangling).
Map<String, dynamic> _img2img() => jsonDecode(
  File(imageModelById('pony').preset!.img2imgAsset).readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> _txt2img() => jsonDecode(
  File(imageModelById('pony').preset!.txt2imgAsset).readAsStringSync(),
) as Map<String, dynamic>;

Iterable<Map> _byClass(Map<String, dynamic> wf, String cls) =>
    wf.values.map((e) => e as Map).where((n) => n['class_type'] == cls);

/// The KSampler's rewired positive conditioning edge.
List _samplerPositive(Map<String, dynamic> wf) =>
    _byClass(wf, 'KSampler').first['inputs']['positive'] as List;

Map _sampler(Map<String, dynamic> wf) =>
    _byClass(wf, 'KSampler').first['inputs'] as Map;

/// Every `[nodeId, output]` edge in the graph.
List<List> _allEdges(Map<String, dynamic> wf) => [
  for (final e in wf.values)
    for (final v in ((e as Map)['inputs'] as Map? ?? {}).values)
      if (v is List && v.length == 2 && v[0] is String) v,
];

void main() {
  final pony = imageModelById('pony').preset!;

  test('template pose overrides source depth (img2img)', () {
    final svc = ComfyUIService()..setPreset(pony);
    final wf = svc.prepareForTest(
      _img2img(),
      prompt: 'x',
      batch: 1,
      seed: 1,
      imageName: 'source.png',
      poseImageName: 'skeleton.png', // a template pose is active
      sourceDepth: true, // …and it must win over this
    );

    // OpenPose path injected, depth path absent.
    expect(_byClass(wf, 'ControlNetLoader').first['inputs']['control_net_name'],
        contains('openpose'));
    expect(_byClass(wf, 'DepthAnythingV2Preprocessor'), isEmpty);
    expect(_byClass(wf, 'SetUnionControlNetType'), isEmpty);

    // Sampler routed through the apply node, which reads the skeleton image.
    final apply = _byClass(wf, 'ControlNetApplyAdvanced').first;
    expect(_samplerPositive(wf), ['__cn_apply__', 0]);
    expect(apply['inputs']['image'], ['__pose_image__', 0]);
  });

  test('source depth applied when no template pose (img2img)', () {
    final svc = ComfyUIService()..setPreset(pony);
    final wf = svc.prepareForTest(
      _img2img(),
      prompt: 'x',
      batch: 1,
      seed: 1,
      imageName: 'source.png',
      sourceDepth: true,
    );

    // Depth chain: source → DepthAnythingV2 → Union CN (depth) → apply.
    final pre = _byClass(wf, 'DepthAnythingV2Preprocessor').first;
    expect(pre['inputs']['image'], ['__depth_src__', 0]);
    final type = _byClass(wf, 'SetUnionControlNetType').first;
    expect(type['inputs']['type'], 'depth');
    expect(type['inputs']['control_net'], ['__depth_cn__', 0]);
    expect(_byClass(wf, 'ControlNetLoader').first['inputs']['control_net_name'],
        contains('union'));

    final apply = _byClass(wf, 'ControlNetApplyAdvanced').first;
    expect(apply['inputs']['control_net'], ['__depth_type__', 0]);
    expect(apply['inputs']['image'], ['__depth_pre__', 0]);
    // img2img auto-depth keeps its tuned values (repose uses its own).
    expect(apply['inputs']['strength'], 0.7);
    expect(apply['inputs']['end_percent'], 1.0);
    // Not dangling: sampler conditioning flows through the apply node.
    expect(_samplerPositive(wf), ['__cn_apply__', 0]);

    // No OpenPose skeleton in this path.
    expect(_byClass(wf, 'LoadImage').where(
      (n) => (n['_meta']?['title'] as String? ?? '').startsWith('Pose:'),
    ), isEmpty);
  });

  test('txt2img never gets the source-depth path', () {
    final svc = ComfyUIService()..setPreset(pony);
    final wf = svc.prepareForTest(
      _txt2img(),
      prompt: 'x',
      batch: 1,
      seed: 1,
      sourceDepth: true, // no imageName ⇒ must be ignored
    );
    expect(_byClass(wf, 'ControlNetApplyAdvanced'), isEmpty);
    expect(_byClass(wf, 'DepthAnythingV2Preprocessor'), isEmpty);
  });

  test('plain img2img with autopose off gets no ControlNet', () {
    final svc = ComfyUIService()..setPreset(pony);
    final wf = svc.prepareForTest(
      _img2img(),
      prompt: 'x',
      batch: 1,
      seed: 1,
      imageName: 'source.png',
      sourceDepth: false,
    );
    expect(_byClass(wf, 'ControlNetApplyAdvanced'), isEmpty);
  });

  group('repose: depth reference over the txt2img template', () {
    Map<String, dynamic> repose(
      ComfyUIService svc, {
      String? poseImageName,
      String? userNegative,
    }) => svc.prepareForTest(
      _txt2img(),
      prompt: 'a knight in armor',
      batch: 2,
      seed: 7,
      depthImageName: 'ref.png',
      latentSize: (w: 832, h: 1216),
      poseImageName: poseImageName,
      userNegative: userNegative,
    );

    test('injects the full depth chain from the reference', () {
      final wf = repose(ComfyUIService()..setPreset(pony));
      final src = _byClass(wf, 'LoadImage').single;
      expect(src['inputs']['image'], 'ref.png');
      final pre = _byClass(wf, 'DepthAnythingV2Preprocessor').single;
      expect(pre['inputs']['image'], ['__depth_src__', 0]);
      expect(_byClass(wf, 'SetUnionControlNetType').single['inputs']['type'],
          'depth');
      expect(
        _byClass(wf, 'ControlNetLoader').single['inputs']['control_net_name'],
        contains('union'),
      );
    });

    test('applies repose strength/schedule and rewires the sampler', () {
      final wf = repose(ComfyUIService()..setPreset(pony));
      final apply = _byClass(wf, 'ControlNetApplyAdvanced').single;
      expect(apply['inputs']['image'], ['__depth_pre__', 0]);
      expect(apply['inputs']['strength'], 0.75);
      expect(apply['inputs']['start_percent'], 0.0);
      expect(apply['inputs']['end_percent'], 0.9);
      expect(_sampler(wf)['positive'], ['__cn_apply__', 0]);
      expect(_sampler(wf)['negative'], ['__cn_apply__', 1]);
    });

    test('renders from noise: denoise 1.0, no VAEEncode, no __IMAGE__', () {
      final wf = repose(ComfyUIService()..setPreset(pony));
      expect(_sampler(wf)['denoise'], 1.0);
      expect(_byClass(wf, 'VAEEncode'), isEmpty);
      expect(jsonEncode(wf), isNot(contains('__IMAGE__')));
    });

    test('latent follows the reference bucket, batch still applied', () {
      final wf = repose(ComfyUIService()..setPreset(pony));
      final latent = _byClass(wf, 'EmptyLatentImage').single['inputs'];
      expect(latent['width'], 832);
      expect(latent['height'], 1216);
      expect(latent['batch_size'], 2);
    });

    test('a template pose is ignored — the reference is the pose', () {
      final wf = repose(
        ComfyUIService()..setPreset(pony),
        poseImageName: 'skeleton.png',
      );
      expect(
        _byClass(wf, 'ControlNetLoader')
            .where((n) => (n['inputs']['control_net_name'] as String)
                .contains('openpose')),
        isEmpty,
      );
      expect(_byClass(wf, 'LoadImage').where(
        (n) => (n['_meta']?['title'] as String? ?? '').startsWith('Pose:'),
      ), isEmpty);
      final apply = _byClass(wf, 'ControlNetApplyAdvanced').single;
      expect(apply['inputs']['image'], ['__depth_pre__', 0]);
    });

    test('composes with a LoRA without dangling edges', () {
      final wf = repose(
        ComfyUIService()
          ..setPreset(pony)
          ..setLora('style-anime-screencap.safetensors'),
      );
      expect(wf.containsKey('__lora__'), isTrue);
      for (final e in _allEdges(wf)) {
        expect(wf.containsKey(e[0]), isTrue, reason: 'dangling edge $e');
      }
      // LoRA rewires model/clip, depth rewires conditioning — both present.
      expect(_sampler(wf)['model'], ['__lora__', 0]);
      expect(_sampler(wf)['positive'], ['__cn_apply__', 0]);
    });

    test('prompt prefix and negatives still compose', () {
      final wf = repose(
        ComfyUIService()..setPreset(pony),
        userNegative: 'bad hands',
      );
      final encs = _byClass(wf, 'CLIPTextEncode').toList();
      final texts = encs.map((n) => n['inputs']['text'] as String).toList();
      expect(
        texts.any((t) => t.startsWith(pony.positivePrefix) &&
            t.endsWith('a knight in armor')),
        isTrue,
      );
      expect(
        texts.any((t) => t.contains(pony.negativePrompt) &&
            t.endsWith('bad hands')),
        isTrue,
      );
    });

    test('without a depth reference txt2img stays plain', () {
      final svc = ComfyUIService()..setPreset(pony);
      final wf = svc.prepareForTest(
        _txt2img(),
        prompt: 'x',
        batch: 1,
        seed: 1,
        latentSize: (w: 1216, h: 832),
      );
      expect(_byClass(wf, 'ControlNetApplyAdvanced'), isEmpty);
      // The latent override is independent of the depth injection.
      expect(_byClass(wf, 'EmptyLatentImage').single['inputs']['width'], 1216);
    });

    test('service refuses repose on a dedicated (non-SDXL) preset', () async {
      final svc = ComfyUIService()
        ..setPreset(imageModelById('flux-manga').preset!);
      final events = await svc
          .repose(image: Uint8List(0), prompt: 'x', n: 1, seed: 1)
          .toList();
      expect(events.single, isA<GenFailed>());
    });
  });
}
