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

Map<String, dynamic> _fluxTxt2img() => jsonDecode(
  File(imageModelById('flux-manga').preset!.txt2imgAsset).readAsStringSync(),
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

    test('service refuses repose on a preset with no txt2img graph', () async {
      // flux-fill's txt2img field points at the inpaint workflow because the
      // type demands a value — there is nothing to render from a prompt.
      final svc = ComfyUIService()
        ..setPreset(imageModelById('flux-fill').preset!);
      final events = await svc
          .repose(image: Uint8List(0), prompt: 'x', n: 1, seed: 1)
          .toList();
      expect(events.single, isA<GenFailed>());
    });
  });

  group('repose on flux-manga', () {
    final flux = imageModelById('flux-manga').preset!;

    Map<String, dynamic> repose(ComfyUIService svc) => svc.prepareForTest(
      _fluxTxt2img(),
      prompt: 'a knight in armor',
      batch: 1,
      seed: 7,
      depthImageName: 'ref.png',
      latentSize: (w: 832, h: 1216),
    );

    test('uses the InstantX depth net, no union type node, with a VAE edge', () {
      final wf = repose(ComfyUIService()..setPreset(flux));
      expect(
        _byClass(wf, 'ControlNetLoader').single['inputs']['control_net_name'],
        'flux-depth-controlnet-v3.safetensors',
      );
      expect(_byClass(wf, 'SetUnionControlNetType'), isEmpty);
      final apply = _byClass(wf, 'ControlNetApplyAdvanced').single;
      expect(apply['inputs']['control_net'], ['__depth_cn__', 0]);
      // The InstantX net encodes its hint through the VAE — the same edge
      // VAEDecode already uses, so it works for a VAELoader or a checkpoint.
      expect(apply['inputs']['vae'], _byClass(wf, 'VAEDecode').single['inputs']['vae']);
      // Its own starting strength: xinsir's 0.75 over-pins here.
      expect(apply['inputs']['strength'], 0.55);
      expect(_sampler(wf)['positive'], ['__cn_apply__', 0]);
    });

    test('the reference bucket reaches a dedicated template too', () {
      // Without this the flux latent stays at the asset's 1:1 while the depth
      // hint is 2:3, and the ControlNet squashes it.
      final wf = repose(ComfyUIService()..setPreset(flux));
      final latent = _byClass(wf, 'EmptySD3LatentImage').single['inputs'];
      expect(latent['width'], 832);
      expect(latent['height'], 1216);
    });

    test('the preset values stay baked in', () {
      final wf = repose(ComfyUIService()..setPreset(flux));
      expect(_sampler(wf)['cfg'], 1.0);
      expect(_sampler(wf)['steps'], 20);
    });

    test('service accepts repose on flux-manga', () async {
      // Not a GenFailed on the guard — it gets as far as uploading, which
      // without credentials throws rather than yielding a refusal.
      final svc = ComfyUIService()..setPreset(flux);
      await expectLater(
        svc.repose(image: Uint8List(0), prompt: 'x', n: 1, seed: 1).toList(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('face identity: the reference keeps its face, not just its pose', () {
    Map<String, dynamic> repose(
      ComfyUIService svc, {
      required FaceIdentity face,
      bool detail = false,
      bool flux = false,
    }) => svc.prepareForTest(
      flux ? _fluxTxt2img() : _txt2img(),
      prompt: 'a knight in armor',
      batch: 1,
      seed: 7,
      depthImageName: 'ref.png',
      latentSize: (w: 832, h: 1216),
      faceIdentity: face,
      faceDetail: detail,
    );

    ComfyUIService sdxlSvc() => ComfyUIService()..setPreset(pony);
    ComfyUIService fluxSvc() =>
        ComfyUIService()..setPreset(imageModelById('flux-manga').preset!);

    test('off by default and for none — repose stays as shipped', () {
      for (final wf in [
        repose(sdxlSvc(), face: FaceIdentity.none),
        sdxlSvc().prepareForTest(_txt2img(), prompt: 'x', batch: 1, seed: 1,
            depthImageName: 'ref.png'),
      ]) {
        expect(_byClass(wf, 'ApplyInstantID'), isEmpty);
        expect(_byClass(wf, 'IPAdapterFaceID'), isEmpty);
        expect(_byClass(wf, 'ApplyPulidFlux'), isEmpty);
        expect(_byClass(wf, 'FaceDetailer'), isEmpty);
      }
    });

    test('SDXL/instantid: four nodes, reading the depth reference', () {
      final wf = repose(sdxlSvc(), face: FaceIdentity.instantid);
      for (final id in const [
        '__face_id__', '__face_analysis__', '__face_cn__', '__face_apply__',
      ]) {
        expect(wf.containsKey(id), isTrue, reason: '$id chybí');
      }
      final apply = wf['__face_apply__'] as Map;
      expect(apply['class_type'], 'ApplyInstantID');
      // The same LoadImage the depth map comes from — one upload, and no way
      // for the two to disagree about which photo they mean.
      expect(apply['inputs']['image'], ['__depth_src__', 0]);
      expect(apply['inputs']['instantid'], ['__face_id__', 0]);
      expect(apply['inputs']['insightface'], ['__face_analysis__', 0]);
      expect(apply['inputs']['control_net'], ['__face_cn__', 0]);
      expect(apply['inputs']['weight'], 0.8);
      // Identity holds to the end; the depth hint is the one released at 90 %.
      expect(apply['inputs']['end_at'], 1.0);
      expect(
        (wf['__face_cn__'] as Map)['inputs']['control_net_name'],
        contains('instantid'),
      );
    });

    test('InstantID sits upstream of the depth apply, on both edges', () {
      final wf = repose(sdxlSvc(), face: FaceIdentity.instantid);
      final cn = (wf['__cn_apply__'] as Map)['inputs'] as Map;
      expect(cn['positive'], ['__face_apply__', 1]);
      expect(cn['negative'], ['__face_apply__', 2]);
      // …and the two ControlNets stack rather than replace each other.
      expect(_sampler(wf)['positive'], ['__cn_apply__', 0]);
      expect(_sampler(wf)['model'], ['__face_apply__', 0]);
      final face = (wf['__face_apply__'] as Map)['inputs'] as Map;
      expect(face['positive'], ['2', 0]);
      expect(face['negative'], ['3', 0]);
    });

    test('SDXL/faceid: model edge only, no conditioning touched', () {
      final wf = repose(sdxlSvc(), face: FaceIdentity.faceid);
      expect(_byClass(wf, 'ApplyInstantID'), isEmpty);
      final loader = (wf['__faceid_loader__'] as Map)['inputs'] as Map;
      expect(loader['preset'], 'FACEID PLUS V2');
      expect(loader['model'], ['1', 0]);
      final apply = (wf['__faceid_apply__'] as Map)['inputs'] as Map;
      expect(apply['model'], ['__faceid_loader__', 0]);
      expect(apply['ipadapter'], ['__faceid_loader__', 1]);
      expect(apply['image'], ['__depth_src__', 0]);
      expect(_sampler(wf)['model'], ['__faceid_apply__', 0]);
      // Conditioning still comes straight from the encoders via the depth CN.
      final cn = (wf['__cn_apply__'] as Map)['inputs'] as Map;
      expect(cn['positive'], ['2', 0]);
    });

    test('both: FaceID first, InstantID last on the model edge', () {
      final wf = repose(sdxlSvc(), face: FaceIdentity.both);
      expect((wf['__faceid_loader__'] as Map)['inputs']['model'], ['1', 0]);
      expect((wf['__face_apply__'] as Map)['inputs']['model'],
          ['__faceid_apply__', 0]);
      expect(_sampler(wf)['model'], ['__face_apply__', 0]);
    });

    test('composes with a LoRA, which stays first in the chain', () {
      final wf = repose(
        sdxlSvc()..setLora('style-anime-screencap.safetensors'),
        face: FaceIdentity.both,
        detail: true,
      );
      expect((wf['__faceid_loader__'] as Map)['inputs']['model'],
          ['__lora__', 0]);
      for (final e in _allEdges(wf)) {
        expect(wf.containsKey(e[0]), isTrue, reason: 'dangling edge $e');
      }
    });

    test('FLUX maps every mode onto PuLID', () {
      for (final mode in const [
        FaceIdentity.instantid, FaceIdentity.faceid, FaceIdentity.both,
      ]) {
        final wf = repose(fluxSvc(), face: mode, flux: true);
        expect(_byClass(wf, 'ApplyInstantID'), isEmpty, reason: mode.name);
        expect(_byClass(wf, 'IPAdapterFaceID'), isEmpty, reason: mode.name);
        final apply = (wf['__face_apply__'] as Map);
        expect(apply['class_type'], 'ApplyPulidFlux');
        expect(apply['inputs']['image'], ['__depth_src__', 0]);
        expect(apply['inputs']['weight'], 0.9);
        expect(apply['inputs']['pulid_flux'], ['__face_pulid__', 0]);
        expect(apply['inputs']['eva_clip'], ['__face_eva__', 0]);
        expect(apply['inputs']['face_analysis'], ['__face_analysis__', 0]);
        expect(_sampler(wf)['model'], ['__face_apply__', 0]);
        // PuLID produces no conditioning, so the depth apply keeps its edges.
        expect((wf['__cn_apply__'] as Map)['inputs']['positive'], ['16', 0]);
        for (final e in _allEdges(wf)) {
          expect(wf.containsKey(e[0]), isTrue, reason: 'dangling edge $e');
        }
      }
    });

    test('no reference to read a face from ⇒ no identity nodes', () {
      // A template skeleton is a pose, not a photo: there is no face in it,
      // and this is also what keeps ['__depth_src__', 0] from dangling.
      final wf = sdxlSvc().prepareForTest(
        _txt2img(),
        prompt: 'x',
        batch: 1,
        seed: 1,
        poseImageName: 'skeleton.png',
        faceIdentity: FaceIdentity.both,
        faceDetail: true,
      );
      expect(_byClass(wf, 'ApplyInstantID'), isEmpty);
      expect(_byClass(wf, 'IPAdapterFaceID'), isEmpty);
      expect(_byClass(wf, 'FaceDetailer'), isEmpty);
      for (final e in _allEdges(wf)) {
        expect(wf.containsKey(e[0]), isTrue, reason: 'dangling edge $e');
      }
    });

    test('detailer: appended before SaveImage, on pre-depth conditioning', () {
      final wf = repose(sdxlSvc(), face: FaceIdentity.instantid, detail: true);
      final save = _byClass(wf, 'SaveImage').single['inputs'] as Map;
      expect(save['images'], ['__face_detail__', 0]);
      final d = (wf['__face_detail__'] as Map)['inputs'] as Map;
      // It consumes what SaveImage used to: the decoded image.
      expect(d['image'], ['6', 0]);
      expect(d['model'], ['__face_apply__', 0]);
      expect(d['bbox_detector'], ['__detail_bbox__', 0]);
      // Pre-depth: a full-frame depth map resized onto a face crop describes
      // something else entirely.
      expect(d['positive'], ['__face_apply__', 1]);
      expect(d['negative'], ['__face_apply__', 2]);
      expect(d['denoise'], 0.4);
      // Same sampler as the main pass, seed included — a face repaired with a
      // different sampler reads as a graft.
      expect(d['steps'], pony.steps);
      expect(d['cfg'], pony.cfg);
      expect(d['sampler_name'], pony.samplerName);
      expect(d['seed'], 7);
      // No SAM model is installed, so the optional hook stays unwired.
      expect(d.containsKey('sam_model_opt'), isFalse);
    });

    test('detailer needs an identity to hold onto', () {
      final wf = repose(sdxlSvc(), face: FaceIdentity.none, detail: true);
      expect(_byClass(wf, 'FaceDetailer'), isEmpty);
      expect(_byClass(wf, 'SaveImage').single['inputs']['images'], ['6', 0]);
    });

    test('detailer on FLUX follows that graph\'s own sampler settings', () {
      final wf = repose(fluxSvc(), face: FaceIdentity.instantid, detail: true,
          flux: true);
      final d = (wf['__face_detail__'] as Map)['inputs'] as Map;
      expect(d['cfg'], 1.0);
      expect(d['steps'], 20);
      expect(d['clip'], ['11', 0]);
      expect(d['vae'], ['12', 0]);
      // PuLID leaves the conditioning alone, so the pre-depth edges are the
      // template's own.
      expect(d['positive'], ['16', 0]);
      expect(_byClass(wf, 'SaveImage').single['inputs']['images'],
          ['__face_detail__', 0]);
    });

    test('FaceIdentity.parse tolerates junk from the lab', () {
      expect(FaceIdentity.parse('instantid'), FaceIdentity.instantid);
      expect(FaceIdentity.parse('both'), FaceIdentity.both);
      expect(FaceIdentity.parse(null), FaceIdentity.none);
      expect(FaceIdentity.parse('typo'), FaceIdentity.none);
    });
  });
}
