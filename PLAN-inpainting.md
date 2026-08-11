# PLAN — Inpainting v Image Studiu

Cíl: uživatel v galerii otevře obrázek, zamaluje oblast, napíše prompt a dostane
varianty s přemalovanou pouze maskovanou oblastí. Dvě serverové cesty:

| Cesta | Model | Kdy |
|---|---|---|
| **FLUX Fill** | `flux1-fill-dev-fp8.safetensors` (diffusion_models) | fotorealismus, velké oblasti, nejlepší kvalita |
| **Fooocus patch** | libovolný SDXL checkpoint + `inpaint_v26.fooocus.patch` | anime/Pony/Illustrious styly, konzistence se stylem session |

Server (SPARK): modely staženy, `comfyui-inpaint-nodes` naklonované (2026-08-11).
MangaPrompts: mimo scope tohoto plánu.

---

## 1. Workflow assety (server-side kontrakt)

### `assets/comfyui/flux_fill_inpaint.api.json`

Odvozen z `flux_manga_img2img.api.json` — stejné loadery (DualCLIP `t5xxl_fp16` +
`clip_l`, VAE `ae.safetensors`), jiný UNET a conditioning:

```
UNETLoader(flux1-fill-dev-fp8, fp8_e4m3fn)
LoadImage(__IMAGE__) ──┬── InpaintModelConditioning(noise_mask=true)
LoadImage(__MASK__) ── ImageToMask(red) ──┘   ├─ positive ← FluxGuidance(30.0) ← CLIPTextEncode(__PROMPT__)
                                              ├─ negative ← CLIPTextEncode("")
KSampler(cfg=1.0, euler/simple, steps=28, denoise=1.0)
  ← model, ← conditioning+latent z InpaintModelConditioning
VAEDecode → SaveImage
```

Pozn.: FluxGuidance **30.0** (doporučení BFL pro Fill; dev má 3.5).
**Batch OVĚŘENĚ FUNGUJE** (M1 test 2026-08-11): `RepeatLatentBatch` za
`InpaintModelConditioning.latent` — noise_mask (batch 1) se přes batch
broadcastuje. Žádná sekvenční smyčka není potřeba.

### `assets/comfyui/sdxl_inpaint.api.json`

Generická šablona (sentinely `__CKPT__`, `__PROMPT__`, `__NEGATIVE__`,
`__IMAGE__`, `__MASK__`) pro všechny SDXL modely:

```
CheckpointLoaderSimple(__CKPT__)
INPAINT_LoadFooocusInpaint(fooocus_inpaint_head.pth, inpaint_v26.fooocus.patch)
INPAINT_ApplyFooocusInpaint(model, patch, latent)
LoadImage(__IMAGE__) ──┬── VAEEncodeForInpaint(grow_mask_by=16)
LoadImage(__MASK__) ── ImageToMask(red) ──┘
KSampler(denoise=1.0, preset sampler/steps/cfg modelu)
VAEDecode → ImageCompositeMasked(zdroj, výsledek, maska) → SaveImage
```

`ImageCompositeMasked` vrací pixely mimo masku 1:1 ze zdroje (VAE roundtrip
jinak lehce degraduje celý obrázek). **Pozor (M1 zjištění):**
`INPAINT_ApplyFooocusInpaint.latent` musí brát **nebatchovaný** latent přímo
z `VAEEncodeForInpaint` (`["5",0]`), ne z RepeatLatentBatch — jinak tensor
mismatch (noise_mask batch 1 vs samples batch N). KSampler batchovaný latent
z `["6",0]` bere normálně.

**Maska = samostatný PNG**: bílá (255) = přemalovat, černá = zachovat, stejné
rozlišení jako zdroj. Nahrává se druhým `/upload/image`, žádný alpha-channel
trik (LoadImage alpha inverze je zrádná a needitovatelná v Comfy UI ručně).

**Test bez appky** (před jakýmkoli Dart kódem):
```bash
curl -X POST http://spark-99bb:8188/upload/image -F image=@zdroj.png
curl -X POST http://spark-99bb:8188/upload/image -F image=@maska.png
python3 patch_and_queue.py flux_fill_inpaint.api.json  # sed sentinelů + POST /prompt
```

