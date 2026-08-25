import 'package:flutter/material.dart';

import 'lora_family.dart';

export 'lora_family.dart';

/// Which service instance handles a model's requests.
enum ImageBackendKind { comfyUi, fluxNim, fluxKontextNim }

/// ComfyUI generation parameters for one model.
///
/// [ckptName] == null means the model ships dedicated workflow JSONs with all
/// values baked in (flux-manga's UNETLoader graph) — only the __PROMPT__ /
/// __IMAGE__ sentinels and batch/seed get patched. With a ckptName the model
/// runs on the generic sdxl_* templates and every field here is patched in.
class ComfyPreset {
  const ComfyPreset({
    required this.txt2imgAsset,
    required this.img2imgAsset,
    this.inpaintAsset,
    this.inpaintRefAsset,
    this.inpaintFaceAsset,
    this.ckptName,
    this.positivePrefix = '',
    this.negativePrompt = '',
    this.width = 1024,
    this.height = 1024,
    this.steps = 30,
    this.cfg = 6.0,
    this.samplerName = 'dpmpp_2m',
    this.scheduler = 'karras',
    this.img2imgDenoise = 0.72,
  });

  final String txt2imgAsset;
  final String img2imgAsset;

  /// Masked-edit workflow (null = model can't inpaint). Inpaint always runs
  /// KSampler at denoise 1.0 — the mask, not the denoise, limits the change.
  final String? inpaintAsset;

  /// Reference-guided inpaint workflow: IPAdapter transfers the reference
  /// image's appearance into the masked region (attn_mask-restricted). Null =
  /// text-only inpaint (flux-fill has no reference path — needs Redux).
  final String? inpaintRefAsset;

  /// Face-identity variant of the reference workflow: a biometric encoder
  /// (PuLID for FLUX) transfers WHO the reference face is, not just how it
  /// looks. Null = the face toggle is hidden for this model.
  final String? inpaintFaceAsset;
  final String? ckptName;
  final String positivePrefix;
  final String negativePrompt;
  final int width;
  final int height;
  final int steps;
  final double cfg;
  final String samplerName;
  final String scheduler;
  final double img2imgDenoise;
}

/// One selectable entry in the unified model picker. [id] is stable — it is
/// persisted in sessions, so never rename existing ids.
class ImageModelSpec {
  const ImageModelSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.kind,
    required this.txt2img,
    required this.img2img,
    this.inpaint = false,
    this.loraFamily = LoraFamily.none,
    this.styleNote,
    this.supportsPose = false,
    this.preset,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final ImageBackendKind kind;
  final bool txt2img;
  final bool img2img;

  /// Masked edit (inpaint) rounds apply to this model. Requires
  /// [ComfyPreset.inpaintAsset]; ComfyUI backend only.
  final bool inpaint;

  /// Whether an inpaint round can carry a reference image (IPAdapter).
  bool get inpaintRef => inpaint && preset?.inpaintRefAsset != null;

  /// Whether the reference can run in face-identity mode.
  bool get inpaintFace => inpaint && preset?.inpaintFaceAsset != null;

  /// Lineage this checkpoint's LoRAs are trained for — not just the
  /// architecture: Pony, Illustrious and vanilla SDXL all load each other's
  /// files, but only the matching lineage transfers properly (see
  /// [loraFit]). Cross-architecture files are filtered out entirely.
  final LoraFamily loraFamily;

  /// One line on how this checkpoint treats an art-style prompt — measured,
  /// not guessed (10 models × 25 styles, see `docs/style-matrix.md`). Shown in
  /// the picker, because the model's *default scene* — what it falls back to
  /// when the style doesn't land — matters more than its capability list.
  final String? styleNote;

  /// OpenPose ControlNet pose templates apply to this model. Explicit flag,
  /// not derived from ckptName: the installed ControlNet is SDXL-only, so
  /// SD 1.5 (which also runs the generic templates) must stay false.
  final bool supportsPose;

  final ComfyPreset? preset;

