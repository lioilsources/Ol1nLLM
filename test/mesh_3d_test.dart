import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/gen_node.dart';

/// Guards the img2print asset contract (deterministic mesh-id prefixes that
/// generateMesh/followMesh rely on) and the GenNode 3D persistence.
void main() {
  _printBaseTests();
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
      // coarse_downsample=4 seals shell gaps before the interior flood fill.
      // At 1.0 the fill leaked and meshes came out as HOLLOW shells — printed
      // heads collapsed (walls only, no infill volume). Never lower this
      // without re-checking solidity via winding number (trimesh
      // mesh.contains() on eroded-interior points must be ~100% per height
      // band; volume-vs-voxel-fill ratios are biased by surface inflation).
      expect((v2m['inputs'] as Map)['coarse_downsample'], 4.0);
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

/// The printable base is added on the mesh, not hoped for from the image —
/// Trellis drops pedestals when reading a single front view. Both export
/// branches must carry it, each in its own up-axis (STL Z-up for the slicer,
/// GLB Y-up for <model-viewer>).
void _printBaseTests() {
  final wf =
      jsonDecode(File('assets/comfyui/img2print.api.json').readAsStringSync())
          as Map<String, dynamic>;

  group('print base', () {
    test('both export branches go through AddPrintBase', () {
      final bases = wf.entries
          .where((e) => (e.value as Map)['class_type'] == 'AddPrintBase')
          .toList();
      expect(bases, hasLength(2));

      final axes = {
        for (final b in bases)
          ((b.value as Map)['inputs'] as Map)['up_axis'] as String: b.key,
      };
      expect(axes.keys, containsAll(['z', 'y']));

      for (final export in wf.values
          .where((n) => (n as Map)['class_type'] == 'Trellis2ExportMesh')) {
        final src = ((export as Map)['inputs'] as Map)['trimesh'] as List;
        final fmt = (export['inputs'] as Map)['file_format'];
        final expectedAxis = fmt == 'stl' ? 'z' : 'y';
        expect(src[0], axes[expectedAxis],
            reason: '$fmt export must read the $expectedAxis-up base');
      }
    });

    test('base geometry stays print-sane', () {
      final base = wf.values
          .firstWhere((n) => (n as Map)['class_type'] == 'AddPrintBase') as Map;
      final i = base['inputs'] as Map;
      expect(i['shape'], 'cylinder');
      expect(i['height_mm'], greaterThan(0));
      // Wider than the model's footprint, or it would not add stability.
      expect(i['diameter_scale'], greaterThan(1.0));
      // A real overlap is required for the boolean union to be non-degenerate.
      expect(i['sink_mm'], greaterThan(0));
    });
  });
}
