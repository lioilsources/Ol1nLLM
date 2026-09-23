import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/models/style_preset.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

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

  group('style candidates', () {
    test('the real candidates file parses, extra keys and all', () {
      final raw = jsonDecode(
        File('tools/lab/candidates/artists.json').readAsStringSync(),
      ) as List<dynamic>;
      final styles = parseStyleCandidates(raw);
      expect(styles.length, raw.length);
      final vg = styles.firstWhere((s) => s.id == 'vangogh-arles');
      expect(vg.artist, 'Vincent van Gogh');
      expect(vg.block, contains('impasto'));
    });

    test('tags ride along, and the sweep can override the model dialect', () {
      final c = parseStyleCandidates([
        {
          'id': 'x',
          'block': 'thick impasto brushstrokes',
          'booru': 'impasto, oil painting (medium)',
        },
      ]);
      expect(c.single.blockFor(PromptDialect.booru),
          'impasto, oil painting (medium)');
      expect(styleDialectFor(null, PromptDialect.booru), PromptDialect.booru);
      expect(styleDialectFor('natural', PromptDialect.booru),
          PromptDialect.natural);
      // A typo must not silently fall back to the model's own dialect.
      expect(() => styleDialectFor('t5', PromptDialect.natural),
          throwsFormatException);
    });

    test('style position and quality prefix: default is the app, the rest is exact', () {
      const style = StylePreset(id: 'u', label: 'u', block: 'ukiyo-e, flat color');
      String sent(StylePosition pos, bool prefixOn) {
        final c = composeCellPrompt(
          subject: 'a dancer',
          styleText: style.block,
          prefix: 'masterpiece, best quality',
          position: pos,
          qualityPrefix: prefixOn,
        );
        // What _prepare then writes: the prefix only where the builder adds it.
        return c.builderPrefix ? 'masterpiece, best quality, ${c.prompt}' : c.prompt;
      }

      expect(sent(StylePosition.end, true),
          'masterpiece, best quality, ${applyStylePreset('a dancer', style)}');
      expect(sent(StylePosition.front, true),
          'masterpiece, best quality, ukiyo-e, flat color, a dancer');
      expect(sent(StylePosition.first, true),
          'ukiyo-e, flat color, masterpiece, best quality, a dancer');
      expect(sent(StylePosition.end, false), 'a dancer, ukiyo-e, flat color');
      expect(sent(StylePosition.first, false), 'ukiyo-e, flat color, a dancer');

      // A baseline has no style to move; an empty subject stays empty.
      final base = composeCellPrompt(subject: 'a dancer', styleText: null,
          prefix: 'p', position: StylePosition.first, qualityPrefix: false);
      expect((base.prompt, base.builderPrefix), ('a dancer', false));
      expect(composeCellPrompt(subject: ' ', styleText: 'x', prefix: 'p').prompt, ' ');

      expect(stylePositionFor(null), StylePosition.end);
      expect(qualityPrefixFor(null), isTrue);
      expect(qualityPrefixFor('off'), isFalse);
      expect(() => stylePositionFor('start'), throwsFormatException);
      expect(() => qualityPrefixFor('no'), throwsFormatException);
    });

    test('the builder drops the preset prefix only when asked', () {
      final spec = imageModelById('noobai-xl');
      final svc = ComfyUIService()..setPreset(spec.preset!);
      final template = jsonDecode(File('assets/comfyui/sdxl_txt2img.api.json')
          .readAsStringSync()) as Map<String, dynamic>;
      String positive(bool prefix) => jsonEncode(svc.prepareForTest(template,
          prompt: 'a dancer', batch: 1, seed: 1, positivePrefix: prefix));
      expect(positive(true), contains('${spec.preset!.positivePrefix}, a dancer'));
      expect(positive(false), isNot(contains(spec.preset!.positivePrefix)));
      expect(positive(false), contains('a dancer'));
    });

    test('a candidate without id or text is rejected', () {
      expect(() => parseStyleCandidates(['x']), throwsFormatException);
      expect(
        () => parseStyleCandidates([
          {'label': 'bez id', 'block': 'flat colour'},
        ]),
        throwsFormatException,
      );
      expect(
        () => parseStyleCandidates([
          {'id': 'x', 'block': '  '},
        ]),
        throwsFormatException,
      );
    });

    test('no selection renders the whole pool', () {
      final c = parseStyleCandidates([
        {'id': 'a', 'block': 'flat colour'},
        {'id': 'b', 'block': 'thick impasto'},
      ]);
      expect(
        selectStyles(candidates: c, registry: kStylePresets, wanted: const [])
            .map((s) => s.id),
        ['a', 'b'],
      );
      expect(
        selectStyles(candidates: null, registry: kStylePresets, wanted: const [])
            .length,
        kStylePresets.length,
      );
    });

    test('an id the file lacks comes from the registry', () {
      // The duplicate check needs the old style next to the candidate, under
      // the same seed and reference — i.e. in the same run.
      final c = parseStyleCandidates([
        {'id': 'monet', 'block': 'plein air figure with parasol'},
      ]);
      final picked = selectStyles(
        candidates: c,
        registry: kStylePresets,
        wanted: const ['impressionist', 'monet'],
      );
      expect(picked.map((s) => s.id), ['monet', 'impressionist']);
      expect(picked.last.block, styleById('impressionist')!.block);
    });

    test('an id found nowhere fails before the GPU', () {
      expect(
        () => selectStyles(
          candidates: null,
          registry: kStylePresets,
          wanted: const ['ukiyoe', 'ukyioe'],
        ),
        throwsFormatException,
      );
    });
  });

  group('prompt bodies', () {
    List<PromptBody> two() => parsePromptBodies([
          {
            'id': 'portrait',
            'texts': {
              'danbooru': '1girl, solo',
              'juggernaut': 'a portrait of a young woman',
              'flux': 'A portrait photograph of a young woman.',
            },
          },
          {
            'id': 'street',
            'texts': {
              'danbooru': '1boy, city, night',
              'juggernaut': 'a man on a city street at night',
              'flux': 'A photograph of a man on a city street at night.',
            },
          },
        ]);

    test('the registry splits into exactly the three families', () {
      // Independent cross-check of the derivation: it reads the preset and the
      // backend, this reads the name. A new model that lands in the wrong
      // bucket — a FLUX one with a checkpoint, or an SDXL one without — shows
      // up here rather than as a run measuring the wrong sentence.
      for (final m in kImageModels) {
        final family = promptFamilyFor(m);
        expect(family == PromptFamily.flux, m.id.startsWith('flux-'),
            reason: '${m.id} → ${family.name}');
        if (m.promptDialect == PromptDialect.booru) {
          expect(family, PromptFamily.danbooru, reason: m.id);
        }
      }
      // The three the user picks between, spelled out.
      expect(promptFamilyFor(imageModelById('pony')), PromptFamily.danbooru);
      expect(promptFamilyFor(imageModelById('illustrious-xl')),
          PromptFamily.danbooru);
      expect(promptFamilyFor(imageModelById('animagine-xl')),
          PromptFamily.danbooru);
      expect(promptFamilyFor(imageModelById('juggernaut-xl')),
          PromptFamily.juggernaut);
      expect(promptFamilyFor(imageModelById('cyberrealistic-xl')),
          PromptFamily.juggernaut);
      expect(promptFamilyFor(imageModelById('sd15')), PromptFamily.juggernaut);
      expect(promptFamilyFor(imageModelById('flux-manga')), PromptFamily.flux);
      expect(promptFamilyFor(imageModelById('flux-schnell')), PromptFamily.flux);
    });

    test('a model reads its own text, and a missing one is never borrowed', () {
      final body = two().first;
      expect(body.textFor(PromptFamily.danbooru), '1girl, solo');
      expect(body.textFor(PromptFamily.flux),
          'A portrait photograph of a young woman.');

      final fluxOnly = parsePromptBodies([
        {
          'id': 'p1',
          'texts': {'flux': 'A photograph.'},
        },
      ]).single;
      // Falling back on a neighbour would hand a tag-reading checkpoint a
      // sentence and return a picture that looks like a measurement of it.
      expect(() => fluxOnly.textFor(PromptFamily.danbooru),
          throwsFormatException);
    });

    test('the axis is prefixes × bodies, in that order', () {
      final axis = buildPromptAxis(
        prefixes: const ['masterpiece', 'low angle'],
        bodies: two(),
      );
      expect(axis.map((e) => e.label), [
        'masterpiece · portrait',
        'masterpiece · street',
        'low angle · portrait',
        'low angle · street',
      ]);
      expect(axis.first.subjectFor(PromptFamily.danbooru),
          'masterpiece, 1girl, solo');
      expect(axis.last.subjectFor(PromptFamily.juggernaut),
          'low angle, a man on a city street at night');
    });

    test('an empty box is one empty prefix; no file leaves the box alone', () {
      final fromFile = buildPromptAxis(prefixes: const [], bodies: two());
      expect(fromFile.length, 2);
      expect(fromFile.first.label, 'portrait');
      expect(fromFile.first.subjectFor(PromptFamily.flux),
          'A portrait photograph of a young woman.');

      final plain = buildPromptAxis(
          prefixes: const ['a dancer'], bodies: const []);
      expect(plain.single.label, 'a dancer');
      // Without a body the family cannot change what is sent.
      for (final f in PromptFamily.values) {
        expect(plain.single.subjectFor(f), 'a dancer');
      }
    });

    test('a body that would render as something else is rejected', () {
      expect(() => parsePromptBodies(['x']), throwsFormatException);
      expect(
        () => parsePromptBodies([
          {
            'texts': {'flux': 'a'},
          },
        ]),
        throwsFormatException,
      );
      // A typo in a family name would silently drop the text.
      expect(
        () => parsePromptBodies([
          {
            'id': 'x',
            'texts': {'pony': 'a'},
          },
        ]),
        throwsFormatException,
      );
      expect(
        () => parsePromptBodies([
          {
            'id': 'x',
            'texts': {'flux': '  '},
          },
        ]),
        throwsFormatException,
      );
      expect(
        () => parsePromptBodies([
          {'id': 'x', 'texts': <String, String>{}},
        ]),
        throwsFormatException,
      );
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
      '__depth_fit__',
      '__depth_cn__',
      '__depth_type__',
      '__pose_image__',
      '__pose_cn__',
      '__lora__',
      '__face_id__',
      '__face_cn__',
      '__face_analysis__',
      '__face_apply__',
      '__face_pulid__',
      '__face_eva__',
      '__faceid_loader__',
      '__faceid_apply__',
      '__detail_bbox__',
      '__face_detail__',
    ]) {
      expect(src, contains("'$id'"), reason: '$id zmizel ze služby');
    }
  });
}
