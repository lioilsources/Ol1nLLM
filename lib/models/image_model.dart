import 'package:flutter/material.dart';

import 'lora_family.dart';
import 'style_preset.dart';

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
    required this.promptDialect,
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

  /// How this model reads a style's text — phrases or danbooru tags (see
  /// [StylePreset.blockFor]). Explicit, not derived from [loraFamily]:
  /// animagine-xl loads plain SDXL LoRAs but was captioned with tags. Measured
  /// in the third style wave: the anime lineages took a style from its tags
  /// far better than from the same description as phrases.
  final PromptDialect promptDialect;

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
/// flux-manga's txt2img graph. Public because it is also the one dedicated
/// (non-generic) template the service knows how to splice a depth ControlNet
/// into, which is what makes repose possible outside the SDXL family.
const kFluxMangaTxt2img = 'assets/comfyui/flux_manga_txt2img.api.json';
const _fluxMangaImg2img = 'assets/comfyui/flux_manga_img2img.api.json';
const _fluxFillInpaint = 'assets/comfyui/flux_fill_inpaint.api.json';
const _fluxFillInpaintRef = 'assets/comfyui/flux_fill_inpaint_ref.api.json';
const _fluxFillInpaintFace = 'assets/comfyui/flux_fill_inpaint_face.api.json';

const _ponyScoreTags = 'score_9, score_8_up, score_7_up, score_6_up';
const _ponyNegative =
    'score_4, score_5, score_6, bad quality, worst quality, low quality, '
    'jpeg artifacts, blurry, ugly, watermark';

/// Shared by the photoreal SDXL checkpoints, whose cards give no negative of
/// their own (Juggernaut, CyberRealistic, Lustify, SDXL base). RealVis is the
/// exception — SG161222 publishes one, so it carries its own.
const _photoNegative =
    'bad quality, worst quality, low quality, jpeg artifacts, blurry, '
    'watermark, deformed, disfigured, bad anatomy, bad hands';

/// What [ImageModelSpec.styleNote] says until a model has been through the
/// style matrix. The field is mandatory (`style_preset_test`), but it must not
/// be filled with a guess: the picker shows it where every other note is a
/// measured result, so a guess would read as one.
const _unmeasured = 'stylovou reakci zatím neměřil lab';

