// Kadeřník: hairstyles for the Image Studio tile action.
//
// The same catalog as Tsumiki's Hairdresser card — ids, blocks and shapes come
// from MangaPrompts `tgbot/tools/bench/candidates/hairstyles.json` and only the
// styles that passed the bench gate on both engines are exported here
// (`export_catalog.py --ol1nllm`, verdicts in MangaPrompts/docs/hair-matrix.md).
// Labels are Czech, like the rest of this app.

import 'hair_mask.dart';
import 'hairstyle_catalog.dart';
import 'style_preset.dart' show foldDiacritics;

export 'hairstyle_catalog.dart' show kHairstyles;

const kHairGroupWomen = 'Ženy';
const kHairGroupMen = 'Muži';
const kHairGroups = [kHairGroupWomen, kHairGroupMen];

class HairstylePreset {
  const HairstylePreset({
    required this.id,
    required this.label,
    required this.group,
    required this.section,
    required this.block,
    required this.shape,
  });

  final String id;
  final String label;
  final String group;
  final String section;

  /// English prompt fragment (name + look), shown as the subtitle.
  final String block;
  final HairShape shape;
}

/// Mirror of MangaPrompts `tgbot/hairprompt.py` — the bot writes the Tsumiki
/// prompt server-side; this app talks to ComfyUI directly and writes it here.
String hairLengthClause(HairstylePreset s) {
  if (s.shape.updo) {
    return s.id == 'half-up'
        ? ''
        : 'all hair gathered up and away from the neck and shoulders';
  }
  return switch (s.shape.length) {
    HairLength.short =>
      'short hair ending above the jaw with the neck clear of hair',
    HairLength.medium => 'hair ending between the chin and the shoulders',
    HairLength.long => 'long hair falling past the shoulders',
    HairLength.keep => '',
  };
}

const kHairNegative =
    'hat, cap, helmet, headband, deformed hair, floating hair, '
    'extra face, second person, blurry, watermark, low quality';

/// [instruction] = FLUX Kontext ("change X, keep Y"); otherwise a description
/// of the finished photo (SDXL inpaint).
String hairPrompt(
  HairstylePreset s,
  String? colour, {
  bool instruction = false,
}) {
  final c = colour ?? 'natural';
  final clause = hairLengthClause(s);
  if (instruction) {
    final length = clause.isEmpty
        ? ''
        : '${clause[0].toUpperCase()}${clause.substring(1)}. ';
    return "Change the person's hairstyle to a ${s.block}. ${length}Keep the $c hair colour. "
        'Keep the face, facial features, expression, skin, clothes, lighting and background '
        'exactly the same.';
  }
  final length = clause.isEmpty ? '' : '$clause, ';
  return 'a photo of the same person with a ${s.block}, $length$c hair, natural hair texture, '
      'realistic strands, same clothes, same lighting and background, photorealistic';
}

HairstylePreset? hairstyleById(String? id) {
  if (id == null) return null;
  for (final s in kHairstyles) {
    if (s.id == id) return s;
  }
  return null;
}

/// Search without diacritics over the label and the English block.
bool hairstyleMatchesQuery(HairstylePreset s, String query) {
  final q = foldDiacritics(query.trim());
  if (q.isEmpty) return true;
  return foldDiacritics(s.label).contains(q) ||
      s.block.toLowerCase().contains(q);
}
