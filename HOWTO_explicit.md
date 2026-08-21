# Jak promptovat modely pro explicitní obsah

Aplikace každému modelu automaticky přidává `positivePrefix` a `negativePrompt`
(definováno v `lib/models/image_model.dart`). Ty **nepiš do promptu** — aplikace
je doplní sama. Piš jen samotný obsah scény.

---

## FLUX Schnell — txt2img

**Backend:** NVIDIA NIM (`llm.ol1n.com/nim/flux-schnell`)  
**Styl promptu:** přirozená angličtina, věty nebo fráze  
**Prefix:** _žádný_ (app nic nepřidává)

FLUX modely jedou přes NIM — ten má hardcoded content filter, který explicitní
obsah odmítne bez ohledu na prompt. **Explicitní obsah zde nefunguje.**  
Použij místo toho ComfyUI modely níže.

---

## FLUX Kontext — img2img

**Backend:** NVIDIA NIM (`llm.ol1n.com/nim/flux-kontext`)  
**Styl promptu:** editační instrukce v angličtině  
**Prefix:** _žádný_

Stejné omezení jako Schnell — NIM filtr. **Explicitní obsah zde nefunguje.**

---

## FLUX manga — txt2img + img2img

**Backend:** ComfyUI, dedikované workflow JSONy  
**Styl promptu:** manga/anime popisné fráze v angličtině  
**Prefix:** _žádný_ (baked-in v JSON)

Manga workflow je natrénované na stylizovaný obsah, ne na explicitní fotografický
realismus. Pro lehce explicitní obsah funguje přirozený popis:

```
upper body, partially undressed, lingerie, intimate pose, soft lighting
```

Pro silněji explicitní obsah je lepší použít Illustrious nebo Pony modely.

---

## Pony V6 — txt2img + img2img

**Backend:** ComfyUI, template `sdxl_txt2img/img2img.api.json`  
**App přidává prefix:** `score_9, score_8_up, score_7_up, score_6_up`  
**App přidává negative:** `score_4, score_5, score_6, bad quality, ...`  
**Styl promptu:** e621/danbooru tagy, čárkou oddělené

Pony je trénovaný na e621 tag taxonomii. Score tagy aplikace doplní — piš jen
obsah. Pro explicitní obsah přidej `rating:explicit` jako první tag:

```
rating:explicit, 1girl, nude, full body, bedroom, cowgirl position, ...
```

**Klíčové tagy pro explicitní obsah (e621 styl):**

| Kategorie | Tagy |
|---|---|
| Rating | `rating:explicit`, `rating:questionable` |
| Nahota | `nude`, `topless`, `bottomless`, `fully nude` |
| Polohy | `missionary`, `cowgirl position`, `doggy style`, `standing sex` |
| Tělo | `large breasts`, `thick thighs`, `wide hips`, `muscular` |
| Akce | `sex`, `oral`, `fingering`, `masturbation` |
| Kamera | `from above`, `from behind`, `pov`, `close-up` |

LoRA kompatibilní rodina: **SDXL** (v app pickeru se zobrazí SDXL LoRAs).

---

## Juggernaut XL — txt2img + img2img

**Backend:** ComfyUI, template `sdxl_txt2img/img2img.api.json`  
**Checkpoint:** `Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors`  
**App přidává negative:** `bad quality, worst quality, deformed, bad anatomy, bad hands`  
**App nastavuje:** `cfg: 5.0` (nižší = přirozenější výsledky)  
**Styl promptu:** fotografický popis v angličtině, přirozené věty nebo fráze

Juggernaut je fotorealistický model — reaguje nejlépe na fotografický jazyk:

```
a woman lying on a bed, nude, natural lighting, cinematic, 85mm lens, shallow depth of field
```

Pro explicitní obsah:
```
nude woman, intimate scene, bedroom, natural lighting, photorealistic, 
detailed skin texture, explicit pose
```

**Tipy:**
- Nižší `cfg` (5.0, už nastaveno) = přirozenější anatomie
- Přidej světelné podmínky: `soft light`, `golden hour`, `studio lighting`
- Fotoaparátový jazyk funguje dobře: `shot on Canon EOS R5`, `f/1.8`, `bokeh`
- **Vyhni se** přílišnému stackování tagů — Juggernaut preferuje plynulý popis

LoRA kompatibilní rodina: **SDXL**.

---

