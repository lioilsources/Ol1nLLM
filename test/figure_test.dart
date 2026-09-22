import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/figure_clip.dart';
import 'package:ol1n_llm/models/gen_node.dart';
import 'package:ol1n_llm/providers/image_studio_provider.dart';
import 'package:ol1n_llm/services/figure_service.dart';

/// „Tančící figurka": parsing of the UGCFactory character API, the GLB
/// integrity check, node persistence and the app-scoped dance catalog.
void main() {
  Map<String, dynamic> detail(
    String status, {
    List<Map<String, dynamic>> steps = const [],
    List<Map<String, dynamic>> animations = const [],
    String? error,
  }) => {
    'character': {'id': 'c1', 'status': status, 'error': ?error},
    'steps': steps,
    'animations': animations,
  };

  group('figureProgress', () {
    test('a real finished character: done, clips in timeline order', () {
      // test/fixtures/figure_detail_done.json je doslovná odpověď
      // GET /v1/fc/characters/{id} z NAS (2026-09-15), jen zkrácená historie.
      final json =
          jsonDecode(
                File(
                  'test/fixtures/figure_detail_done.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final p = figureProgress(json);
      expect(p.done, isTrue);
      expect(p.error, isNull);
      expect(p.clipIds, hasLength(10));
      expect(p.clipIds.first, 'booty_hip_hop_dance');
      expect(p.clipIds, contains('salsa_dancing'));
    });

    test('clips are ordered by frame_start, not by list order', () {
      final p = figureProgress(
        detail(
          'done',
          animations: [
            {'animation_id': 'salsa', 'frame_start': 130},
            {'animation_id': 'samba', 'frame_start': 1},
          ],
        ),
      );
      expect(p.clipIds, ['samba', 'salsa']);
    });

    test('status names the finished step, the stage is the next one', () {
      expect(figureProgress(detail('uploaded')).stage, 0);
      expect(figureProgress(detail('preprocessed')).stage, 1);
      expect(figureProgress(detail('meshed')).stage, 2);
      expect(figureProgress(detail('rigged')).stage, 4);
      expect(figureStageLabel(1), contains('3D model'));
      // mimo rozsah se label neptá indexem do prázdna
      expect(figureStageLabel(99), kFigureStageLabels.last);
    });

    test('a first step nobody claimed yet is queued', () {
      final p = figureProgress(
        detail(
          'uploaded',
          steps: [
            {'step': 'char.preprocess', 'status': 'queued'},
          ],
        ),
      );
      expect(p.queued, isTrue);
      expect(p.done, isFalse);
    });

    test('failed carries the server error, or a readable default', () {
      expect(
        figureProgress(detail('failed', error: 'char.rig: mesh nesedí')).error,
        'char.rig: mesh nesedí',
      );
      expect(figureProgress(detail('failed')).error, 'Figurka se nepovedla');
    });
  });

  group('glbLooksComplete', () {
    Uint8List glb(int declared, int actual) {
      final b = Uint8List(actual);
      final d = ByteData.sublistView(b);
      d.setUint32(0, 0x46546C67, Endian.little); // 'glTF'
      d.setUint32(4, 2, Endian.little);
      d.setUint32(8, declared, Endian.little);
      return b;
    }

    test('length in the header must match the download', () {
      expect(glbLooksComplete(glb(64, 64)), isTrue);
      expect(glbLooksComplete(glb(3252848, 1048576)), isFalse); // uříznuté
    });

    test('anything that is not binary glTF is rejected', () {
      final html = Uint8List.fromList(
        utf8.encode('<html>Access denied</html>'),
      );
      expect(glbLooksComplete(html), isFalse);
      expect(glbLooksComplete(Uint8List(4)), isFalse);
    });
  });

  group('FigureClip', () {
    test('name falls back to the id', () {
      expect(
        FigureClip.fromJson(const {'id': 'salsa', 'name': ''}).name,
        'salsa',
      );
      expect(
        FigureClip.fromJson(const {'id': 'salsa', 'name': 'Salsa'}).name,
        'Salsa',
      );
    });

    test('label of a clip the catalog no longer has stays readable', () {
      const catalog = [FigureClip(id: 'chicken_dance', name: 'Ptačí tanec')];
      expect(figureClipLabel('chicken_dance', catalog), 'Ptačí tanec');
      expect(
        figureClipLabel('snake_hip_hop_dance', catalog),
        'Snake hip hop dance',
      );
    });
  });

  group('GenNode figure persistence', () {
    test('round-trips isFigure, figureId, clipIds and the GLB', () {
      final node =
          GenNode.create(
            sourceImageId: 'img',
            prompt: 'Tančící figurka',
            isFigure: true,
          ).copyWith(
            glbFileName: 'n.glb',
            figureId: 'c1',
            clipIds: const ['salsa', 'samba'],
          );
      final back = GenNode.fromJson(
        jsonDecode(jsonEncode(node.toJson())) as Map<String, dynamic>,
      );
      expect(back.isFigure, isTrue);
      expect(back.figureId, 'c1');
      expect(back.clipIds, ['salsa', 'samba']);
      expect(back.glbFileName, 'n.glb');
      expect(back.is3D, isFalse);
    });

    test(
      'a generating figure with its server id resumes, other nodes stay lean',
      () {
        final generating = GenNode.create(
          prompt: 'Tančící figurka',
          isFigure: true,
        ).copyWith(jobId: 'c1');
        expect(
          GenNode.fromJson(generating.toJson()).status,
          GenStatus.generating,
        );
        final plain = GenNode.create(prompt: 'x').toJson();
        expect(plain.containsKey('isFigure'), isFalse);
        expect(plain.containsKey('clipIds'), isFalse);
        expect(GenNode.fromJson(plain).clipIds, isEmpty);
      },
    );
  });

  group('dance catalog is app-scoped', () {
    const dances = [FigureClip(id: 'salsa_dancing', name: 'Salsa')];

    test('copyWith keeps it', () {
      const s = ImageStudioState(availableDances: dances);
      expect(s.copyWith(currentNodeId: 'x').availableDances, hasLength(1));
    });

    test('provider rebuild sites carry it next to the scene catalog', () {
      // Stejná past jako „Rozhýbat" v 1.12.0: místo, které staví stav znovu a
      // zapomene katalog, schová figurku. Každé předání scén musí mít vedle
      // sebe i tance.
      final src = File(
        'lib/providers/image_studio_provider.dart',
      ).readAsStringSync();
      final scenes = RegExp(
        r'availableScenes: state\.availableScenes,',
      ).allMatches(src).length;
      final carried = RegExp(
        r'availableScenes: state\.availableScenes,\s*availableDances: state\.availableDances,',
      ).allMatches(src).length;
      expect(scenes, greaterThan(0));
      expect(carried, scenes);

      // Stejná past pro „Rozhýbat promptem": meze vlastního pohybu jsou
      // app-scoped jako katalogy, takže musí jet s nimi.
      final withCustom = RegExp(
        r'availableDances: state\.availableDances,\s*'
        r'videoCustom: state\.videoCustom,',
      ).allMatches(src).length;
      expect(withCustom, scenes);
    });
  });
}
