import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/services/video_service.dart';

Uint8List _mp4() {
  final b = BytesBuilder();
  void atom(String type, int payload) {
    final size = ByteData(4)..setUint32(0, 8 + payload);
    b.add(size.buffer.asUint8List());
    b.add(type.codeUnits);
    b.add(Uint8List(payload));
  }

  atom('ftyp', 8);
  atom('moov', 24);
  atom('mdat', 100);
  return b.toBytes();
}

void main() {
  test('úplné mp4 projde', () {
    final f = _mp4();
    expect(mp4LooksComplete(f, f.length), isTrue);
    expect(mp4LooksComplete(f, null), isTrue);
  });

  test('uříznutý mdat neprojde', () {
    final f = _mp4();
    final cut = Uint8List.sublistView(f, 0, f.length - 20);
    expect(mp4LooksComplete(cut, null), isFalse);
  });

  test('nesouhlas s content-length neprojde', () {
    final f = _mp4();
    expect(mp4LooksComplete(f, f.length + 5), isFalse);
  });

  test('soubor bez moov neprojde', () {
    final b = BytesBuilder();
    final size = ByteData(4)..setUint32(0, 16);
    b.add(size.buffer.asUint8List());
    b.add('ftyp'.codeUnits);
    b.add(Uint8List(8));
    expect(mp4LooksComplete(b.toBytes(), null), isFalse);
  });
}
