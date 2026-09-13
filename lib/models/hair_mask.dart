// Kadeřník: inpaint mask from face-parsing masks.
//
// Dart mirror of MangaPrompts `tgbot/hairmask.py` — same constants, same
// steps, same order. Change both together; the tests on both sides build the
// same synthetic fixture and assert the same things (hair_mask_test.dart /
// test_hairmask.py). The numbers are calibrated by the Tsumiki bench
// (`tgbot/tools/bench`, results in `MangaPrompts/docs/hair-matrix.md`).
//
// `assets/comfyui/hair_analyse.api.json` saves four binary masks of the
// portrait (hair, face, hat, eyes+brows). The repaint mask is:
//   1. old hair + hat, dilated so no stray strands survive;
//   2. a forehead band when the new style has a fringe;
//   3. an envelope where the new hair may grow (a longer cut needs room the
//      old hair never had);
//   4. minus the face, so the pixels that carry identity are never touched.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum HairLength { keep, short, medium, long }

enum HairBangs { none, full, side, curtain, wispy }

class HairShape {
  const HairShape({
    required this.length,
    this.bangs = HairBangs.none,
    this.updo = false,
  });

  final HairLength length;
  final HairBangs bangs;
  final bool updo;

  String get key => '${length.name}-${bangs.name}-${updo ? 'updo' : 'down'}';
}

// ── Tunables (units are face-box sizes; see hairmask.py for the why) ────────
const kHairDilateFh = 0.06;
const kHairBangBandFh = 0.28;
const kHairFeatureGuardFh = 0.04;

/// (sideways past the face in face widths, above the face top in face
/// heights, below the chin in face heights); null = no envelope.
const kHairEnvelopes = <HairLength, (double, double, double)?>{
  HairLength.keep: null,
  HairLength.short: (0.35, 0.35, 0.0),
  HairLength.medium: (0.5, 0.35, 0.7),
  HairLength.long: (0.6, 0.35, 1.8),
};

/// "blob" = the bounding rounded rectangle of the union (minus the face);
/// "hair" = the union itself. FLUX paints the mask's shape and SDXL left old
/// strands on the shoulders, so the shipped default is the rectangle.
const kHairMaskMode = 'blob';
const kHairUpdoAboveFh = 0.8;
const kHairUpdoSideFw = 0.3;
const kHairCornerFw = 0.3;
const kHairMinFaceH = 0.08;
const kHairMinMaskArea = 0.02;
const kHairWorkSide = 768;
const kHairMinForColour = 0.005;

/// InpaintCropImproved settings of the Tsumiki hair graphs
/// (`flux_hair_inpaint.api.json`): the face is a hole in the mask, and filling
/// holes repainted it; 1.5 is the context window the bench ran with.
const kHairMaskFillHoles = false;
const kHairContextFactor = 1.5;

/// A photo the Kadeřník cannot work with; [message] is shown to the user.
class HairMaskException implements Exception {
  const HairMaskException(this.code, this.message);

  final String code;
  final String message;

  static const noFace = HairMaskException(
    'no_face',
    'Na fotce není tvář — použij čelní portrét jednoho člověka.',
  );
  static const faceTooSmall = HairMaskException(
    'face_too_small',
    'Tvář je moc malá — ořízni fotku blíž k hlavě a ramenům.',
  );
  static const maskTooSmall = HairMaskException(
    'mask_too_small',
    'Na fotce není dost vlasů, které by šlo přestříhat.',
  );

  @override
  String toString() => message;
}

/// Row-major boolean mask; `data[y * w + x]` is 1 inside.
class BoolMask {
  BoolMask(this.w, this.h, [Uint8List? data]) : data = data ?? Uint8List(w * h);

  final int w;
  final int h;
  final Uint8List data;

  bool at(int x, int y) => data[y * w + x] != 0;
  void set(int x, int y) => data[y * w + x] = 1;

  BoolMask copy() => BoolMask(w, h, Uint8List.fromList(data));

  int get count {
    var n = 0;
    for (final v in data) {
      n += v;
    }
    return n;
  }

  double get mean => count / data.length;

