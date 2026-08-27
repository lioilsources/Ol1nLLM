// Emits the exact ComfyUI workflows the app would send, plus a manifest that
// describes every cell. Driven entirely by env vars so the lab (or a shell)
// can configure it without a second copy of the app's logic living here.
//
//   flutter test tools/lab/dump.dart
//
// Everything that decides *what* a graph looks like comes from the app:
// ComfyUIService.prepareForTest → _prepare, kImageModels, kStylePresets,
// kPoseTemplates, reposeLatentFor. This file only chooses which combinations
// to ask for, and applies the lab's sweep/override on top.
// prepareForTest is @visibleForTesting and this file *is* run by
// `flutter test` — the analyzer just keys off the path, not the runner.
// Using it is the whole point: the lab must build graphs with the app's own
// code, otherwise it measures a copy that drifts.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/models/latent_bucket.dart';
import 'package:ol1n_llm/models/pose_template.dart';
import 'package:ol1n_llm/models/style_preset.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

import 'dump_spec.dart';

Map<String, dynamic> _load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<String> _csv(String? v) => (v == null || v.trim().isEmpty)
    ? const []
    : v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

bool _flag(String? v) => v == '1' || v == 'true';

void main() {
  test('dump matrix workflows', () {
    final env = Platform.environment;
    final out = Directory(env['OUT_DIR']!)..createSync(recursive: true);
    final seed = int.parse(env['SEED'] ?? '777');
    final batch = int.parse(env['BATCH'] ?? '1');
    final limit = int.tryParse(env['LIMIT'] ?? '');
    final refName = env['REF_NAME'];
    final refFile = env['REF_FILE'];
    final negative = env['NEGATIVE'];
    final poseMode = env['POSE_MODE'] ?? 'none';
    final poseName = env['POSE_NAME'];
    final sourceDepth = env['SOURCE_DEPTH'] ?? 'auto';
    // Identity/detail travel as names, not booleans: the sweep axis
    // `param.faceIdentity` needs to say *which* mechanism, and the effective
    // one is read back out of the graph afterwards anyway.
    final faceIdentity = env['FACE_IDENTITY'] ?? 'none';
    final faceDetail = _flag(env['FACE_DETAIL']);
    final lora = (env['LORA'] ?? '').isEmpty ? null : env['LORA'];
    final loraStrength =
        double.tryParse(env['LORA_STRENGTH'] ?? '') ?? kDefaultLoraStrength;
    // The server's LoRA list, so the manifest can classify every file the
    // picker will offer. Families live in the app (lora_family.dart) — the
    // lab must not grow a second opinion about lineage.
    final serverLoras = env['LORAS'] == null
        ? const <String>[]
        : File(env['LORAS']!)
            .readAsLinesSync()
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
    final flows = _csv(env['FLOWS']).isEmpty
        ? const ['repose', 'img2img']
        : _csv(env['FLOWS']);

    // Prompts: a file wins over the single SUBJECT, and its index becomes part
    // of the cell id so two prompts never collide.
    final prompts = env['PROMPTS_FILE'] != null
        ? File(env['PROMPTS_FILE']!)
            .readAsLinesSync()
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList()
        : [env['SUBJECT']!];
    final indexPrompts = prompts.length > 1;

    // Styles: the app registry, unless the caller vets candidates from a file.
    final wantedStyles = _csv(env['STYLES']);
    final styles = env['STYLES_FILE'] != null
        ? (jsonDecode(File(env['STYLES_FILE']!).readAsStringSync()) as List)
            .cast<Map<String, dynamic>>()
            .map((m) => StylePreset(
                  id: m['id'] as String,
                  label: (m['label'] ?? m['id']) as String,
                  block: m['block'] as String,
                ))
            .where((s) => wantedStyles.isEmpty || wantedStyles.contains(s.id))
            .toList()
        : kStylePresets
            .where((s) => wantedStyles.isEmpty || wantedStyles.contains(s.id))
            .toList();

    final installed = env['CKPTS'] == null
        ? const <String>[]
        : File(env['CKPTS']!)
            .readAsLinesSync()
            .where((l) => l.trim().isNotEmpty)
            .toList();
    final wantedModels = _csv(env['MODELS']);
    final models = imageModelsFor(installed)
        .where((m) => m.kind == ImageBackendKind.comfyUi && m.preset != null)
        .where((m) => wantedModels.isEmpty || wantedModels.contains(m.id))
        .toList();

    final overrides = _csv(env['OVERRIDE_AT']).map(parseOverride).toList();
    final sweep = parseSweep(env['SWEEP'], env['SWEEP_LABEL']);
    final latentEnv = env['LATENT'];

    final cells = <Map<String, dynamic>>[];
    final skipped = <Map<String, String>>[];
    var n = 0;

    for (final m in models) {
      final preset = m.preset!;
      final generic = preset.ckptName != null;
      // Mirrors ComfyUIService._reposeSupported: the generic SDXL templates
      // (union CN, so supportsPose too — sd15 has no ControlNet) or
      // flux-manga, the one dedicated template with a depth CN of its own.
      // Auto-depth follows supportsPose unless the caller forces it.
      final canRepose = (generic && m.supportsPose) ||
          preset.txt2imgAsset == kFluxMangaTxt2img;
      final autoDepth = sourceDepth == 'on' ||
          (sourceDepth == 'auto' && m.supportsPose && generic);

      for (var pi = 0; pi < prompts.length; pi++) {
        for (final style in [null, ...styles]) {
          if (style == null && _flag(env['NO_BASELINE']) && styles.isNotEmpty) {
            continue;
          }
          final styleId = style?.id ?? '__baseline';
          final prompt = applyStylePreset(prompts[pi], style);

          for (final flow in flows) {
            void emit(String? variantValue) {
              if (limit != null && n >= limit) return;

              // A pose template is only legal where the OpenPose ControlNet is
              // (SDXL); depth wins over it inside _prepare anyway.
              String? poseImage;
              if (poseMode == 'template') {
                if (!m.supportsPose || !generic) {
                  skipped.add({
                    'cell': cellId(
                        flow: flow, model: m.id, style: styleId,
                        promptIndex: indexPrompts ? pi : null),
                    'reason': 'šablona pózy je SDXL-only (${m.id})',
                  });
                  return;
                }
                if (poseName == null) {
                  throw StateError('POSE_MODE=template vyžaduje POSE_NAME');
                }
                poseImage = poseName;
              }

              // Per-variant param overrides re-enter the builder; graph-level
              // ones are applied to the finished JSON afterwards.
              final params = <String, Object>{};
              for (final o in overrides) {
                if (o.target.kind == OverrideKind.param) {
                  params[o.target.scope] = o.value;
                }
              }
              var graphOverrides = overrides
                  .where((o) => o.target.kind != OverrideKind.param)
                  .toList();
              if (variantValue != null) {
                if (sweep.target.kind == OverrideKind.param) {
                  params[sweep.target.scope] = coerce(variantValue);
                } else {
                  graphOverrides = [
                    ...graphOverrides,
                    OverrideSpec(sweep.target, coerce(variantValue)),
                  ];
                }
              }

              double? editDenoise = env['EDIT_DENOISE'] == null
                  ? null
                  : double.parse(env['EDIT_DENOISE']!);
              if (params['editDenoise'] is num) {
                editDenoise = (params['editDenoise'] as num).toDouble();
              }
              var cellSeed = seed;
              if (params['seed'] is int) cellSeed = params['seed'] as int;

              // LoRA is sweepable (`param.lora`), so it is resolved per cell.
              var cellLora = lora;
              if (params['lora'] is String) {
                final v = params['lora'] as String;
                cellLora = (v.isEmpty || v == 'none') ? null : v;
              }
              var cellLoraStrength = loraStrength;
              if (params['loraStrength'] is num) {
                cellLoraStrength = (params['loraStrength'] as num).toDouble();
              }
              var cellFace = FaceIdentity.parse(faceIdentity);
              if (params['faceIdentity'] is String) {
                cellFace = FaceIdentity.parse(params['faceIdentity'] as String);
              }
              var cellFaceDetail = faceDetail;
              if (params['faceDetail'] is bool) {
                cellFaceDetail = params['faceDetail'] as bool;
              }
              if (cellLora != null &&
                  fitOfLora(cellLora, m.loraFamily) == LoraFit.incompatible) {
                skipped.add({
                  'cell': cellId(
                      flow: flow, model: m.id, style: styleId,
                      variantLabel: variantValue == null ? null : sweep.label,
                      variantValue: variantValue,
                      promptIndex: indexPrompts ? pi : null),
                  'reason': '$cellLora je ${loraFamilyLabel(familyOfLora(cellLora))} '
                      '— jiná architektura než ${m.id}, nešla by aplikovat',
                });
                return;
              }

              LatentSize? latent;
              if (latentEnv != null) {
                final parts = latentEnv.split('x');
                latent = (w: int.parse(parts[0]), h: int.parse(parts[1]));
              } else if (flow == 'repose' && refFile != null) {
                latent = reposeLatentFor(
                  File(refFile).readAsBytesSync(),
                  fallback: (w: preset.width, h: preset.height),
                );
              }

              final svc = ComfyUIService()..setPreset(preset);
              if (cellLora != null) {
                svc
                  ..setLora(cellLora)
                  ..setLoraStrength(cellLoraStrength);
              }
              Map<String, dynamic> wf;
              switch (flow) {
                case 'repose':
                  if (!canRepose || refName == null) {
                    skipped.add({
                      'cell': cellId(
                          flow: flow, model: m.id, style: styleId,
                          promptIndex: indexPrompts ? pi : null),
                      'reason': canRepose
                          ? 'chybí referenční obrázek'
                          : 'zachovej pózu je SDXL-only (${m.id})',
                    });
                    return;
                  }
                  wf = svc.prepareForTest(
                    _load(preset.txt2imgAsset),
                    prompt: prompt,
                    batch: batch,
                    seed: cellSeed,
                    depthImageName: refName,
                    latentSize: latent,
                    userNegative: negative,
                    faceIdentity: cellFace,
                    faceDetail: cellFaceDetail,
                  );
                case 'img2img':
                  if (refName == null) {
                    skipped.add({
                      'cell': cellId(
                          flow: flow, model: m.id, style: styleId,
                          promptIndex: indexPrompts ? pi : null),
                      'reason': 'chybí referenční obrázek',
                    });
                    return;
                  }
                  wf = svc.prepareForTest(
                    _load(preset.img2imgAsset),
                    prompt: prompt,
                    batch: batch,
                    seed: cellSeed,
                    imageName: refName,
                    poseImageName: poseImage,
                    sourceDepth: poseImage == null &&
                        poseMode != 'depth' &&
                        autoDepth,
                    depthImageName: poseMode == 'depth' ? refName : null,
                    userNegative: negative,
                    editDenoise: editDenoise,
                    faceIdentity: cellFace,
                    faceDetail: cellFaceDetail,
                  );
                case 'txt2img':
                  wf = svc.prepareForTest(
                    _load(preset.txt2imgAsset),
                    prompt: prompt,
                    batch: batch,
                    seed: cellSeed,
                    poseImageName: poseImage,
                    depthImageName:
                        poseMode == 'depth' ? refName : null,
                    latentSize: latent,
                    userNegative: negative,
                    faceIdentity: cellFace,
                    faceDetail: cellFaceDetail,
                  );
                default:
                  fail('neznámá flow: $flow');
              }

              // A sweep target can be structurally absent for a model rather
              // than mistyped — flux-manga has no ControlNet to aim at. Skip
              // that cell with the reason instead of killing the whole dump;
              // a genuine typo then shows up as *everything* skipped.
              Map<String, List<String>> applied;
              try {
                applied = applyOverrides(wf, graphOverrides);
              } on StateError catch (e) {
                skipped.add({
                  'cell': cellId(
                      flow: flow, model: m.id, style: styleId,
                      variantLabel: variantValue == null ? null : sweep.label,
                      variantValue: variantValue,
                      promptIndex: indexPrompts ? pi : null),
                  'reason': e.message,
                });
                return;
              }
              final id = cellId(
                flow: flow,
                model: m.id,
                style: styleId,
                variantLabel: variantValue == null ? null : sweep.label,
                variantValue: variantValue,
                promptIndex: indexPrompts ? pi : null,
              );
              File('${out.path}/$id.json').writeAsStringSync(jsonEncode(wf));
              cells.add({
                'id': id,
                'flow': flow,
                'model': m.id,
                'modelLabel': m.label,
                'style': styleId,
                'styleLabel': style?.label,
                'promptIndex': pi,
                // Read back out of the graph, so the table can never show a
                // prompt that differs from the one that was sent.
                'prompt': _encodedText(wf, positive: true),
                'negative': _encodedText(wf, positive: false),
                'variant': variantValue == null
                    ? null
                    : {'label': sweep.label, 'value': variantValue},
                'params': {
                  'seed': cellSeed,
                  'batch': batch,
                  'editDenoise': editDenoise,
                  'latent': latent == null ? null : '${latent.w}x${latent.h}',
                  'poseMode': poseMode,
                  'refName': refName,
                  'lora': cellLora,
                  'loraStrength': cellLora == null ? null : cellLoraStrength,
                  'sourceDepth': flow == 'img2img' && poseImage == null &&
                      poseMode != 'depth' &&
                      autoDepth,
                  // Read back out of the graph, like the prompt: asking for
                  // `faceid` on a FLUX model gets PuLID, and the table must
                  // say what ran, not what was requested.
                  'faceIdentity': _effectiveFaceIdentity(wf),
                  'faceDetail': wf.containsKey('__face_detail__'),
                },
                'applied': applied,
                'presetOverridden': graphOverrides.isNotEmpty,
              });
              n++;
            }

            if (sweep.isEmpty) {
              emit(null);
            } else {
              for (final v in sweep.values) {
                emit(v);
              }
            }
          }
        }
      }
    }

    if (_flag(env['MANIFEST'])) {
      File('${out.path}/manifest.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert({
          'cells': cells,
          'skipped': skipped,
          'models': [
            for (final m in models)
              {
                'id': m.id,
                'label': m.label,
                'supportsPose': m.supportsPose,
                'styleNote': m.styleNote,
                'ckptName': m.preset!.ckptName,
                'preset': {
                  'steps': m.preset!.steps,
                  'cfg': m.preset!.cfg,
                  'sampler': m.preset!.samplerName,
                  'scheduler': m.preset!.scheduler,
                  'width': m.preset!.width,
                  'height': m.preset!.height,
                  'img2imgDenoise': m.preset!.img2imgDenoise,
                  'positivePrefix': m.preset!.positivePrefix,
                  'negativePrompt': m.preset!.negativePrompt,
                },
              },
          ],
          'styles': [
            for (final s in kStylePresets)
              {'id': s.id, 'label': s.label, 'block': s.block},
          ],
          'poses': [
            for (final p in kPoseTemplates)
              {'id': p.id, 'label': p.label, 'asset': p.asset},
          ],
          // Fit per model, not a single verdict: the same file is native on
          // Illustrious and merely weak on Juggernaut.
          'loras': [
            for (final n in serverLoras)
              {
                'name': n,
                'family': familyOfLora(n).name,
                'familyLabel': loraFamilyLabel(familyOfLora(n)),
                'fit': {
                  for (final m in models)
                    m.id: fitOfLora(n, m.loraFamily).name,
                },
              },
          ],
          'defaultLoraStrength': kDefaultLoraStrength,
          'buckets': [
            for (final b in kSdxlBuckets) '${b.w}x${b.h}',
          ],
          'prompts': prompts,
        }),
      );
    }
    stdout.writeln('DUMP $n workflows · ${models.length} modelů × '
        '${prompts.length} promptů × ${styles.length + 1} stylů × '
        '${flows.length} flow'
        '${sweep.isEmpty ? '' : ' × ${sweep.values.length} variant'}'
        '${skipped.isEmpty ? '' : ' · přeskočeno ${skipped.length}'}');
    expect(n, greaterThan(0), reason: 'dump nevyrobil žádné workflow');
  });
}

