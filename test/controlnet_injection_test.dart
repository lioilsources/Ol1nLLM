import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

/// Verifies ControlNet injection precedence in img2img:
///   • a picked template pose (OpenPose skeleton) overrides everything
///   • otherwise the source photo's structure is carried over via a depth map
///   • txt2img / no-source never gets the depth path
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
}
