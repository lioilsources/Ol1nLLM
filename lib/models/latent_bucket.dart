import 'dart:math' show log;
import 'dart:typed_data';

import 'package:image/image.dart' show JpegDecoder, PngDecoder;

/// Latent dimensions for an SDXL generic-template round.
typedef LatentSize = ({int w, int h});

/// Standard SDXL training buckets (≈1 MP, multiples of 64). Generating in
/// the bucket closest to a reference's aspect keeps a depth/pose hint from
/// being center-cropped by ControlNetApplyAdvanced.
const kSdxlBuckets = <LatentSize>[
  (w: 1024, h: 1024),
  (w: 896, h: 1152),
  (w: 1152, h: 896),
  (w: 832, h: 1216),
  (w: 1216, h: 832),
  (w: 768, h: 1344),
  (w: 1344, h: 768),
];

/// Closest bucket by aspect ratio, compared in log space so portrait and
/// landscape deviations weigh the same (2:3 vs 3:2 are symmetric). Ties
/// resolve to the earlier entry in [kSdxlBuckets].
LatentSize snapToSdxlBucket(int width, int height) {
  if (width <= 0 || height <= 0) return kSdxlBuckets.first;
  final target = log(width / height);
  var best = kSdxlBuckets.first;
  var bestDist = double.infinity;
  for (final b in kSdxlBuckets) {
    final d = (log(b.w / b.h) - target).abs();
    if (d < bestDist) {
      bestDist = d;
      best = b;
    }
  }
  return best;
}

/// Pixel size read from the PNG or JPEG header only — no pixel decode, so
/// it's cheap enough to run on the UI isolate for a ~1 MP reference. Both
/// formats are tried because photo roots from image_picker are JPEG bytes
/// stored under a `.png` name. Null when the bytes are neither / truncated.
LatentSize? decodeImageSize(Uint8List bytes) {
  try {
    final info =
        PngDecoder().startDecode(bytes) ?? JpegDecoder().startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) return null;
    return (w: info.width, h: info.height);
  } catch (_) {
    return null;
  }
}

/// Latent bucket for a repose round: the reference's aspect, snapped to
/// [kSdxlBuckets]. [fallback] (the preset's default size) is used when the
/// reference header can't be read.
LatentSize reposeLatentFor(
  Uint8List reference, {
  required LatentSize fallback,
}) {
  final s = decodeImageSize(reference) ?? fallback;
  return snapToSdxlBucket(s.w, s.h);
}
