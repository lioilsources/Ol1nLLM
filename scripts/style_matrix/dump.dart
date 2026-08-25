// Emits the exact ComfyUI workflows the app would send, for an offline
// style/model matrix. Runs through the app's own graph builder
// (ComfyUIService.prepareForTest → _prepare), so what the matrix measures is
// what the app actually generates — not a re-implementation that can drift.
//
// Driven by env vars (see run.sh); writes <OUT_DIR>/<flow>__<model>__<style>.json
// plus a `__baseline` entry per model (same prompt, no style block) so a
// scorer can tell "the model reacted to this style" from "the model always
// paints this".
//
//   flutter test scripts/style_matrix/dump.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/models/latent_bucket.dart';
import 'package:ol1n_llm/models/style_preset.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

Map<String, dynamic> _load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<String> _csv(String? v) => (v == null || v.trim().isEmpty)
    ? const []
    : v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

void main() {
  test('dump matrix workflows', () {
    final env = Platform.environment;
    final out = Directory(env['OUT_DIR']!)..createSync(recursive: true);
    final seed = int.parse(env['SEED'] ?? '777');
    final subject = env['SUBJECT']!;
    final refName = env['REF_NAME'];
    final refFile = env['REF_FILE'];
    final flows = _csv(env['FLOWS']).isEmpty
        ? const ['repose', 'img2img']
        : _csv(env['FLOWS']);

    // Only models the server can actually run, unless the caller narrows it.
    final installed = env['CKPTS'] == null
        ? const <String>[]
        : File(env['CKPTS']!).readAsLinesSync()
            .where((l) => l.trim().isNotEmpty).toList();
    final wanted = _csv(env['MODELS']);
    final models = imageModelsFor(installed)
        .where((m) => m.kind == ImageBackendKind.comfyUi && m.preset != null)
        .where((m) => wanted.isEmpty || wanted.contains(m.id))
        .toList();

    // Styles come from the app registry, unless the caller points at a file
    // of candidates — that is how a style gets vetted *before* it is added
    // to kStylePresets.
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

    // Parameter A/B: `sampler_name=dpmpp_2m,scheduler=karras,cfg=6`. Applied
    // to the finished graph, which is what changing the preset would produce
    // — _prepare writes exactly these fields from ComfyPreset.
    final overrides = <String, dynamic>{};
    for (final kv in _csv(env['OVERRIDE'])) {
      final i = kv.indexOf('=');
      if (i < 1) fail('bad --override entry: $kv');
      final k = kv.substring(0, i);
      final v = kv.substring(i + 1);
      overrides[k] = num.tryParse(v) ?? v;
    }
    // Variant label lands in the flow segment, so runs stay comparable
    // side by side: `img2img@karras__pony__ukiyoe.png`.
    final variant = env['VARIANT'] == null ? '' : '@${env['VARIANT']}';

    Map<String, dynamic> applyOverrides(Map<String, dynamic> wf) {
      if (overrides.isEmpty) return wf;
      for (final node in wf.values) {
        final inputs = ((node as Map)['inputs'] as Map?)?.cast<String, dynamic>();
        if (inputs == null) continue;
        for (final e in overrides.entries) {
          if (inputs.containsKey(e.key)) inputs[e.key] = e.value;
        }
      }
      return wf;
    }

    var n = 0;
    void write(String flow, String model, String style,
        Map<String, dynamic> wf) {
      File('${out.path}/${flow}${variant}__${model}__${style}.json')
          .writeAsStringSync(jsonEncode(applyOverrides(wf)));
      n++;
    }

    for (final m in models) {
      final preset = m.preset!;
      // Mirrors ComfyUIService.repose() / edit(): repose needs the generic
      // SDXL template + depth ControlNet, auto-depth follows supportsPose.
      final canRepose = preset.ckptName != null && m.supportsPose;
      final sourceDepth = m.supportsPose && preset.ckptName != null;
      final latent = refFile == null
          ? null
          : reposeLatentFor(File(refFile).readAsBytesSync(),
              fallback: (w: preset.width, h: preset.height));

      for (final entry in [null, ...styles]) {
        final id = entry?.id ?? '__baseline';
        final prompt = applyStyle(subject, entry?.id);
        for (final flow in flows) {
          final svc = ComfyUIService()..setPreset(preset);
          if (flow == 'repose') {
            if (!canRepose || refName == null) continue;
            write('repose', m.id, id, svc.prepareForTest(
              _load(preset.txt2imgAsset),
              prompt: prompt, batch: 1, seed: seed,
              depthImageName: refName, latentSize: latent,
            ));
          } else if (flow == 'img2img') {
            if (refName == null) continue;
            write('img2img', m.id, id, svc.prepareForTest(
              _load(preset.img2imgAsset),
              prompt: prompt, batch: 1, seed: seed,
              imageName: refName, sourceDepth: sourceDepth,
              editDenoise: env['EDIT_DENOISE'] == null
                  ? null
                  : double.parse(env['EDIT_DENOISE']!),
            ));
          } else if (flow == 'txt2img') {
            write('txt2img', m.id, id, svc.prepareForTest(
              _load(preset.txt2imgAsset),
              prompt: prompt, batch: 1, seed: seed,
            ));
          } else {
            fail('unknown flow: $flow');
          }
        }
      }
    }
    stdout.writeln('DUMP $n workflows · '
        '${models.length} models × ${styles.length + 1} prompts × '
        '${flows.length} flows');
    expect(n, greaterThan(0));
  });
}
