/// LoRA lineage + compatibility.
///
/// The server hosts a mixed pile of LoRAs with no manifest, and the filename
/// alone is not enough: `sexy_attire.safetensors` sounds like every other
/// SDXL character LoRA but was trained on runwayml/stable-diffusion-v1-5.
/// Loading it on an SDXL checkpoint is worse than a no-op — the UNet keys
/// don't match, while the shared CLIP-L text encoder *does*, so it perturbs
/// the prompt embedding without ever applying the trained concept (verified
/// on the server: mean 7.3/255 pixel drift, none of it the LoRA's subject).
///
/// So families are curated from each file's safetensors metadata
/// (`ss_base_model_version` / `ss_sd_model_name`, read via ComfyUI's
/// `/view_metadata/loras`), with a filename heuristic for anything not in the
/// registry. Unknown never means hidden — it means flagged.
library;

/// Lineage a LoRA was trained on. [none] is for models that take no LoRA.
enum LoraFamily { flux, sdxl, pony, illustrious, sd15, wan, zimage, unknown, none }

/// Model architecture — LoRAs only apply across the same one.
enum _LoraArch { flux, sdxl, sd15, wan, zimage, unknown }

_LoraArch _archOf(LoraFamily f) => switch (f) {
  LoraFamily.flux => _LoraArch.flux,
  // Pony and Illustrious are SDXL fine-tunes: their LoRAs load on any SDXL
  // checkpoint, they just transfer poorly across lineages.
  LoraFamily.sdxl || LoraFamily.pony || LoraFamily.illustrious =>
    _LoraArch.sdxl,
  LoraFamily.sd15 => _LoraArch.sd15,
  LoraFamily.wan => _LoraArch.wan,
  LoraFamily.zimage => _LoraArch.zimage,
  LoraFamily.unknown || LoraFamily.none => _LoraArch.unknown,
};

/// How well a LoRA fits the active model.
enum LoraFit {
  /// Same lineage — what the LoRA was trained for.
  native,

  /// Same architecture, different lineage (an Illustrious LoRA on Juggernaut):
  /// it loads and does something, usually weaker or off-style.
  weak,

  /// Family couldn't be determined — offered, but labelled.
  unknown,

  /// Different architecture: it would either no-op or corrupt the prompt.
  incompatible,
}

LoraFit loraFit(LoraFamily lora, LoraFamily model) {
  if (model == LoraFamily.none) return LoraFit.incompatible;
  if (lora == LoraFamily.unknown) return LoraFit.unknown;
  if (lora == model) return LoraFit.native;
  return _archOf(lora) == _archOf(model) ? LoraFit.weak : LoraFit.incompatible;
}

/// Human label for the picker.
String loraFamilyLabel(LoraFamily f) => switch (f) {
  LoraFamily.flux => 'FLUX',
  LoraFamily.sdxl => 'SDXL',
  LoraFamily.pony => 'Pony',
  LoraFamily.illustrious => 'Illustrious',
  LoraFamily.sd15 => 'SD 1.5',
  LoraFamily.wan => 'WAN (video)',
  LoraFamily.zimage => 'Z-Image',
  LoraFamily.unknown => 'neznámý původ',
  LoraFamily.none => '—',
};

