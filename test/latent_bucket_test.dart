import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ol1n_llm/models/latent_bucket.dart';

/// Repose latent sizing: the bucket has to follow the reference's aspect so
/// the depth hint isn't center-cropped, and the size must come from the
/// header only — photo roots are JPEG bytes stored under a `.png` name.
void main() {
  group('snapToSdxlBucket', () {
    const cases = <(int, int, LatentSize)>[
      (1024, 1024, (w: 1024, h: 1024)),
      (832, 1216, (w: 832, h: 1216)),
      (512, 768, (w: 832, h: 1216)), // 2:3 portrait photo
      (768, 1024, (w: 896, h: 1152)), // 3:4
      (1024, 768, (w: 1152, h: 896)), // 4:3
      (720, 1280, (w: 768, h: 1344)), // 9:16
      (1280, 720, (w: 1344, h: 768)), // 16:9
      (1000, 1010, (w: 1024, h: 1024)), // near-square
    ];
    for (final (w, h, want) in cases) {
      test('$w×$h → ${want.w}×${want.h}', () {
        expect(snapToSdxlBucket(w, h), want);
      });
    }

    test('always returns a known bucket', () {
      for (var w = 64; w <= 2048; w += 192) {
        for (var h = 64; h <= 2048; h += 192) {
          expect(kSdxlBuckets, contains(snapToSdxlBucket(w, h)));
        }
      }
    });

    test('degenerate input falls back to square', () {
      expect(snapToSdxlBucket(0, 100), (w: 1024, h: 1024));
    });
  });

  group('decodeImageSize', () {
    test('reads PNG header', () {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 3, height: 5)),
      );
      expect(decodeImageSize(bytes), (w: 3, h: 5));
    });

    test('reads JPEG header (photo roots are JPEG under a .png name)', () {
      final bytes = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 40, height: 24)),
      );
      expect(decodeImageSize(bytes), (w: 40, h: 24));
    });

    test('garbage → null', () {
      expect(decodeImageSize(Uint8List.fromList([1, 2, 3])), isNull);
      expect(decodeImageSize(Uint8List(0)), isNull);
    });
  });

  test('reposeLatentFor snaps the reference, falls back when unreadable', () {
    final portrait = Uint8List.fromList(
      img.encodePng(img.Image(width: 600, height: 900)),
    );
    expect(
      reposeLatentFor(portrait, fallback: (w: 1024, h: 1024)),
      (w: 832, h: 1216),
    );
    expect(
      reposeLatentFor(Uint8List.fromList([9]), fallback: (w: 512, h: 512)),
      (w: 1024, h: 1024),
    );
  });
}