  BoolMask or(BoolMask o) {
    final out = copy();
    for (var i = 0; i < data.length; i++) {
      out.data[i] |= o.data[i];
    }
    return out;
  }

  BoolMask andNot(BoolMask o) {
    final out = copy();
    for (var i = 0; i < data.length; i++) {
      out.data[i] &= 1 - o.data[i];
    }
    return out;
  }

  BoolMask inverted() {
    final out = BoolMask(w, h);
    for (var i = 0; i < data.length; i++) {
      out.data[i] = 1 - data[i];
    }
    return out;
  }
}

class HairAnalysis {
  HairAnalysis({
    required this.hair,
    required this.face,
    required this.hat,
    BoolMask? features,
  }) : features = features ?? BoolMask(face.w, face.h) {
    for (final m in [hair, hat, this.features]) {
      if (m.w != face.w || m.h != face.h) {
        throw ArgumentError('analysis masks differ in size');
      }
    }
  }

  final BoolMask hair;
  final BoolMask face;
  final BoolMask hat;
  final BoolMask features;
}

class HairMaskResult {
  const HairMaskResult(this.mask, this.faceBox, this.area);

  final BoolMask mask;

  /// (x0, y0, x1, y1) in image pixels.
  final (int, int, int, int) faceBox;
  final double area;
}

/// Python's round(): half to even. Keeps pixel counts identical to hairmask.py.
int pyRound(double v) {
  final f = v.floorToDouble();
  final diff = v - f;
  if (diff > 0.5) return f.toInt() + 1;
  if (diff < 0.5) return f.toInt();
  return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
}

/// A saved ComfyUI mask (white = inside) → [BoolMask].
BoolMask decodeMaskPng(Uint8List png) {
  final image = img.decodeImage(png);
  if (image == null) throw const FormatException('mask is not an image');
  final out = BoolMask(image.width, image.height);
  // Masks are grey (MaskToImage writes r = g = b), so the red channel is the
  // luminance hairmask.py thresholds — and what ImageToMask reads.
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).r >= 128) out.set(x, y);
    }
  }
  return out;
}

/// [BoolMask] → black/white PNG, the `__MASK__` convention.
Uint8List maskToPng(BoolMask mask) {
  final image = img.Image(width: mask.w, height: mask.h, numChannels: 1);
  for (var y = 0; y < mask.h; y++) {
    for (var x = 0; x < mask.w; x++) {
      image.setPixelR(x, y, mask.at(x, y) ? 255 : 0);
    }
  }
  return img.encodePng(image);
}

/// numpy.percentile (linear) over the coordinates of set pixels, from a
/// per-coordinate histogram.
double _percentileFromHist(List<int> hist, int n, double p) {
  final pos = p / 100 * (n - 1);
  final lo = pos.floor();
  final frac = pos - lo;
  int valueAt(int rank) {
    var cum = 0;
    for (var i = 0; i < hist.length; i++) {
      cum += hist[i];
      if (cum > rank) return i;
    }
    return hist.length - 1;
  }

  final a = valueAt(lo);
  if (frac == 0) return a.toDouble();
  final b = valueAt(math.min(lo + 1, n - 1));
  return a + frac * (b - a);
}

/// Face box from the 1st/99th percentile of the face pixels.
(int, int, int, int)? faceBox(BoolMask face) {
  final xs = List<int>.filled(face.w, 0);
  final ys = List<int>.filled(face.h, 0);
  var n = 0;
  for (var y = 0; y < face.h; y++) {
    for (var x = 0; x < face.w; x++) {
      if (face.at(x, y)) {
        xs[x]++;
        ys[y]++;
        n++;
      }
    }
  }
  if (n < 50) return null;
  return (
    _percentileFromHist(xs, n, 1).toInt(),
    _percentileFromHist(ys, n, 1).toInt(),
    _percentileFromHist(xs, n, 99).toInt(),
    _percentileFromHist(ys, n, 99).toInt(),
  );
}

/// Nearest-neighbour resize (Pillow's NEAREST: pixel-centre sampling).
BoolMask resizeMask(BoolMask m, int w, int h) {
  final out = BoolMask(w, h);
  final sx = m.w / w;
  final sy = m.h / h;
  for (var y = 0; y < h; y++) {
    final yy = math.min(m.h - 1, ((y + 0.5) * sy).floor());
    for (var x = 0; x < w; x++) {
      final xx = math.min(m.w - 1, ((x + 0.5) * sx).floor());
      out.data[y * w + x] = m.data[yy * m.w + xx];
    }
  }
  return out;
}

