import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/gen_node.dart';

/// `isRepose` persistence contract: present only when true, default false
/// for legacy sessions, carried through copyWith like every identity field.
void main() {
  test('repose node round-trips with its metadata', () {
    final node = GenNode.create(
      parentId: 'p',
      sourceImageId: 'ref',
      prompt: 'a knight',
      isRepose: true,
      modelId: 'pony',
      seed: 42,
      width: 832,
      height: 1216,
      denoise: 1.0,
    );
    final json = node.toJson();
    expect(json['isRepose'], isTrue);
    expect(json.containsKey('poseId'), isFalse);

    final back = GenNode.fromJson(json);
    expect(back.isRepose, isTrue);
    expect(back.sourceImageId, 'ref');
    expect(back.width, 832);
    expect(back.height, 1216);
    expect(back.denoise, 1.0);
  });

  test('legacy JSON without the key reads as not repose', () {
    final back = GenNode.fromJson({
      'id': 'n',
      'prompt': 'x',
      'status': 'ready',
      'images': <Map<String, dynamic>>[],
    });
    expect(back.isRepose, isFalse);
  });

  test('non-repose nodes do not emit the key', () {
    final json = GenNode.create(prompt: 'x').toJson();
    expect(json.containsKey('isRepose'), isFalse);
  });

  test('copyWith preserves the flag', () {
    final node = GenNode.create(prompt: 'x', isRepose: true)
        .copyWith(status: GenStatus.ready, jobId: 'j');
    expect(node.isRepose, isTrue);
    expect(node.status, GenStatus.ready);
  });
}