  String get capabilityLabel {
    final caps = [
      if (txt2img) 'txt2img',
      if (img2img) 'img2img',
      if (inpaint) 'inpaint',
    ];
    return caps.join(' + ');
  }
}

const kDefaultImageModelId = 'flux-manga';

/// LoRA strength applied to both model and clip. The default matches what the
/// service used before the control existed, so behaviour is unchanged until
/// the user moves the slider. Negative values are allowed on purpose: slider
/// LoRAs are trained as a direction, and below zero they push the other way.
const kDefaultLoraStrength = 0.9;
const kMinLoraStrength = -1.0;
const kMaxLoraStrength = 1.5;

const _sdxlTxt2img = 'assets/comfyui/sdxl_txt2img.api.json';
const _sdxlImg2img = 'assets/comfyui/sdxl_img2img.api.json';
const _sdxlInpaint = 'assets/comfyui/sdxl_inpaint.api.json';
const _sdxlInpaintRef = 'assets/comfyui/sdxl_inpaint_ref.api.json';
const _fluxFillInpaint = 'assets/comfyui/flux_fill_inpaint.api.json';
const _fluxFillInpaintRef = 'assets/comfyui/flux_fill_inpaint_ref.api.json';
const _fluxFillInpaintFace = 'assets/comfyui/flux_fill_inpaint_face.api.json';

const _ponyScoreTags = 'score_9, score_8_up, score_7_up, score_6_up';
const _ponyNegative =
    'score_4, score_5, score_6, bad quality, worst quality, low quality, '
    'jpeg artifacts, blurry, ugly, watermark';

