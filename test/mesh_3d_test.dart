import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/gen_node.dart';

/// Guards the img2print asset contract (deterministic mesh-id prefixes that
/// generateMesh/followMesh rely on) and the GenNode 3D persistence.
void main() {
  group('img2print asset', () {
    final wf =
        jsonDecode(File('assets/comfyui/img2print.api.json').readAsStringSync())
            as Map<String, dynamic>;

    test('carries the sentinels the service patches', () {
      final s = jsonEncode(wf);
      expect(s, contains('__IMAGE__'));
      // Two exports with the deterministic prefixes — STL + GLB. followMesh
      // downloads `<id>_00001_.stl` / `<id>g_00001_.glb` from subfolder 3D/app.
      expect(s, contains('3D/app/__MESHID__'));
      expect(s, contains('3D/app/__MESHID__g'));
    });

    test('exports stl + glb via crop&stitch pipeline', () {
      final exports = wf.values
          .where((n) => (n as Map)['class_type'] == 'Trellis2ExportMesh')
          .map((n) => ((n as Map)['inputs'] as Map)['file_format'])
          .toList();
      expect(exports, containsAll(['stl', 'glb']));
      final classes =
          wf.values.map((n) => (n as Map)['class_type']).toSet();
      // The validated printability chain must stay intact.
      expect(
        classes,
        containsAll([
          'Trellis2VoxelToMesh',
          'Trellis2SimplifyMesh',
          'Trellis2FillHolesWithMeshlib',
          'InpaintCropImproved',
        ].where(classes.contains).toList(),
      ));
      expect(classes, contains('Trellis2VoxelToMesh'));
      expect(classes, contains('Trellis2FillHolesWithMeshlib'));
      // Simplify must use Meshlib (Cumesh breaks watertightness on sm_120).
      final simplify = wf.values.firstWhere(
        (n) => (n as Map)['class_type'] == 'Trellis2SimplifyMesh',
      ) as Map;
      expect((simplify['inputs'] as Map)['method'], 'Meshlib');
      // STL branch must export native Z-up (None), not the GLB-viewer Y-up.
      final trimeshNodes = wf.values
          .where(
            (n) => (n as Map)['class_type'] == 'Trellis2MeshWithVoxelToTrimesh',
          )
          .map((n) => ((n as Map)['inputs'] as Map)['reorient_vertices'])
          .toSet();
      expect(trimeshNodes, containsAll(['None', '90 degrees']));
    });

    test('mm scaling is baked in', () {
      final v2m = wf.values.firstWhere(
        (n) => (n as Map)['class_type'] == 'Trellis2VoxelToMesh',
      ) as Map;
      expect((v2m['inputs'] as Map)['target_height_mm'], 100.0);
    });
  });

  group('GenNode 3D persistence', () {
    test('round-trips is3D + mesh file names', () {
      final node = GenNode.create(
        prompt: '3D model',
        is3D: true,
        sourceImageId: 'img-1',
        seed: 42,
      ).copyWith(
        status: GenStatus.ready,
        glbFileName: 'abc.glb',
        stlFileName: 'abc.stl',
      );
      final back = GenNode.fromJson(node.toJson());
      expect(back.is3D, isTrue);
      expect(back.glbFileName, 'abc.glb');
      expect(back.stlFileName, 'abc.stl');
      expect(back.status, GenStatus.ready);
    });

    test('legacy nodes read as non-3D', () {
      final back = GenNode.fromJson({
        'id': 'x',
        'prompt': 'p',
        'status': 'ready',
        'images': [],
      });
      expect(back.is3D, isFalse);
      expect(back.glbFileName, isNull);
    });
  });
}
