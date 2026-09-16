// Kadeřník: hairstyles for the Image Studio tile action.
//
// The same catalog as Tsumiki's Hairdresser card — ids, blocks and shapes come
// from MangaPrompts `tgbot/tools/bench/candidates/hairstyles.json` and every
// style that passed the bench gate on *either* engine is exported here, with
// [HairstylePreset.engines] saying which (`export_catalog.py --ol1nllm`,
// verdicts in MangaPrompts/docs/hair-matrix.md).
// Labels are Czech, like the rest of this app.

import 'hair_mask.dart';
import 'hairstyle_catalog.dart';
import 'image_model.dart';
import 'style_preset.dart' show foldDiacritics;

export 'hairstyle_catalog.dart' show kHairstyles, kHairColours;

/// Which engine the bench measured a catalog entry on.
///
/// The gate is per engine, and the two disagree in both directions: Kontext
/// keeps platinum blonde platinum where SDXL paints it brown (`colour_ok 0%`),
/// while SDXL keeps a lob or a pixie recognisable where Kontext loses it
/// (`recognised 33%`). Demanding both would throw away 20 measured, passing
/// entries — most of the everyday haircuts.
enum HairEngine {
  /// FLUX presets — `flux_hair_kontext.api.json`, instruction-style prompts.
  kontext,

  /// SDXL inpaint through the preset's `inpaintAsset`.
  sdxl,
}

/// The model each engine was measured on: the bench ran Kontext through
/// flux-fill's graph and SDXL on `Juggernaut-XL_v9_RunDiffusionPhoto_v2`. Those
/// two are therefore the models the Kadeřník runs on. Another SDXL checkpoint
/// renders the same graph, but no verdict covers it — and a catalog is only as
/// true as the model underneath it.
const kHairEngineModel = <HairEngine, String>{
  HairEngine.kontext: 'flux-fill',
  HairEngine.sdxl: 'juggernaut-xl',
};

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
    this.engines = HairEngine.values,
  });

  final String id;
  final String label;
  final String group;
  final String section;

  /// Engines whose gate accepted this style. Never empty — an entry that
  /// passed nowhere is not exported at all.
  final List<HairEngine> engines;

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
    this.engines = HairEngine.values,
  });

  final String id;
  final String label;
  final String phrase;

  /// Engines whose gate accepted this colour — see [HairstylePreset.engines].
  final List<HairEngine> engines;

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

/// What a Kadeřník request will actually run on.
typedef HairPlan = ({String modelId, HairEngine engine, String? note});

/// Pick the engine from the **style**, then the model from the engine — never
/// the other way round.
///
/// With the model deciding, a style measured only on SDXL would be reachable
/// by accident (whatever the user last generated with) and invisible
/// otherwise; the user picks a haircut, not a checkpoint.
///
/// [colour] narrows the choice further when it passed on only one engine.
/// When style and colour share no engine the **style wins** and [HairPlan.note]
/// says so: refusing a plausible request (a blond lob — blonde passes only on
/// Kontext, a lob only on SDXL) would be worse than running it with a caveat,
/// and the gate's job is to tell the truth, not to forbid.
///
/// Keeps [currentModelId] when it is already one of the two measured models,
/// so a style that passed everywhere doesn't shuffle the picker for nothing.
/// Null = the server has neither engine's model.
HairPlan? planHairRun({
  required List<ImageModelSpec> available,
  required String currentModelId,
  required HairstylePreset style,
  HairColourPreset? colour,
}) {
  bool installed(HairEngine e) => available.any(
    (m) =>
        m.id == kHairEngineModel[e] &&
        m.inpaint &&
        m.kind == ImageBackendKind.comfyUi,
  );

  final wanted = [
    for (final e in HairEngine.values)
      if (style.engines.contains(e)) e,
  ];
  final shared = colour == null
      ? wanted
      : [
          for (final e in wanted)
            if (colour.engines.contains(e)) e,
        ];
  final usable = [
    for (final e in (shared.isEmpty ? wanted : shared))
      if (installed(e)) e,
  ];
  if (usable.isEmpty) return null;
  var engine = usable.first;
  for (final e in usable) {
    if (kHairEngineModel[e] == currentModelId) engine = e;
  }
  return (
    modelId: kHairEngineModel[engine]!,
    engine: engine,
    note: shared.isEmpty && colour != null
        ? '${colour.label} není na tomhle enginu změřená — barva může vyjít jinak.'
        : null,
  );
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
