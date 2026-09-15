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

export 'hairstyle_catalog.dart' show kHairstyles, kHairColours;

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

  /// Bundled preview: the bench's own output for this style on the group's
  /// primary synthetic portrait (export_catalog.py --bench). Same face under
  /// every style, so the sheet compares hair and nothing else.
  String get preview => 'assets/hair/$id.jpg';
}

/// A hair colour (MangaPrompts `tgbot/haircolours.py`). The app writes its own
/// prompt, so it carries the phrase, not just the id.
class HairColourPreset {
  const HairColourPreset({
    required this.id,
    required this.label,
    required this.phrase,
    this.swatch,
  });

  final String id;
  final String label;
  final String phrase;

  /// ARGB of the colour the bench *measured* on the accepted cells — what the
  /// model paints, not the target range. Null while unmeasured.
  final int? swatch;
}

/// "Same haircut, new colour" (`haircolours.KEEP_CUT`).
const kKeepCutId = 'keep-cut';
const kKeepCutPreset = HairstylePreset(
  id: kKeepCutId,
  label: 'Stejný střih',
  group: kHairGroupWomen,
  section: '',
  block: 'the same haircut as in the photo',
  shape: HairShape(length: HairLength.keep),
);

HairColourPreset? hairColourById(String? id) {
  if (id == null) return null;
  for (final c in kHairColours) {
    if (c.id == id) return c;
  }
  return null;
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
    'nude, naked, nsfw, hat, cap, helmet, headband, deformed hair, '
    'floating hair, extra face, second person, blurry, watermark, low quality';

/// [instruction] = FLUX Kontext ("change X, keep Y"); otherwise a description
/// of the finished photo (SDXL inpaint). [newColour] replaces the colour read
/// off the photo; with [kKeepCutPreset] only the colour changes.
String hairPrompt(
  HairstylePreset s,
  String? colour, {
  bool instruction = false,
  HairColourPreset? newColour,
}) {
  final keepCut = s.id == kKeepCutId;
  final c = colour ?? 'natural';
  final target = newColour?.phrase;
  final clause = keepCut ? '' : hairLengthClause(s);
  if (instruction) {
    final length = clause.isEmpty
        ? ''
        : '${clause[0].toUpperCase()}${clause.substring(1)}. ';
    final lead = keepCut
        ? "Change the person's hair colour to $target. Keep the haircut, length and hair texture."
        : "Change the person's hairstyle to a ${s.block}. $length"
            '${target != null ? 'Dye the hair $target.' : 'Keep the $c hair colour.'}';
    return '$lead Keep the face, facial features, expression, skin, clothes, lighting and '
        'background exactly the same.';
  }
  final hair = '${target ?? c} hair';
  if (keepCut) {
    return 'a photo of the same person with the same haircut as in the photo, $hair, '
        'natural hair texture, realistic strands, same clothes, same lighting and background, '
        'photorealistic';
  }
  final length = clause.isEmpty ? '' : '$clause, ';
  return 'a photo of the same person with a ${s.block}, $length$hair, natural hair texture, '
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