## Illustrious XL — txt2img + img2img

**Backend:** ComfyUI, template `sdxl_txt2img/img2img.api.json`  
**Checkpoint:** `Illustrious-XL-v2.0.safetensors`  
**App přidává prefix:** `masterpiece, best quality`  
**App přidává negative:** `lowres, bad anatomy, bad hands, worst quality, ...`  
**App nastavuje:** `steps: 28`, sampler `euler_ancestral`, scheduler `normal`  
**Styl promptu:** danbooru tagy + přirozené fráze, angličtina

Illustrious je anime/illustration model. Pro explicitní obsah funguje kombinace
danbooru tagů + popisu:

```
1girl, nude, lying on bed, spread legs, explicit, nsfw, detailed, 
soft lighting, anime style
```

**Klíčové tagy (danbooru styl):**

| Kategorie | Tagy |
|---|---|
| Základní | `nsfw`, `explicit`, `nude`, `topless` |
| Počet postav | `1girl`, `1boy`, `2girls`, `couple` |
| Polohy | `lying`, `sitting`, `standing`, `spread legs`, `on all fours` |
| Stav oblečení | `clothes removed`, `partially clothed`, `underwear only` |
| Akce | `sex`, `oral sex`, `masturbation`, `fingering` |
| Pohled | `pov`, `from above`, `from behind`, `close-up` |
| Prostředí | `bedroom`, `outdoors`, `bathroom`, `hotel room` |

**Tip:** `masterpiece, best quality` app přidá sama — pomůže přidat i `highly detailed, 
sharp focus` pro čistší detaily.

LoRA kompatibilní rodina: **SDXL**.

---

## Atomix Pony Anime — txt2img + img2img

**Backend:** ComfyUI, template `sdxl_txt2img/img2img.api.json`  
**Checkpoint:** `atomixPonyAnimeXL_v30.safetensors`  
**App přidává prefix:** `score_9, score_8_up, score_7_up, score_6_up`  
**App přidává negative:** stejné jako Pony V6  
**App nastavuje:** `steps: 28`, `cfg: 6.5`, sampler `euler_ancestral`, scheduler `normal`  
**Styl promptu:** mix e621 + danbooru tagů, anime zaměření

Atomix Pony Anime kombinuje Pony scoring systém s anime stylem — funguje lépe
pro stylizované anime explicitní obsah než čistý Pony V6:

```
rating:explicit, 1girl, anime style, nude, large breasts, bedroom, 
intimate pose, detailed, soft shading
```

Score tagy a negative aplikace doplní. Stejná taxonomie jako Pony V6 (e621),
ale výsledky jsou více anime než furry zaměřené.

LoRA kompatibilní rodina: **SDXL**.

---

## SD 1.5

**Backend:** ComfyUI, template `sdxl_txt2img/img2img.api.json`  
**Checkpoint:** `v1-5-pruned-emaonly-fp16.safetensors`  
**App nastavuje:** `512×512`, `cfg: 7.0`, `steps: 25`  
**Styl promptu:** klasický SD styl — krátké tagy, čárkami

SD 1.5 je starší model s nízkým rozlišením (512×512). Pro explicitní obsah
funguje, ale kvalita je výrazně nižší než SDXL modely:

```
nude woman, bedroom, explicit, detailed, masterpiece, high quality
```

**Tip:** SD 1.5 reaguje lépe na kratší, jednoznačné tagy. Vyhni se dlouhým
větám — čím kratší, tím lépe.

---

## Shrnutí — rychlý přehled

| Model | Styl promptu | Explicit? | Nejlepší pro |
|---|---|---|---|
| FLUX Schnell | přirozená angličtina | ❌ NIM filtr | SFW txt2img |
| FLUX Kontext | editační instrukce EN | ❌ NIM filtr | SFW img2img úpravy |
| FLUX manga | anime fráze EN | ⚠️ jen lehce | manga/komiksový styl |
| **Pony V6** | e621 tagy | ✅ | stylizovaný/furry obsah |
| **Juggernaut XL** | fotografický popis EN | ✅ | fotorealistické scény |
| **Illustrious XL** | danbooru tagy | ✅ | anime ilustrace |
| **Atomix Pony Anime** | e621 + danbooru | ✅ | anime + Pony styl |
| SD 1.5 | krátké tagy | ✅ (nízká kvalita) | retro/klasický styl |
