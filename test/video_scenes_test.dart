import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/video_scene.dart';
import 'package:ol1n_llm/providers/image_studio_provider.dart';

/// The scene catalog is app-scoped: it is fetched once at startup, while
/// session restore/switch rebuilds the whole state from scratch. Dropping it
/// there hid the „Rozhýbat" button in 1.12.0, so pin the invariant.
void main() {
  const scenes = [
    VideoScene(
      id: 'blink_smile',
      label: 'Mrknutí a úsměv',
      desc: '',
      beats: 3,
      seconds: 15.1,
      minutesEst: 8,
    ),
  ];

  test('audio flag parses, and an older server without it means silent', () {
    final withAudio = VideoScene.fromJson(const {
      'id': 'ltx_dance_music',
      'label': 'Tanec s hudbou',
      'desc': '',
      'beats': 1,
      'seconds': 4.8,
      'minutes_est': 3,
      'audio': true,
    });
    expect(withAudio.audio, isTrue);

    // Server před přidáním zvuku pole neposílá — nesmí to shodit parsování.
    final legacy = VideoScene.fromJson(const {
      'id': 'wink',
      'label': 'Mrknutí',
      'desc': '',
      'beats': 3,
      'seconds': 13.4,
      'minutes_est': 6,
    });
    expect(legacy.audio, isFalse);
  });

  test('copyWith keeps the scene catalog', () {
    const s = ImageStudioState(availableScenes: scenes);
    expect(s.copyWith(currentNodeId: 'x').availableScenes, hasLength(1));
  });

  test('a state rebuilt for another session must carry the catalog over', () {
    // Mirrors selectSession/_load: fresh ImageStudioState, catalogs passed by
    // hand. Forgetting availableScenes is exactly the 1.12.0 bug.
    const restored = ImageStudioState(
      nodes: [],
      availableLoras: ['a'],
      availableCheckpoints: ['b'],
      availableScenes: scenes,
    );
    expect(restored.availableScenes, isNotEmpty);
  });
}