/// Curated families, keyed by the bare filename (no folder, no extension,
/// lowercased). Each entry is what the file's own training metadata says;
/// the comment records the evidence so a later re-check is cheap.
const _knownLoras = <String, LoraFamily>{
  // ── FLUX (ss_base_model_version: flux1) ──
  'flux-female-anatomy': LoraFamily.flux,
  'flux-lora-uncensored': LoraFamily.flux,
  'flux-lora-uncensored-000004': LoraFamily.flux,
  'pussydiffusion-flux1': LoraFamily.flux,
  'lora-000013.ta_trained': LoraFamily.flux,
  // metadata claims sd_1.5 (kohya default left untouched), but it is the
  // published FLUX NSFW slider — the name wins here.
  'sldr_flux_nsfw_v2-studio': LoraFamily.flux,

  // ── Illustrious / NoobAI lineage (ss_sd_model_name) ──
  'style-anime-screencap': LoraFamily.illustrious, // Laxhar/noobai-XL-0.5
  'style-usnr-thin-paint': LoraFamily.illustrious, // illustriousXL10_v10
  'style-gothic-niji': LoraFamily.illustrious, // 889818.safetensors
  'style-illustrious-pack': LoraFamily.illustrious, // 889818.safetensors
  'pussy-sandwich-il': LoraFamily.illustrious,
  'spread-pussy-il': LoraFamily.illustrious,
  'util-stabilizer-il': LoraFamily.illustrious,

  // ── Pony (all three trained on 290640.safetensors) ──
  'starship_hulls_-_pony_r1': LoraFamily.pony,
  'spacecraft': LoraFamily.pony,
  'starship_warm_anime_old_anime': LoraFamily.pony,

  // ── Vanilla SDXL ──
  'real-pussy-lily-xl': LoraFamily.sdxl, // bigLust_v10 (SDXL)
  'dmd2_sdxl_4step_lora_fp16': LoraFamily.sdxl,
  'sdxl_lightning_8step_lora': LoraFamily.sdxl,

  // ── SD 1.5 / NAI (SD 1.x) — these must never reach an SDXL model ──
  'sexy_attire': LoraFamily.sd15, // runwayml/stable-diffusion-v1-5
  'cardoggy': LoraFamily.sd15, // deliberate_v2
  'change_clothes_to_nothing': LoraFamily.sd15,
  'spaceship': LoraFamily.sd15, // v1-5-pruned-emaonly
  'micro_shorts_v0.6': LoraFamily.sd15, // nai.ckpt
  'npm-v11t-000005': LoraFamily.sd15, // nai.ckpt
  'povfacesitting': LoraFamily.sd15, // animefull-final-pruned
  'splitsitting': LoraFamily.sd15, // animefull-final-pruned

  // ── Other architectures we host no model for ──
  'heelsup_v2_22': LoraFamily.zimage, // ss_base_model_version: zimage
};

/// Filename fallback for anything outside [_knownLoras]. Deliberately
/// conservative: a name that says nothing stays [LoraFamily.unknown] and gets
/// offered (flagged) rather than silently filtered away.
LoraFamily _guessFamily(String bare) {
  if (bare.contains('flux')) return LoraFamily.flux;
  if (bare.startsWith('wan2') || bare.contains('-wan') || bare.contains('_wan')) {
    return LoraFamily.wan;
  }
  if (bare.contains('illustrious') ||
      bare.contains('noobai') ||
      bare.contains('niji') ||
      bare.endsWith('-il') ||
      bare.endsWith('_il')) {
    return LoraFamily.illustrious;
  }
  if (bare.contains('pony')) return LoraFamily.pony;
  if (bare.contains('sd15') || bare.contains('sd_15') || bare.contains('v1-5')) {
    return LoraFamily.sd15;
  }
  if (bare.contains('sdxl') || bare.endsWith('-xl') || bare.endsWith('_xl')) {
    return LoraFamily.sdxl;
  }
  return LoraFamily.unknown;
}

/// Family of the LoRA named [name] (as the server lists it — may include a
/// subfolder, e.g. `avatar/testface.safetensors`).
LoraFamily familyOfLora(String name) {
  final bare = name
      .split('/')
      .last
      .toLowerCase()
      .replaceAll('.safetensors', '')
      .replaceAll('.ckpt', '');
  return _knownLoras[bare] ?? _guessFamily(bare);
}

LoraFit fitOfLora(String name, LoraFamily model) =>
    loraFit(familyOfLora(name), model);

/// LoRAs offerable for a model, best fit first: native lineage, then other
/// lineages of the same architecture, then unknown-origin files. Architecture
/// mismatches are dropped — they can't apply what they were trained for.
List<String> lorasForFamily(List<String> all, LoraFamily family) {
  if (family == LoraFamily.none) return const [];
  const order = [LoraFit.native, LoraFit.weak, LoraFit.unknown];
  return [
    for (final fit in order)
      ...all.where((n) => fitOfLora(n, family) == fit),
  ];
}