/// Grow by about [radius] px: alternating 4- and 8-neighbour steps.
BoolMask dilateMask(BoolMask mask, int radius) {
  var out = mask;
  final w = mask.w, h = mask.h;
  for (var i = 0; i < radius; i++) {
    final src = out.data;
    final grown = Uint8List.fromList(src);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        if (src[row + x] == 0) continue;
        if (y > 0) grown[row - w + x] = 1;
        if (y < h - 1) grown[row + w + x] = 1;
        if (x > 0) grown[row + x - 1] = 1;
        if (x < w - 1) grown[row + x + 1] = 1;
        if (i.isOdd) {
          if (y > 0 && x > 0) grown[row - w + x - 1] = 1;
          if (y > 0 && x < w - 1) grown[row - w + x + 1] = 1;
          if (y < h - 1 && x > 0) grown[row + w + x - 1] = 1;
          if (y < h - 1 && x < w - 1) grown[row + w + x + 1] = 1;
        }
      }
    }
    out = BoolMask(w, h, grown);
  }
  return out;
}

BoolMask roundedRect(
  int h,
  int w,
  double x0,
  double y0,
  double x1,
  double y1,
  double radius,
) {
  final out = BoolMask(w, h);
  final r = math.max(
    0.0,
    math.min(radius, math.min((x1 - x0) / 2, (y1 - y0) / 2)),
  );
  final ys0 = math.max(0, y0.ceil()), ys1 = math.min(h - 1, y1.floor());
  final xs0 = math.max(0, x0.ceil()), xs1 = math.min(w - 1, x1.floor());
  for (var y = ys0; y <= ys1; y++) {
    for (var x = xs0; x <= xs1; x++) {
      if (r > 0) {
        final dx = math.max(math.max(x0 + r - x, 0.0), x - (x1 - r));
        final dy = math.max(math.max(y0 + r - y, 0.0), y - (y1 - r));
        if (dx * dx + dy * dy > r * r) continue;
      }
      out.set(x, y);
    }
  }
  return out;
}

HairMaskResult buildHairMask(
  HairAnalysis a,
  HairShape shape, {
  String mode = kHairMaskMode,
}) {
  final fullW = a.face.w, fullH = a.face.h;
  final scale = math.min(1.0, kHairWorkSide / math.max(fullH, fullW));
  final w = math.max(1, pyRound(fullW * scale));
  final h = math.max(1, pyRound(fullH * scale));
  BoolMask small(BoolMask m) => scale == 1.0 ? m : resizeMask(m, w, h);

  final face = small(a.face);
  final hair = small(a.hair);
  final hat = small(a.hat);
  final features = small(a.features);

  final box = faceBox(face);
  if (box == null) throw HairMaskException.noFace;
  final (x0, y0, x1, y1) = box;
  final fw = x1 - x0 + 1, fh = y1 - y0 + 1;
  if (fh < kHairMinFaceH * h) throw HairMaskException.faceTooSmall;

  var mask = dilateMask(hair.or(hat), pyRound(kHairDilateFh * fh));

  var band = BoolMask(w, h);
  if (shape.bangs != HairBangs.none) {
    final yEnd = math.min(h, y0 + pyRound(kHairBangBandFh * fh));
    final xEnd = math.min(w, x1 + 1);
    for (var y = math.max(0, y0); y < yEnd; y++) {
      for (var x = math.max(0, x0); x < xEnd; x++) {
        band.set(x, y);
      }
    }
    band = band.andNot(
      dilateMask(features, math.max(2, pyRound(kHairFeatureGuardFh * fh))),
    );
    mask = mask.or(band);
  }

  final env = kHairEnvelopes[shape.length];
  if (env != null) {
    final (side, above, below) = env;
    mask = mask.or(
      roundedRect(
        h,
        w,
        x0 - side * fw,
        y0 - above * fh,
        x1 + side * fw,
        y1 + below * fh,
        kHairCornerFw * fw,
      ),
    );
  }
  if (shape.updo) {
    mask = mask.or(
      roundedRect(
        h,
        w,
        x0 - kHairUpdoSideFw * fw,
        y0 - kHairUpdoAboveFh * fh,
        x1 + kHairUpdoSideFw * fw,
        y0 + 0.2 * fh,
        kHairCornerFw * fw,
      ),
    );
  }

  if (mode == 'blob' && mask.count > 0) {
    var bx0 = w, by0 = h, bx1 = -1, by1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!mask.at(x, y)) continue;
        if (x < bx0) bx0 = x;
        if (x > bx1) bx1 = x;
        if (y < by0) by0 = y;
        if (y > by1) by1 = y;
      }
    }
    mask = mask.or(
      roundedRect(
        h,
        w,
        bx0.toDouble(),
        by0.toDouble(),
        bx1.toDouble(),
        by1.toDouble(),
        kHairCornerFw * fw,
      ),
    );
  }

  mask = mask.andNot(face.andNot(band));
  final area = mask.mean;
  if (area < kHairMinMaskArea) throw HairMaskException.maskTooSmall;

  if (scale != 1.0) {
    mask = resizeMask(
      mask,
      fullW,
      fullH,
    ).andNot(a.face.andNot(resizeMask(band, fullW, fullH)));
  }
  final inv = 1.0 / scale;
  return HairMaskResult(mask, (
    (x0 * inv).toInt(),
    (y0 * inv).toInt(),
    (x1 * inv).toInt(),
    (y1 * inv).toInt(),
  ), area);
}

