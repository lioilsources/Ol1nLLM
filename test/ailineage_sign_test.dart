import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/services/comfyui_service.dart';

/// AILineage: every SaveImage of a prepared graph becomes the signing node,
/// keeping its image edge and filename prefix, and commits to the user's own
/// prompt rather than the preset-prefixed text the encoder sees.
Map<String, dynamic> _load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final pony = imageModelById('pony');

  test('SaveImage becomes AILineageSaveImage with the user prompt', () {
    final svc = ComfyUIService()..setPreset(pony.preset!);
    final wf = svc.prepareForTest(
      _load(pony.preset!.txt2imgAsset),
      prompt: 'a fox in the snow',
      batch: 2,
      seed: 7,
    );
    final before = wf.values
        .firstWhere((n) => n['class_type'] == 'SaveImage')['inputs'] as Map;
    final images = before['images'];
    final prefix = before['filename_prefix'];

    ComfyUIService.signOutputs(wf, prompt: 'a fox in the snow');

    expect(wf.values.where((n) => n['class_type'] == 'SaveImage'), isEmpty);
    final node = wf.values.singleWhere(
      (n) => n['class_type'] == ComfyUIService.kAiLineageNode,
    );
    final inputs = node['inputs'] as Map;
    expect(inputs['images'], images);
    expect(inputs['filename_prefix'], prefix);
    expect(inputs['format'], 'png');
    expect(inputs['prompt_storage'], 'none');
    expect(inputs['prompt_text'], 'a fox in the snow');
    expect(inputs['embed_workflow'], false);
  });

  test('every shipped generation template has exactly one SaveImage', () {
    // The swap assumes one output node per generation graph; the analysis
    // and mesh graphs never go through _run and are not signed.
    const unsigned = {'hair_analyse.api.json', 'img2print.api.json'};
    for (final f in Directory('assets/comfyui').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.api.json') || unsigned.contains(name)) continue;
      final wf = _load(f.path);
      final saves =
          wf.values.where((n) => (n as Map)['class_type'] == 'SaveImage');
      expect(saves, hasLength(1), reason: name);
      ComfyUIService.signOutputs(wf, prompt: 'p');
      expect(
        wf.values.where((n) => (n as Map)['class_type'] == 'SaveImage'),
        isEmpty,
        reason: name,
      );
    }
  });
}