const kImageModels = <ImageModelSpec>[
  ImageModelSpec(
    id: 'flux-schnell',
    label: 'FLUX Schnell',
    icon: Icons.bolt,
    color: Color(0xFF10A37F),
    kind: ImageBackendKind.fluxNim,
    txt2img: true,
    img2img: false,
    styleNote:
        'rychlé txt2img, styl drží slušně',
  ),
  ImageModelSpec(
    id: 'flux-kontext',
    label: 'FLUX Kontext',
    icon: Icons.auto_fix_high,
    color: Colors.orange,
    kind: ImageBackendKind.fluxKontextNim,
    txt2img: false,
    img2img: true,
    styleNote:
        'instrukční editace — pózu ze zdroje nedrží',
  ),
  ImageModelSpec(
    id: 'flux-manga',
    label: 'FLUX manga',
    icon: Icons.brush_outlined,
    color: Color(0xFF7E9CD8),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    loraFamily: LoraFamily.flux,
    styleNote:
        'buď převezme médium naplno, nebo vůbec — pózu nedrží',
    preset: ComfyPreset(
      txt2imgAsset: 'assets/comfyui/flux_manga_txt2img.api.json',
      img2imgAsset: 'assets/comfyui/flux_manga_img2img.api.json',
    ),
  ),
  ImageModelSpec(
    id: 'flux-fill',
    label: 'FLUX Fill',
    icon: Icons.format_color_fill,
    color: Color(0xFFD19A66),
    kind: ImageBackendKind.comfyUi,
    txt2img: false,
    img2img: false,
    inpaint: true,
    // Dedicated inpaint-only workflow (UNETLoader graph, values baked in).
    // txt2img/img2img assets are never used (both flags false) — the field
    // type requires them, so they point at the same file.
    styleNote:
        'jen inpaint — styl řeší prompt zamalované oblasti',
    preset: ComfyPreset(
      txt2imgAsset: _fluxFillInpaint,
      img2imgAsset: _fluxFillInpaint,
      inpaintAsset: _fluxFillInpaint,
      // Redux (SigLIP + style model) — reference-guided fill.
      inpaintRefAsset: _fluxFillInpaintRef,
      // PuLID (InsightFace + EVA-CLIP) — identity-preserving face reference.
      inpaintFaceAsset: _fluxFillInpaintFace,
    ),
  ),
  ImageModelSpec(
    id: 'pony',
    label: 'Pony V6',
    icon: Icons.palette_outlined,
    color: Color(0xFFC678DD),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.pony,
    supportsPose: true,
    styleNote:
        'vlastní malovaná estetika, historické styly skoro nepřejímá',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'ponyDiffusionV6XL_v6StartWithThisOne.safetensors',
      positivePrefix: _ponyScoreTags,
      negativePrompt: _ponyNegative,
    ),
  ),
  ImageModelSpec(
    id: 'juggernaut-xl',
    label: 'Juggernaut XL',
    icon: Icons.photo_camera_outlined,
    color: Color(0xFFE5C07B),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.sdxl,
    supportsPose: true,
    styleNote:
        'nejširší stylový rozsah; styl inscenuje jako kostým a kulisu',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors',
      negativePrompt:
          'bad quality, worst quality, low quality, jpeg artifacts, blurry, '
          'watermark, deformed, disfigured, bad anatomy, bad hands',
      cfg: 5.0,
    ),
  ),
  ImageModelSpec(
    id: 'juggernaut-xl-lightning',
    label: 'Juggernaut XL Lightning',
    icon: Icons.speed,
    color: Color(0xFF56B6C2),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.sdxl,
    supportsPose: true,
    // Distilled 4-step checkpoint: RunDiffusion's own guidance is 4–6 steps at
    // cfg 1.5–2. 6 steps keeps img2img usable (denoise 0.72 ⇒ ~4 real steps)
    // and cfg 2.0 is the top of the range, where the negative still bites —
    // at cfg 1 it would be ignored outright.
    styleNote:
        '6 kroků, skoro stejný rozsah jako Juggernaut XL',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'Juggernaut-XL-Lightning_4Steps.safetensors',
      negativePrompt:
          'bad quality, worst quality, low quality, jpeg artifacts, blurry, '
          'watermark, deformed, disfigured, bad anatomy, bad hands',
      steps: 6,
      cfg: 2.0,
      samplerName: 'dpmpp_sde',
      scheduler: 'karras',
    ),
  ),
  ImageModelSpec(
    id: 'illustrious-xl',
    label: 'Illustrious XL',
    icon: Icons.draw_outlined,
    color: Color(0xFF61AFEF),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.illustrious,
    supportsPose: true,
    styleNote:
        'styl řeší dekorativním rámem, postava zůstane ilustrací',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'Illustrious-XL-v2.0.safetensors',
      positivePrefix: 'masterpiece, best quality',
      negativePrompt:
          'lowres, bad anatomy, bad hands, worst quality, low quality, '
          'jpeg artifacts, blurry, watermark, signature',
      steps: 28,
      samplerName: 'euler_ancestral',
      scheduler: 'normal',
    ),
  ),
  // NoobAI is Illustrious dotrénovaný na danbooru + e621: stejná gramatika
  // promptů, ale výrazně širší znalost postav a konceptů. Záměrně eps-pred
  // varianta — v-pred verze potřebují ModelSamplingDiscrete, který generické
  // sdxl_* šablony nemají.
  ImageModelSpec(
    id: 'noobai-xl',
    label: 'NoobAI XL',
    icon: Icons.diversity_2_outlined,
    color: Color(0xFF8FBCBB),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.illustrious,
    supportsPose: true,
    styleNote:
        'pastelové jeviště; spolehlivě jen ukiyo-e, tuš, Art Nouveau',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'noobai-xl-eps11.safetensors',
      positivePrefix: 'masterpiece, best quality, very awa',
      negativePrompt:
          'lowres, bad anatomy, bad hands, worst quality, low quality, '
          'jpeg artifacts, blurry, watermark, signature',
      steps: 28,
      samplerName: 'euler_ancestral',
      scheduler: 'normal',
    ),
  ),
  ImageModelSpec(
    id: 'wai-illustrious',
    label: 'WAI Illustrious',
    icon: Icons.auto_fix_normal_outlined,
    color: Color(0xFFB48EAD),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.illustrious,
    supportsPose: true,
    styleNote:
        'silný vlastní rukopis — krémové jeviště přebije zadaný styl',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'wai-nsfw-illustrious.safetensors',
      positivePrefix: 'masterpiece, best quality, amazing quality',
      negativePrompt:
          'bad quality, worst quality, worst detail, sketch, censored, '
          'lowres, bad anatomy, bad hands, watermark, signature',
      steps: 28,
      cfg: 5.0,
      samplerName: 'euler_ancestral',
      scheduler: 'normal',
    ),
  ),
  // Přímý SDXL finetune (ne Illustrious rodina) — jiná gramatika promptů
  // a čistší "oficiální" anime look; drží se kvůli stylovému kontrastu.
  ImageModelSpec(
    id: 'animagine-xl',
    label: 'Animagine XL 4',
    icon: Icons.brush,
    color: Color(0xFFEBCB8B),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.sdxl,  // anime-tuned SDXL, not Illustrious lineage
    supportsPose: true,
    styleNote:
        'teplé protisvětlo; výborně tuš, ukiyo-e, Art Nouveau, Egypt',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'animagine-xl-40-opt.safetensors',
      positivePrefix: 'masterpiece, high score, great score, absurdres',
      negativePrompt:
          'lowres, bad anatomy, bad hands, text, error, missing finger, '
          'extra digits, fewer digits, cropped, worst quality, low quality, '
          'jpeg artifacts, watermark, signature',
      steps: 28,
      cfg: 5.0,
      samplerName: 'euler_ancestral',
      scheduler: 'normal',
    ),
  ),
  ImageModelSpec(
    id: 'atomix-pony-anime',
    label: 'Atomix Pony Anime',
    icon: Icons.animation,
    color: Color(0xFFE06C75),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.pony,
    supportsPose: true,
    styleNote:
        'měkká anime ilustrace, styl přes kostým a paletu',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'atomixPonyAnimeXL_v30.safetensors',
      positivePrefix: _ponyScoreTags,
      negativePrompt: _ponyNegative,
      steps: 28,
      cfg: 6.5,
      samplerName: 'euler_ancestral',
      scheduler: 'normal',
    ),
  ),
  ImageModelSpec(
    id: 'sd15',
    label: 'SD 1.5',
    icon: Icons.history_edu_outlined,
    color: Color(0xFF98C379),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    styleNote:
        'styl nepřejímá, 512×512',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      ckptName: 'v1-5-pruned-emaonly-fp16.safetensors',
      negativePrompt: 'bad quality, worst quality, blurry, watermark',
      width: 512,
      height: 512,
      steps: 25,
      cfg: 7.0,
      img2imgDenoise: 0.70,
    ),
  ),
];

