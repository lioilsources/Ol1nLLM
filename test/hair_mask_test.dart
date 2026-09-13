// Mirror of MangaPrompts tgbot/tests/test_hairmask.py: the same synthetic
// fixture, the same assertions. A 512² frame, face ellipse centred at
// (256, 280) with radii 50×65, eyes at y 265, brows at y 250, hair a disc of
// radius 85 around (256, 250) above y 250 and outside the face.

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ol1n_llm/models/hair_mask.dart';

const size = 512;
const cx = 256, cy = 280, rx = 50, ry = 65;

BoolMask ellipse(double ex, double ey, double erx, double ery, [int s = size]) {
  final m = BoolMask(s, s);
  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      final dx = (x - ex) / erx, dy = (y - ey) / ery;
      if (dx * dx + dy * dy <= 1.0) m.set(x, y);
    }
  }
  return m;
}

HairAnalysis synthetic({
  int s = size,
  double k = 1,
  bool hair = true,
  bool hat = false,
}) {
  final face = ellipse(cx * k, cy * k, rx * k, ry * k, s);
  final features = ellipse((cx - 20) * k, 265 * k, 9 * k, 5 * k, s)
      .or(ellipse((cx + 20) * k, 265 * k, 9 * k, 5 * k, s))
      .or(ellipse((cx - 20) * k, 250 * k, 13 * k, 3 * k, s))
      .or(ellipse((cx + 20) * k, 250 * k, 13 * k, 3 * k, s));
  final hairM = BoolMask(s, s);
  if (hair) {
    for (var y = 0; y < s; y++) {
      for (var x = 0; x < s; x++) {
        final dx = x - cx * k, dy = y - 250 * k;
        if (dx * dx + dy * dy <= (85 * k) * (85 * k) &&
            y < 250 * k &&
            !face.at(x, y)) {
          hairM.set(x, y);
        }
      }
    }
  }
  final hatM = hat
      ? ellipse(cx * k, 150 * k, 70 * k, 25 * k, s)
      : BoolMask(s, s);
  return HairAnalysis(hair: hairM, face: face, hat: hatM, features: features);
}

bool anyOverlap(BoolMask a, BoolMask b) {
  for (var i = 0; i < a.data.length; i++) {
    if (a.data[i] & b.data[i] != 0) return true;
  }
  return false;
}

double area(HairShape shape, [HairAnalysis? a]) =>
    buildHairMask(a ?? synthetic(), shape).area;