/// The text actually fed to the sampler's positive/negative conditioning.
String? _encodedText(Map<String, dynamic> wf, {required bool positive}) {
  Map<String, dynamic>? sampler;
  for (final e in wf.entries) {
    final node = (e.value as Map).cast<String, dynamic>();
    if (node['class_type'] == 'KSampler') {
      sampler = node;
      break;
    }
  }
  final inputs = (sampler?['inputs'] as Map?)?.cast<String, dynamic>();
  var ref = inputs?[positive ? 'positive' : 'negative'];
  // Walk through the ControlNet apply node the app splices in.
  for (var hop = 0; hop < 4 && ref is List && ref.length == 2; hop++) {
    final node = (wf[ref[0]] as Map?)?.cast<String, dynamic>();
    if (node == null) return null;
    final ni = (node['inputs'] as Map?)?.cast<String, dynamic>();
    if (node['class_type'] == 'CLIPTextEncode') return ni?['text'] as String?;
    // FluxGuidance names its single input `conditioning`, so the positive side
    // of a FLUX graph dead-ends without this hop.
    ref = ni?[positive ? 'positive' : 'negative'] ?? ni?['conditioning'];
  }
  return null;
}

/// Which identity mechanism the finished graph actually carries. Derived, not
/// remembered: FLUX maps every mode onto PuLID, and a mode the graph had no
/// reference to read a face from silently stays off.
String _effectiveFaceIdentity(Map<String, dynamic> wf) {
  if (wf.containsKey('__face_pulid__')) return 'pulid';
  final instant = wf.containsKey('__face_id__');
  final faceId = wf.containsKey('__faceid_apply__');
  if (instant && faceId) return 'both';
  if (instant) return 'instantid';
  if (faceId) return 'faceid';
  return 'none';
}