/// Lookup by persisted id, falling back to the default model so sessions
/// written by future/older builds still open.
ImageModelSpec imageModelById(String id) => kImageModels.firstWhere(
  (m) => m.id == id,
  orElse: () =>
      kImageModels.firstWhere((m) => m.id == kDefaultImageModelId),
);

/// The subset of [kImageModels] the server can actually run: a ComfyUI entry
/// whose checkpoint is not installed is dropped, so the picker never offers a
/// model that would fail at enqueue time. Presets stay curated in Dart — a new
/// checkpoint on the server shows up only once it gets an [ImageModelSpec]
/// here, because the filename alone says nothing about sampler/steps/cfg.
///
/// An empty [installedCheckpoints] means the list is unknown (offline, or the
/// fetch failed) — then everything stays visible, i.e. the pre-fetch behaviour.
/// [keepId] is never filtered out, so a session restored with a since-removed
/// model still shows its own entry as the selected one.
List<ImageModelSpec> imageModelsFor(
  List<String> installedCheckpoints, {
  String? keepId,
}) {
  if (installedCheckpoints.isEmpty) return kImageModels;
  final installed = installedCheckpoints.toSet();
  return [
    for (final m in kImageModels)
      // preset == null (NIM) and ckptName == null (flux-manga's UNETLoader
      // graph) load no checkpoint, so nothing to check.
      if (m.id == keepId ||
          m.preset?.ckptName == null ||
          installed.contains(m.preset!.ckptName))
        m,
  ];
}