void main() {
  test('face box ignores stray pixels', () {
    final a = synthetic();
    a.face.set(5, 5);
    final (x0, y0, x1, y1) = faceBox(a.face)!;
    expect(x0, inInclusiveRange(204, 210));
    expect(x1, inInclusiveRange(302, 308));
    expect(y0, inInclusiveRange(213, 220));
    expect(y1, inInclusiveRange(340, 347));
  });

  test('face features and lower face are never repainted', () {
    final a = synthetic();
    final lower = BoolMask(size, size);
    for (var y = cy; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (a.face.at(x, y)) lower.set(x, y);
      }
    }
    for (final length in HairLength.values) {
      for (final bangs in HairBangs.values) {
        final r = buildHairMask(a, HairShape(length: length, bangs: bangs));
        expect(
          anyOverlap(r.mask, a.features),
          isFalse,
          reason: '$length $bangs',
        );
        expect(anyOverlap(r.mask, lower), isFalse, reason: '$length $bangs');
      }
    }
  });

  test('old hair is always repainted with a margin', () {
    final a = synthetic();
    final r = buildHairMask(a, const HairShape(length: HairLength.keep));
    for (var i = 0; i < a.hair.data.length; i++) {
      if (a.hair.data[i] == 1) expect(r.mask.data[i], 1);
    }
    expect(r.mask.at(cx, 250 - 85 - 3), isTrue);
  });

  test('short envelope ends at the chin', () {
    final a = synthetic();
    final (_, _, _, y1) = faceBox(a.face)!;
    final r = buildHairMask(a, const HairShape(length: HairLength.short));
    for (var y = y1 + 2; y < size; y++) {
      for (var x = 0; x < size; x++) {
        expect(r.mask.at(x, y), isFalse);
      }
    }
  });

  test('long envelope reaches well below the chin; areas grow with length', () {
    final a = synthetic();
    final (_, y0, _, y1) = faceBox(a.face)!;
    final fh = y1 - y0 + 1;
    final r = buildHairMask(a, const HairShape(length: HairLength.long));
    expect(
      r.mask.at(cx - rx - 10, (y1 + 1.5 * fh).toInt().clamp(0, size - 1)),
      isTrue,
    );
    expect(
      r.area,
      greaterThan(area(const HairShape(length: HairLength.medium))),
    );
    expect(
      area(const HairShape(length: HairLength.medium)),
      greaterThan(area(const HairShape(length: HairLength.short))),
    );
    expect(area(const HairShape(length: HairLength.medium)), lessThan(0.35));
  });

  test('forehead band only with a fringe, clear of the brows', () {
    final a = synthetic();
    final (_, y0, _, _) = faceBox(a.face)!;
    expect(a.face.at(cx, y0 + 6), isTrue);
    expect(
      buildHairMask(
        a,
        const HairShape(length: HairLength.keep),
      ).mask.at(cx, y0 + 6),
      isFalse,
    );
    for (final b in [
      HairBangs.full,
      HairBangs.side,
      HairBangs.curtain,
      HairBangs.wispy,
    ]) {
      final r = buildHairMask(a, HairShape(length: HairLength.keep, bangs: b));
      expect(r.mask.at(cx, y0 + 6), isTrue, reason: '$b');
    }
    final full = buildHairMask(
      a,
      const HairShape(length: HairLength.keep, bangs: HairBangs.full),
    );
    final guard = dilateMask(a.features, 3);
    final guardedFace = BoolMask(size, size);
    for (var i = 0; i < guard.data.length; i++) {
      guardedFace.data[i] = guard.data[i] & a.face.data[i];
    }
    expect(anyOverlap(full.mask, guardedFace), isFalse);
  });

  test('updo makes room above the head; hat is repainted', () {
    final a = synthetic();
    final (_, y0, _, y1) = faceBox(a.face)!;
    final above = (y0 - 0.7 * (y1 - y0 + 1)).toInt().clamp(0, size);
    expect(
      buildHairMask(
        a,
        const HairShape(length: HairLength.keep),
      ).mask.at(cx, above),
      isFalse,
    );
    expect(
      buildHairMask(
        a,
        const HairShape(length: HairLength.keep, updo: true),
      ).mask.at(cx, above),
      isTrue,
    );
    expect(
      buildHairMask(
        synthetic(hat: true),
        const HairShape(length: HairLength.keep),
      ).mask.at(cx, 150),
      isTrue,
    );
  });

  test('refusals: no face, tiny face, nothing to repaint', () {
    final noFace = synthetic();
    noFace.face.data.fillRange(0, noFace.face.data.length, 0);
    expect(
      () => buildHairMask(noFace, const HairShape(length: HairLength.short)),
      throwsA(
        isA<HairMaskException>().having((e) => e.code, 'code', 'no_face'),
      ),
    );
    final tiny = ellipse(256, 256, 8, 10);
    expect(
      () => buildHairMask(
        HairAnalysis(
          hair: BoolMask(size, size),
          face: tiny,
          hat: BoolMask(size, size),
        ),
        const HairShape(length: HairLength.long),
      ),
      throwsA(
        isA<HairMaskException>().having(
          (e) => e.code,
          'code',
          'face_too_small',
        ),
      ),
    );
    final bald = synthetic(hair: false);
    expect(
      () => buildHairMask(bald, const HairShape(length: HairLength.keep)),
      throwsA(
        isA<HairMaskException>().having(
          (e) => e.code,
          'code',
          'mask_too_small',
        ),
      ),
    );
    expect(
      area(const HairShape(length: HairLength.short), bald),
      greaterThan(kHairMinMaskArea),
    );
  });

  test('large photos are processed scaled and returned full size', () {
    final a = synthetic(s: 1536, k: 3);
    final r = buildHairMask(
      a,
      const HairShape(length: HairLength.medium, bangs: HairBangs.full),
    );
    expect((r.mask.w, r.mask.h), (1536, 1536));
    expect(anyOverlap(r.mask, a.features), isFalse);
    final (x0, _, _, y1) = r.faceBox;
    expect((x0 - 3 * (cx - rx)).abs(), lessThan(24));
    expect((y1 - 3 * (cy + ry)).abs(), lessThan(24));
  });

  test('png round trip and python rounding', () {
    final r = buildHairMask(
      synthetic(),
      const HairShape(length: HairLength.short),
    );
    final back = decodeMaskPng(maskToPng(r.mask));
    expect(back.data, r.mask.data);
    expect(
      [pyRound(0.5), pyRound(1.5), pyRound(2.5), pyRound(2.6)],
      [0, 2, 2, 3],
    );
    expect(
      const HairShape(
        length: HairLength.long,
        bangs: HairBangs.curtain,
        updo: true,
      ).key,
      'long-curtain-updo',
    );
  });

  group('colour', () {
    const cases = {
      (20, 18, 16): 'black',
      (60, 40, 28): 'dark brown',
      (85, 58, 38): 'brown',
      (125, 90, 58): 'light brown',
      (190, 155, 100): 'blonde',
      (235, 225, 200): 'platinum blonde',
      (150, 148, 146): 'grey',
      (235, 235, 235): 'white',
      (170, 80, 40): 'auburn',
    };
    img.Image canvas(
      HairAnalysis a,
      (int, int, int) Function(int x, int y) hairColour,
    ) {
      final im = img.Image(width: size, height: size);
      img.fill(im, color: img.ColorRgb8(200, 200, 200));
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          if (a.hair.at(x, y)) {
            final (r, g, b) = hairColour(x, y);
            im.setPixelRgb(x, y, r, g, b);
          }
        }
      }
      return im;
    }

    cases.forEach((rgb, name) {
      test('$rgb → $name', () {
        final a = synthetic();
        expect(estimateHairColour(canvas(a, (_, _) => rgb), a.hair), name);
      });
    });

    test('reads lit strands, not the shadows between them', () {
      final a = synthetic();
      final im = canvas(a, (x, _) => x % 5 < 3 ? (22, 15, 11) : (85, 58, 38));
      expect(estimateHairColour(im, a.hair), 'brown');
      expect(estimateHairColour(im, BoolMask(size, size)), isNull);
    });
  });
}