## 2. Datový model

- **`image_model.dart`**
  - `ComfyPreset.inpaintAsset` (`String?`) — cesta k inpaint šabloně
  - `ImageModelSpec.inpaint` (`bool`, default false) + rozšířit `capabilityLabel`
  - nový spec **`flux-fill`** (kind: comfyUi, ckptName: null, jen inpaint:
    txt2img=false, img2img=false, inpaint=true) — vlastní workflow s bakenými
    hodnotami jako flux-manga
  - SDXL modely (pony, juggernaut ×2, illustrious, atomix, sd15**¹**): přidat
    `inpaintAsset: _sdxlInpaint`, `inpaint: true`
  - **¹** sd15: Fooocus patch je SDXL-only → sd15 zůstává `inpaint: false`
- **`gen_node.dart`** — `GenNode.maskPath` (`String?`): PNG masky uložený vedle
  obrázků session (reprodukovatelnost + „upravit masku a zkusit znovu").
  Hive: nové nullable pole, staré nody čtou jako null — bez migrace.

## 3. Backend vrstva

- **`image_backend.dart`** — `edit()` dostane `Uint8List? mask` (named,
  default null). Nová metoda ne — provider má kolem `edit()` retry/follow
  logiku, kterou by `inpaint()` duplikoval.
- **`comfyui_service.dart`**
  - `edit(mask: …)`: upload masky (`_uploadImage` už umí filename param),
    `__MASK__` sentinel do patcheru (vedle `__IMAGE__`, ř. ~743)
  - výběr assetu: `mask != null ? preset.inpaintAsset : preset.img2imgAsset`
  - flux-fill varianty: batch funguje nativně (viz §1); `variantCount` pro
    flux-fill zvážit 2 kvůli času (~42 s/obrázek vs ~13 s Pony)
  - LoRA injekce (`__lora__`) funguje beze změny pro SDXL cestu; pro
    flux-fill ji **vypnout** (UNETLoader graf ji sice unese, ale Fill +
    style-LoRA dává artefakty — ověřit až v M4, do té doby ban)
- **`flux_nim_service.dart` / `flux_kontext_nim_service.dart`** — `mask` param
  přijmou a **ignorují s assertem** (NIM API masku neumí; UI je tam nenabídne)

## 4. Provider (`image_studio_provider.dart`)

- Nová akce `inpaint(nodeId, imageIndex, maskPng, prompt)`:
  1. ulož masku do session storage → `maskPath`
  2. seed = `_newSeed()` (stejně jako refine)
  3. `_backend.edit(image: …, mask: …, prompt: efektivní)`
  4. nový `GenNode` jako dítě zdrojového (stejný strom jako refine)
- **Prompt chaining vypnout**: `_chainedPrompt()` se pro inpaint NEvolá —
  prompt popisuje jen maskovanou oblast; zděděné celoobrázkové tokeny táhnou
  výsledek mimo. Efektivní prompt = jen text uživatele (+ `positivePrefix`
  modelu).
- Model pro inpaint kolo: aktuální model, pokud `inpaint: true`; jinak UI
  nabídne přepnutí (flux-fill jako default fallback).

## 5. UI

- **`mask_editor_screen.dart`** (nová): fullscreen obrázek,
  `CustomPainter` overlay (semi-transparentní červená), gesta:
  - štětec / guma, slider velikosti (px vůči zdrojovému rozlišení)
  - undo (stack tahů), clear
  - export: `ui.PictureRecorder` → PNG v rozlišení zdroje, bílá/černá
- **Vstupní bod**: viewer obrázku v galerii → nová akce „Inpaint" vedle
  „Refine". Po potvrzení masky prompt sheet (stejný jako refine, bez chain
  preview).
- **Indikace v stromu**: node s `maskPath` zobrazí badge (ikona masky);
  tap na badge → náhled masky.

## 6. Pořadí prací + testy