// ── Hair colour ─────────────────────────────────────────────────────────────

List<double> _srgbToLab(int r, int g, int b) {
  double lin(int c) {
    final v = c / 255.0;
    return v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final rl = lin(r), gl = lin(g), bl = lin(b);
  final x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047;
  final y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl;
  final z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883;
  const eps = 216 / 24389, kappa = 24389 / 27;
  double f(double t) =>
      t > eps ? math.pow(t, 1 / 3).toDouble() : (kappa * t + 16) / 116;
  final fx = f(x), fy = f(y), fz = f(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

String hairColourName(double l, double a, double b) {
  final chroma = math.sqrt(a * a + b * b);
  if (l < 22 && chroma < 10) return 'black';
  if (chroma < 8 && l > 75) return 'white';
  if (chroma < 8 && l > 38) return 'grey';
  if (a > 16) return 'auburn';
  if (l < 22) return 'dark brown';
  if (l < 33) return 'brown';
  if (l < 48) return 'light brown';
  if (l < 72) return 'blonde';
  return 'platinum blonde';
}

double _median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Colour word for the hair, read from the lit strands (50th–90th luminance
/// rank of the hair core), or null when there is too little hair.
String? estimateHairColour(img.Image rgb, BoolMask hair) {
  if (rgb.width != hair.w || rgb.height != hair.h) {
    throw ArgumentError('hair mask and image differ in size');
  }
  if (hair.mean < kHairMinForColour) return null;
  final core = hair.andNot(dilateMask(hair.inverted(), 3));
  final use = core.count >= 50 ? core : hair;
  final labs = <List<double>>[];
  for (var y = 0; y < hair.h; y++) {
    for (var x = 0; x < hair.w; x++) {
      if (!use.at(x, y)) continue;
      final p = rgb.getPixel(x, y);
      labs.add(_srgbToLab(p.r.toInt(), p.g.toInt(), p.b.toInt()));
    }
  }
  // Stable sort by L, like numpy's argsort(kind="stable").
  final order = List<int>.generate(labs.length, (i) => i)
    ..sort((i, j) {
      final c = labs[i][0].compareTo(labs[j][0]);
      return c != 0 ? c : i.compareTo(j);
    });
  final start = (0.5 * order.length).toInt();
  final end = math.max((0.9 * order.length).toInt(), start + 1);
  final lit = [for (final i in order.sublist(start, end)) labs[i]];
  return hairColourName(
    _median([for (final v in lit) v[0]]),
    _median([for (final v in lit) v[1]]),
    _median([for (final v in lit) v[2]]),
  );
}
