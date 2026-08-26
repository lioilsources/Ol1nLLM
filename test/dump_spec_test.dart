import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/lab/dump_spec.dart';

Map<String, dynamic> _graph() => {
      '1': {
        'class_type': 'CheckpointLoaderSimple',
        'inputs': {'ckpt_name': 'x.safetensors'},
      },
      '5': {
        'class_type': 'KSampler',
        'inputs': {'steps': 30, 'cfg': 6.0, 'denoise': 1.0},
      },
      '6': {
        'class_type': 'KSampler',
        'inputs': {'steps': 20, 'cfg': 5.0, 'denoise': 0.45},
      },
      '__cn_apply__': {
        'class_type': 'ControlNetApplyAdvanced',
        'inputs': {'strength': 0.75, 'end_percent': 0.9},
      },
      '__lora__': {
        'class_type': 'LoraLoader',
        'inputs': {'strength_model': 0.9, 'strength_clip': 0.9},
      },
    };

void main() {
  group('parseOverride', () {
    test('targets a node class, a node id, a synthetic node, a param', () {
      expect(parseOverride('KSampler.cfg=6').target.kind,
          OverrideKind.nodeClass);
      expect(parseOverride('#5.steps=20').target.kind, OverrideKind.nodeId);
      expect(parseOverride('#5.steps=20').target.scope, '5');
      expect(parseOverride('__cn_apply__.strength=0.5').target.kind,
          OverrideKind.syntheticNode);
      expect(parseOverride('param.editDenoise=0.9').target.kind,
          OverrideKind.param);
    });

    test('? marks a target that may match nothing', () {
      expect(parseOverride('?KSampler.cfg=6').target.optional, isTrue);
      expect(parseOverride('KSampler.cfg=6').target.optional, isFalse);
    });

    test('values keep their type; quotes force a string', () {
      expect(coerce('6'), 6);
      expect(coerce('0.5'), 0.5);
      expect(coerce('true'), true);
      expect(coerce('karras'), 'karras');
      expect(coerce('"6"'), '6');
    });

    test('malformed entries are rejected loudly', () {
      expect(() => parseOverride('KSampler.cfg'), throwsFormatException);
      expect(() => parseOverride('cfg=6'), throwsFormatException);
      expect(() => parseOverride('param.=6'), throwsFormatException);
    });
  });

  group('applyOverrides', () {
    test('a class target hits every node of that class', () {
      final wf = _graph();
      final applied = applyOverrides(wf, [parseOverride('KSampler.cfg=7')]);
      expect(wf['5']['inputs']['cfg'], 7);
      expect(wf['6']['inputs']['cfg'], 7);
      expect(applied['KSampler.cfg'], ['5', '6']);
    });

    test('a node id hits only that node', () {
      final wf = _graph();
      applyOverrides(wf, [parseOverride('#5.steps=12')]);
      expect(wf['5']['inputs']['steps'], 12);
      expect(wf['6']['inputs']['steps'], 20);
    });

    test('a synthetic target does not leak into the LoRA node', () {
      // The old OVERRIDE wrote into *any* input with a matching key; strength
      // lives on the ControlNet apply, strength_model on the LoRA.
      final wf = _graph();
      applyOverrides(wf, [parseOverride('__cn_apply__.strength=0.5')]);
      expect(wf['__cn_apply__']['inputs']['strength'], 0.5);
      expect(wf['__lora__']['inputs']['strength_model'], 0.9);
    });

    test('a target that matches nothing is a hard error', () {
      expect(
        () => applyOverrides(_graph(), [parseOverride('SamplerCustom.cfg=6')]),
        throwsA(isA<StateError>()),
      );
      expect(
        () => applyOverrides(_graph(), [parseOverride('KSampler.nonsense=1')]),
        throwsA(isA<StateError>()),
      );
    });

    test('? tolerates zero matches', () {
      expect(
        applyOverrides(_graph(), [parseOverride('?SamplerCustom.cfg=6')]),
        isEmpty,
      );
    });

    test('param targets are left for the builder, not written into the graph',
        () {
      final wf = _graph();
      final applied =
          applyOverrides(wf, [parseOverride('param.editDenoise=0.9')]);
      expect(applied, isEmpty);
      expect(wf['5']['inputs']['denoise'], 1.0);
    });
  });

  group('sweeps and cell ids', () {
    test('expands values and derives a label from the target', () {
      final s = parseSweep('__cn_apply__.strength=0.5|0.75|1.0', null);
      expect(s.values, ['0.5', '0.75', '1.0']);
      expect(s.label, 'strength');
      expect(parseSweep('param.editDenoise=0.5|0.9', null).label, 'editDenoise');
      expect(parseSweep('KSampler.cfg=5|6', 'cfgtest').label, 'cfgtest');
    });

    test('no sweep is empty, not null', () {
      expect(parseSweep(null, null).isEmpty, isTrue);
      expect(parseSweep('  ', null).isEmpty, isTrue);
    });

    test('values stay literal — no float artefacts in names', () {
      expect(sanitizeValue('0.3'), '0p3');
      expect(sanitizeValue('dpmpp_2m'), 'dpmpp_2m');
      expect(sanitizeValue('832x1216'), '832x1216');
      // A LoRA sweep sweeps filenames; the extension is noise in every id.
      expect(sanitizeValue('style-usnr-thin-paint.safetensors'),
          'style-usnr-thin-paint');
      expect(sanitizeValue('avatar/testface.safetensors'), 'avatar_testface');
    });

    test('cell id keeps the __ separators parseable', () {
      expect(
        cellId(flow: 'repose', model: 'pony', style: 'ukiyoe'),
        'repose__pony__ukiyoe',
      );
      expect(
        cellId(
            flow: 'img2img',
            model: 'juggernaut-xl',
            style: '__baseline',
            promptIndex: 3),
        'img2img__juggernaut-xl____baseline__p03',
      );
      expect(
        cellId(
            flow: 'repose',
            model: 'pony',
            style: 'ukiyoe',
            variantLabel: 'strength',
            variantValue: '0.5'),
        'repose@strength-0p5__pony__ukiyoe',
      );
    });

    test('the flow segment survives a split on __', () {
      final id = cellId(
          flow: 'img2img',
          model: 'juggernaut-xl',
          style: '__baseline',
          promptIndex: 0);
      final parts = id.split('__');
      expect(parts.first, 'img2img');
      expect(parts[1], 'juggernaut-xl');
    });
  });

  test('the real ControlNet apply node is reachable by its synthetic id', () {
    // Guards the naming contract between _prepare and the lab: if the app ever
    // renames __cn_apply__, every strength sweep silently stops matching.
    final src = File('lib/services/comfyui_service.dart').readAsStringSync();
    for (final id in const [
      '__cn_apply__',
      '__depth_pre__',
      '__depth_src__',
      '__depth_cn__',
      '__depth_type__',
      '__pose_image__',
      '__pose_cn__',
      '__lora__',
    ]) {
      expect(src, contains("'$id'"), reason: '$id zmizel ze služby');
    }
  });
}