| Milník | Obsah | Ověření |
|---|---|---|
| **M1** ✅ 2026-08-11 | workflow JSONy + curl test na SPARKu | HOTOVO: Fill batch 2 za 84 s (mimo masku max diff 54/765, VAE šum, 0,3 % vzorků); Pony+Fooocus batch 2 za 27 s (mimo masku **0** rozdílných px). Kvalita Fill výborná i na syntetickém vstupu; Fooocus na plochém syntetiku generuje fotorealistickou texturu (čekané — ověřit na reálných obrázcích v M4) |
| **M2** ✅ 2026-08-11 | datový model + backend (`mask` param, sentinel, upload) | HOTOVO: `test/inpaint_prepare_test.dart` (6 testů — sentinely, denoise 1.0 override, batch na obou Repeat nodech, nebatchovaný latent pro Fooocus, LoRA ban pro Fill / povolená pro SDXL); celá suita 56/56 |
| **M3** ✅ 2026-08-11 | provider akce + persistence masky | HOTOVO (kód): `inpaint()` bez chainingu, `GenNode.maskFileName`, retry masku re-sendí a guarduje nekompatibilní model; ověření na zařízení spadá do M4 |
| **M4** 🔶 2026-08-11 | mask editor UI + galerie entry point | KÓD HOTOV (analyze čistý, suita 56/56): `mask_editor_screen.dart` (štětec/guma/undo/clear, velikost, export v rozlišení zdroje, prompt sheet), ikona na dlaždici + model-switch sheet, badge s náhledem masky ve stromu. **ZBÝVÁ manuální ověření na zařízení**: iPhone + Android, malá maska (oči) i velká (pozadí); flux-fill i pony |
| **M5** | LoRA × flux-fill experiment, `variantCount` tuning | rozhodnout ban/allow LoRA pro Fill |

Nezávislosti: M1 nemá závislost na Dartu; M2+M3 lze proti hotovému M1; M4
paralelně s M3 (editor nepotřebuje backend).

## UX pozn. (2026-08-11)

flux-fill je v pickeru **neaktivní** s hintem „spustíš ikonou ✨ na obrázku" —
manuální výběr vedl do slepé uličky (model neumí txt2img ani img2img, input
bar s ním nemá co dělat). Když je Fill aktivní po ✨ kole a uživatel píše do
input baru, snackbar ho navede na ✨ flow.

**Volba inpaint modelu žije v prompt sheetu mask editoru** (ChoiceChip řada:
FLUX Fill + SDXL modely; předvybraný je aktivní model session, jinak Fill).
Původní verze nabízela přepnutí jen když aktivní model inpaint neuměl — Fill
tak nešel zvolit vůbec, když byl aktivní třeba Pony. Zvolený model se před
spuštěním kola stane aktivním (metadata, retry i guard ho vidí konzistentně).
Ref picker reaguje na zvolený model (`inpaintRef`); přepnutí na model bez
reference vybranou referenci zahodí.

## M6 — reference-guided inpaint ✅ 2026-08-11 (kód; zařízení viz M4)

Uživatelské očekávání z testování: „vložím obrázek toho, čím se má maska
přemalovat". HOTOVO přes **SDXL + IPAdapter** (bez stahování):

- `assets/comfyui/sdxl_inpaint_ref.api.json` — IPAdapterUnifiedLoader (PLUS)
  → IPAdapterAdvanced (weight 0.85, end_at 0.9, **attn_mask = inpaint maska**,
  jinak reference prosakuje do celého obrázku) → Fooocus patch → KSampler.
  Server test: pruhy+barvy z reference prokazatelně přeneseny do masky
  (prompt barvy neuváděl), mimo masku 0 px, 33 s/batch 2.
- `__REF__` sentinel; `ComfyPreset.inpaintRefAsset` (5× SDXL);
  `ImageModelSpec.inpaintRef` getter; `edit(refImage:)`;
  `GenNode.refFileName` (persistence + retry).
- UI: prompt sheet v mask editoru má „Přidat referenci" (galerie) —
  jen u modelů s `inpaintRef` (Fill ho nemá).