const kImageModels = <ImageModelSpec>[
  ImageModelSpec(
    id: 'flux-schnell',
    label: 'FLUX Schnell',
    promptDialect: PromptDialect.natural,
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
    promptDialect: PromptDialect.natural,
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
    promptDialect: PromptDialect.natural,
    icon: Icons.brush_outlined,
    color: Color(0xFF7E9CD8),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    loraFamily: LoraFamily.flux,
    styleNote:
        'pózu ze zdroje nedrží; stylů zná jen pár',
    preset: ComfyPreset(
      txt2imgAsset: kFluxMangaTxt2img,
      img2imgAsset: _fluxMangaImg2img,
    ),
  ),
  ImageModelSpec(
    id: 'flux-fill',
    label: 'FLUX Fill',
    // Inpaint only, and inpaint never gets a style — natural just keeps the
    // field honest.
    promptDialect: PromptDialect.natural,
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
    promptDialect: PromptDialect.booru,
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
    promptDialect: PromptDialect.natural,
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
      negativePrompt: _photoNegative,
      cfg: 5.0,
    ),
  ),
  ImageModelSpec(
    id: 'juggernaut-xl-lightning',
    label: 'Juggernaut XL Lightning',
    promptDialect: PromptDialect.natural,
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
      negativePrompt: _photoNegative,
      steps: 6,
      cfg: 2.0,
      samplerName: 'dpmpp_sde',
      scheduler: 'karras',
    ),
  ),
  // Fotoreal SDXL trojka. Hodnoty z karet modelů.
  ImageModelSpec(
    id: 'cyberrealistic-xl',
    label: 'CyberRealistic XL',
    promptDialect: PromptDialect.natural,
    icon: Icons.camera_alt_outlined,
    color: Color(0xFF88C0D0),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.sdxl,
    supportsPose: true,
    styleNote:
        'fotoreal SDXL, cfg 3–5 — $_unmeasured',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'CyberRealisticXL_v10.safetensors',
      negativePrompt: _photoNegative,
      // Karta: DPM++ 2M SDE Karras, 30+ kroků, cfg 3–5, VAE zapečené.
      steps: 30,
      cfg: 4.0,
      samplerName: 'dpmpp_2m_sde',
      scheduler: 'karras',
    ),
  ),
  ImageModelSpec(
    id: 'realvis-xl',
    label: 'RealVis XL V5',
    promptDialect: PromptDialect.natural,
    icon: Icons.portrait_outlined,
    color: Color(0xFFA3BE8C),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.sdxl,
    supportsPose: true,
    styleNote:
        'fotoreal SDXL, vlastní negativ autora — $_unmeasured',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'RealVisXL_V5.0.safetensors',
      // Vlastní negativ z karty SG161222 (závorkované váhy nechány tak, jak je
      // autor píše — ComfyUI je čte stejně jako A1111).
      negativePrompt:
          'bad hands, bad anatomy, ugly, deformed, (face asymmetry, '
          'eyes asymmetry, deformed eyes, deformed mouth, open mouth)',
      // Karta: DPM++ SDE Karras, 30+ kroků. cfg neudává — 5.0 jako
      // u ostatních fotoreal SDXL v registru.
      steps: 30,
      cfg: 5.0,
      samplerName: 'dpmpp_sde',
      scheduler: 'karras',
    ),
  ),
  ImageModelSpec(
    id: 'lustify-zenith',
    label: 'Lustify ZENITH',
    promptDialect: PromptDialect.natural,
    icon: Icons.local_fire_department_outlined,
    color: Color(0xFFBF616A),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.sdxl,
    supportsPose: true,
    styleNote:
        'fotoreal SDXL, jede na nízkém cfg — $_unmeasured',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'Lustify_ZENITH_V9.safetensors',
      negativePrompt: _photoNegative,
      // Karta: DPM++ 2M SDE / 3M SDE, Exponential nebo Karras, 30 kroků,
      // cfg 2.5–4.5 (ZENITH jede níž než starší verze).
      steps: 30,
      cfg: 3.5,
      samplerName: 'dpmpp_2m_sde',
      scheduler: 'karras',
    ),
  ),
  ImageModelSpec(
    id: 'illustrious-xl',
    label: 'Illustrious XL',
    promptDialect: PromptDialect.booru,
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
    promptDialect: PromptDialect.booru,
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
    promptDialect: PromptDialect.booru,
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
  ImageModelSpec(
    id: 'hassaku-illustrious',
    label: 'Hassaku XL Illustrious',
    promptDialect: PromptDialect.booru,
    icon: Icons.color_lens_outlined,
    color: Color(0xFF5E81AC),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.illustrious,
    supportsPose: true,
    styleNote:
        'anime, linie Illustrious — $_unmeasured',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'HassakuXL_Illustrious_v3.4.safetensors',
      positivePrefix: 'masterpiece, best quality, amazing quality',
      // Autor jmenovitě doporučuje `signature` do negativu — model jinak sype
      // podpisy a bubliny.
      negativePrompt:
          'bad quality, worst quality, worst detail, sketch, censored, '
          'lowres, bad anatomy, bad hands, signature, watermark',
      // Karta: Euler A, 28 kroků, cfg 4–7 (bereme 5.0 jako u ostatních
      // Illustrious v registru).
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
    promptDialect: PromptDialect.booru,
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
    promptDialect: PromptDialect.booru,
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
    id: 'autismmix-pony',
    label: 'AutismMix Pony',
    promptDialect: PromptDialect.booru,
    icon: Icons.auto_awesome_outlined,
    color: Color(0xFFD8A0DF),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.pony,
    supportsPose: true,
    styleNote:
        'anime, linie Pony — $_unmeasured',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'AutismMix_pony.safetensors',
      // Karta chce celý score řetěz (delší než sdílený _ponyScoreTags)
      // a `source_anime`.
      positivePrefix:
          'score_9, score_8_up, score_7_up, score_6_up, score_5_up, '
          'score_4_up, source_anime',
      // Záměrně NE _ponyNegative: autor píše, že score_4/5/6 v negativu
      // a pony negativní embeddingy výsledek zhoršují. Zůstává jen nutné
      // minimum.
      negativePrompt: 'worst quality, low quality, watermark, signature',
      // Karta: Euler a (nebo DPM++ 2M SDE Karras), 25–28 kroků, cfg 7.
      steps: 28,
      cfg: 7.0,
      samplerName: 'euler_ancestral',
      scheduler: 'normal',
    ),
  ),
  // Neochucený SDXL 1.0 od Stability — referenční bod, proti kterému je vidět,
  // co každý finetune výš vlastně přidává.
  ImageModelSpec(
    id: 'sdxl-base',
    label: 'SDXL base 1.0',
    promptDialect: PromptDialect.natural,
    icon: Icons.layers_outlined,
    color: Color(0xFF6E7A8A),
    kind: ImageBackendKind.comfyUi,
    txt2img: true,
    img2img: true,
    inpaint: true,
    loraFamily: LoraFamily.sdxl,
    supportsPose: true,
    styleNote:
        'neochucený základ SDXL — $_unmeasured',
    preset: ComfyPreset(
      txt2imgAsset: _sdxlTxt2img,
      img2imgAsset: _sdxlImg2img,
      inpaintAsset: _sdxlInpaint,
      inpaintRefAsset: _sdxlInpaintRef,
      ckptName: 'sd_xl_base_1.0.safetensors',
      negativePrompt: _photoNegative,
      // DPM++ 2M Karras, 25–30 kroků, cfg 7–8 (diffusers default guidance 7.5).
      // Refiner se nepoužívá — generické sdxl_* šablony mají jen base.
      steps: 30,
      cfg: 7.5,
      samplerName: 'dpmpp_2m',
      scheduler: 'karras',
    ),
  ),
  ImageModelSpec(
    id: 'sd15',
    label: 'SD 1.5',
    promptDialect: PromptDialect.natural,
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