**FLUX Fill + Redux** ✅ 2026-08-11: staženo `flux1-redux-dev.safetensors`
(129 MB, style_models; mirror Runware — oficiální BFL repo je gated) +
`sigclip_vision_patch14_384.safetensors` (857 MB, clip_vision; Comfy-Org).
`flux_fill_inpaint_ref.api.json`: CLIPVisionEncode(ref) → StyleModelApply
(strength 0.8/multiply) mezi text encode a FluxGuidance. Server test: vzhled
reference přenesen A styl zdroje zachován — kvalitativně nejlepší výsledek
(93 s/batch 2, mimo masku jen VAE šum). flux-fill má `inpaintRefAsset`
→ ref picker se u něj v UI zobrazuje automaticky.

## Crop & stitch — oprava neostrosti ✅ 2026-08-11

Malá maska dostávala jen zlomek latent rozlišení (8× downscale) → měkký
výsledek. Nasazen `ComfyUI-Inpaint-CropAndStitch` (lquesada):
`InpaintCropImproved` (výřez kolem masky + kontext 1.2×, VŽDY přeškálovaný na
1024², `output_padding` je **string enum**!) → vnitřní inpaint graf →
`InpaintStitchImproved` (všití zpět, blend 32 px). Obaleny **všechny 4**
inpaint workflowy; `RepeatImageBatch`+`ImageCompositeMasked` v SDXL grafech
nahrazeny stitchem (dělá kompozit sám, vč. batch 2). Pixel-diff mimo masku:
Fill ~0 (lepší než dřív — stitch vrací originál mimo výřez), SDXL ~1 %
vzorků = záměrný 32px blend pás švu. Vizuálně řádový skok v detailu.
Appka beze změn (sentinely stejné).

## M7 — face-identity inpaint (FLUX Fill + PuLID) ✅ 2026-08-11 (kód; zařízení viz M4)

Redux/IPAdapter přenášejí jen sémantiku (CLIP), ne identitu → obličej
z reference byl „podobný jen vzdáleně". Řešení: **PuLID-FLUX** (InsightFace
biometrický embedding + EVA-CLIP).

- Server: `ComfyUI_PuLID_Flux_ll` + `facexlib`, `facenet-pytorch --no-deps`
  (jinak downgrade torch!); modely `pulid_flux_v0.9.1.safetensors` (1,1 GB,
  models/pulid) + `EVA02_CLIP_L_336_psz14_s6B.pt` (857 MB, models/clip);
  antelopev2 už byl. **Patch nodu**: `pulid_forward_orig` v PulidFluxHook.py
  neznal `timestep_zero_index` (ComfyUI ≥ 0.19) — přidán param + `**kwargs`
  (záloha `.bak-20260811`; pozor při `git pull` nodu).
- `flux_fill_inpaint_face.api.json`: Fill crop&stitch + ApplyPulidFlux
  (**weight 1.0, BEZ attn_mask** — crop repaint už scopuje maska; s attn_mask
  a weight 0.9 identita neprorazila kontext). Test: identita reference
  prokazatelně přenesena (99 s/batch 2).
- **Maska musí pokrýt vše, co se má změnit** — vlasy mimo masku zůstanou
  původní (ověřeno: velká maska přes hlavu = tvář reference, malá = jen
  omlazení). Do UI hintu příště?
- App: `inpaintFaceAsset`/`inpaintFace` (jen flux-fill), `refIsFace` napříč
  edit()/GenNode (persistováno jen true)/provider/retry; face toggle ikona
  (`face_retouching_natural`) u reference v prompt sheetu, jen pro modely
  s face podporou; přepnutí chipu na model bez ní režim vypne.
- SDXL InstantID varianta zůstává jako možné rozšíření (vše na serveru je).

## Mimo scope

- MangaPrompts (tgbot RMBG auto-masky) — samostatný plán později
- Outpainting (FLUX Fill ho umí — přidá se rozšíření canvasu v editoru, jinak
  stejná pipeline; nechat na follow-up)
- Batch > 1 pro FLUX Fill jedním queue (vyžaduje RepeatLatentBatch za
  InpaintModelConditioning — ověřit podporu, zatím sekvenčně)
