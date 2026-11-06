# STYLEMAP_PLAN.md — "Style Map" widget: prstem mezi tisíci styly jednoho motivu

Handoff pro Opuse. Vstup: adresář s tisíci obrázky stejného motivu v různých stylech (manga, autorské styly, techniky, barevnosti). Výstup: mobilní Flutter widget, ve kterém prst na obrazovce vybírá obrázek a přejížděním po widgetu vzniká plynulá "animace" mezi styly.

---

## 0. Odpovědi na klíčové otázky (rozhodnuto)

| Otázka | Rozhodnutí |
|---|---|
| Stačí 2D? | Pro navigaci ano, pro reprezentaci ne. Stylový prostor je ~10–20D. Používáme 2D **mapu sousednosti** (UMAP → mřížka), ne 2D "osy". |
| Stačí čtverec? | Čtverec + prstenec (jako HSV picker) = 3 dimenze na jedné obrazovce. Čtvercová mřížka je pro přiřazení 1 obrázek = 1 buňka nejjednodušší; hex mřížka je nice-to-have. |
| Jak zachytit víc parametrů? | (a) UMAP-mapa pro "podobné jsou u sebe", (b) přepínatelné interpretovatelné osy X/Y, (c) fasety (tagy) jako filtr, (d) pinch-zoom = hierarchie cluster → uvnitř clusteru. |
| Pomůžou LLM tagy? | Ano, ale jako popisky clusterů, fasety a vyhledávání — ne jako spojité osy. Spojitou verzi tagu dává CLIP zero-shot skóre. |
| Animace | Plynulost = sousední buňky si musí být vizuálně blízké. Měřit LPIPS/SSIM mezi sousedy, optimalizovat přiřazení na mřížku, předpočítat 1D Hilbert/TSP trasu pro scrub/autoplay. |

---

## 1. Architektura

```
[gallery/*.png]
      │
      ▼  (Python, běží na Sparku / kdekoli s GPU)
┌─────────────────────────────┐
│ 1. extract_features.py      │ → features.parquet   (per obrázek: cheap + CLIP + CSD + tagy)
│ 2. build_map.py             │ → map.json           (umap xy, grid cell, cluster, hilbert idx, osy)
│ 3. make_thumbs.py           │ → thumbs/ atlas.png  (mozaika 32px + 128px + 512px pyramida)
└─────────────────────────────┘
      │
      ▼
[Flutter app]  StyleMap widget: načte map.json + atlas, zobrazí mřížku/prstenec, prst → obrázek
```

Jedna pipeline, jeden manifest, widget je čistě klient. Žádný backend za běhu.

---

## 2. Extrakce vlastností (`extract_features.py`)

### 2.1 Levné, interpretovatelné (OpenCV/numpy, ms na obrázek)
Vše normalizovat na 0–1 přes percentily (2–98) z celé sady.

- `luminance` — mean L (CIELAB)  → osa světlý/tmavý
- `contrast` — std L
- `saturation` — mean chroma (sqrt(a²+b²)) → živé/pastelové/monochrom
- `hue` — kruhový průměr H (HSV) vážený sytostí + `hue_concentration` (délka výsledného vektoru; nízká = pestrá paleta, vysoká = jednobarevná)
- `warmth` — mean b* (žlutá↔modrá), `tint` — mean a* (zelená↔červená)
- `edge_density` — podíl Canny pixelů → čárovost / lineart vs. malba
- `sharpness` — variance Laplacianu → detail vs. měkké/rozmazané
- `color_count` — počet barev po kvantizaci (k-means 16 / median cut) → flat/cel-shading vs. gradienty
- `colorfulness` — Hasler–Süsstrunk metrika
- `entropy` — entropie histogramu L
- `grain` — vysokofrekvenční energie (FFT) → zrno, šum, halftone

### 2.2 Sémantické (OpenCLIP ViT-L/14 nebo SigLIP)
- `clip_emb` (768D, normalizovaný) → podobnost, UMAP, clustery
- **Zero-shot stylové osy** = `sim(img, prompt_A) − sim(img, prompt_B)`, softmax přes sadu promptů. Definovat ~12 bipolárních os:
  - photo ↔ drawing ("a photograph of …" vs "a drawing of …")
  - realistic ↔ stylized
  - anime/manga ↔ western comic
  - painterly (oil, watercolor, gouache) ↔ graphic (vector, flat, pixel)
  - 3D render ↔ 2D
  - sketch/lineart ↔ fully rendered
  - vintage/retro ↔ modern/clean
  - dark/moody ↔ bright/cheerful
  - minimal ↔ detailed/busy
- Multi-class "medium" (softmax nad: photo, oil painting, watercolor, pencil sketch, ink, pixel art, 3D render, anime cel, comic, collage, lowpoly, cutout …) → `medium_top`, `medium_probs`

### 2.3 Čistě stylový embedding (volitelné, ale doporučeno)
- **CSD** (Contrastive Style Descriptors, Somepalli et al. 2024) — trénovaný na styl, ignoruje obsah. Protože motiv je stejný, CLIP i CSD fungují, ale CSD dá čistší stylovou mapu.
- Fallback: VGG Gram-matice z conv3_1 + conv4_1 → PCA na 256D (klasický "style loss" prostor).

### 2.4 VLM tagy (lokální Qwen2-VL / Florence-2 na Sparku, nebo Claude)
Strukturovaný JSON per obrázek, cena ~0.5–2 s/obrázek lokálně:
```json
{"medium": "watercolor", "technique": ["wet-on-wet"], "palette": "pastel",
 "era": "1970s", "artist_like": ["Miyazaki"], "mood": "calm",
 "line_quality": "soft", "background": "plain", "tags": ["…"]}
```
Použití: fasety (filtr), popisek clusteru (nejčastější tagy v clusteru), fulltext hledání "ukaž mi watercolor". **Ne** jako osy.

### 2.5 Vzájemné podobnosti pro animaci
Motiv je stejný ⇒ má smysl pixelová/perceptuální vzdálenost:
- `lpips` (AlexNet) nebo DreamSim mezi obrázky — plná matice pro ≤ 3000 obr. je OK (N²/2 ≈ 4.5M párů, GPU batch).
- Použije se pro: (a) optimalizaci přiřazení na mřížku, (b) Hilbert/TSP trasu, (c) metriku "plynulost animace".

### 2.6 Výstup
`features.parquet`: `id, path, w, h, [cheap…], clip_emb, csd_emb, axis_* (12), medium_probs, tags_json`

---

## 3. Stavba mapy (`build_map.py`)

### 3.1 Redukce
- PCA na `csd_emb` (nebo `clip_emb`) → 50D, log explained variance (pro report: kolik dimenzí reálně nese info).
- UMAP(n_neighbors=15–30, min_dist=0.05, metric=cosine) → 2D `umap_xy`.
- HDBSCAN nebo k-means (k≈12–30) na 50D → `cluster_id`; popisek clusteru z tagů + top medium.

### 3.2 Mřížka (klíčový krok)
Cíl: každý obrázek má právě jednu buňku, sousedé v mřížce ≈ sousedé v UMAP, a navíc LPIPS mezi sousedy minimální.
- Rozměr: `G = ceil(sqrt(N))`, čtverec G×G (N=1000 → 32×32, prázdné buňky dolů/doprava nebo vyplnit nejbližším duplikátem).
- **Linear assignment**: cost = ||umap_xy_i − cell_xy_j||² → `scipy.optimize.linear_sum_assignment` (nebo lapjv pro N>2000). To je "RasterFairy"/"image t-SNE grid" postup.
- Refinement: lokální swap heuristika — náhodně vybrat dvojici sousedních buněk, prohodit, pokud klesne součet LPIPS k sousedům (pár tisíc iterací, zlepší plynulost ~10–20 %).
- Volitelně **hex mřížka** (6 sousedů místo 4) — plynulejší, ale složitější hit-test.

### 3.3 Interpretovatelné osy pro "Pad" mód
Pro každou dvojici os z předvoleného seznamu (např. `luminance×axis_photo_drawing`) **nepočítat** novou mřížku; místo toho při výběru prstu `(x,y)` hledat nejbližší obrázek v 2D feature prostoru (KD-tree, předpočítaný). Aby prst "nepřeskakoval", vybírá se vždy nearest a zobrazí se bodový scatter jako pozadí.

### 3.4 Prstenec
- Mód "hue": úhel = `hue`, poloměr = `saturation`. Obrázky s `hue_concentration < 0.2` (pestré/monochrom) jdou do středu.
- Mód "clusters": sektory = clustery (šířka ∝ velikost), poloměr = vzdálenost od centroidu. Vnitřek čtverce pak zobrazuje jen obrázky vybraného sektoru (hierarchie).

### 3.5 1D trasa pro scrub/autoplay
- Hilbertova křivka přes mřížku (jednoduché, zachovává lokalitu) → `hilbert_idx`.
- Lepší: TSP (nearest-neighbor + 2-opt) nad LPIPS maticí → `tour_idx`. Animace po této cestě je nejplynulejší možná.
- Výstup obou; widget přepíná.

### 3.6 Výstup `map.json`
```json
{"grid": 32, "images": [
  {"id": "a1", "cell": [3, 17], "umap": [0.12, 0.88], "cluster": 4,
   "hilbert": 212, "tour": 540, "f": {"lum": 0.81, "sat": 0.3, "hue": 0.62, "warm": 0.4,
   "edge": 0.1, "photo": 0.9, "paint": 0.2, "...": 0}}],
 "axes": [{"key": "lum", "label": "světlý ↔ tmavý"}, …],
 "clusters": [{"id": 4, "label": "akvarel, pastel", "size": 61, "color": "#…"}],
 "pyramid": {"32": "atlas32.png", "128": "atlas128.png", "512": "thumbs512/"}}
```

---

## 4. Flutter widget `StyleMap`

### 4.1 Módy (přepínatelné lištou dole)
1. **Map** (default) — čtverec je doslova mozaika 32px thumbnailů (atlas). Prst → buňka → velký obrázek nad ním. Pinch-zoom do oblasti (zobrazí 128px thumby) = hierarchie.
2. **Pad** — čtverec s volbou os X a Y (dropdown nebo swipe na popisku osy). Pozadí: scatter teček obarvených clusterem. Prst → nearest neighbor (KD-tree v Dartu nebo předpočítaná 64×64 lookup tabulka cell→id, levnější).
3. **Wheel** — prstenec (hue nebo clustery) kolem čtverce; tah po prstenci filtruje/vybírá sektor, čtverec uvnitř reaguje.
4. **Scrub** — vodorovný slider přes `tour_idx` + play/pause + rychlost. Toto je "animace".

### 4.2 Interakce
- `GestureDetector` `onPanStart/Update/End` → lokální souřadnice → buňka; `HapticFeedback.selectionClick()` při změně buňky.
- Dlouhé podržení = uložit do "oblíbených" / zobrazit tagy obrázku.
- Dva prsty: pinch = zoom (Map), rotace = otočit prstenec.
- Zobrazovaný obrázek: `Image` s `gaplessPlayback: true` + `precacheImage` okolních 8 buněk (a ±5 na trase) → žádné bliknutí.

### 4.3 Výkon
- Atlas 32×32 buněk × 32 px = 1024×1024 PNG ≈ 1–2 MB; 128px atlas 4096² ≈ 16 MB (nebo rozdělit na dlaždice).
- Velké náhledy 512px WebP q80 ≈ 40–60 kB × 1000 = 50 MB v assets nebo stáhnout lazy. Pro "animaci" stačí 512px.
- Pro extra plynulý scrub: předrenderovat **video** po `tour_idx` (ffmpeg, 24 fps, každý snímek 2–4 framy) a slider seekovat ve videu (`video_player`). Nejlevnější cesta k plynulé animaci na slabších telefonech.
- Vykreslení mozaiky: `CustomPainter` + `drawAtlas` (jedna GPU batch) místo 1000 widgetů.

### 4.4 Struktura
```
lib/stylemap/
  stylemap.dart          // StyleMap(controller, mode) — veřejný widget
  model.dart             // MapManifest, ImageEntry, Axis, Cluster (fromJson)
  atlas.dart             // načtení atlasů, drawAtlas painter
  modes/map_mode.dart
  modes/pad_mode.dart
  modes/wheel_mode.dart
  modes/scrub_mode.dart
  lookup.dart            // cell↔id, kd-tree / lookup tabulky
tools/                   // Python pipeline (viz výše)
```

---

## 5. Milníky

1. **M1 Pipeline MVP** (1 den): cheap features + CLIP emb + UMAP + linear assignment na mřížku → `map.json` + atlas32. Report: PCA variance, histogramy os.
2. **M2 Flutter Map mód** (1 den): mozaika, prst → obrázek, precache, haptika. Ověřit "animaci" ručně.
3. **M3 Plynulost** (0.5 dne): LPIPS matice, swap-refinement, TSP trasa, Scrub mód + autoplay. Metrika: průměrný LPIPS mezi sousedy před/po.
4. **M4 Pad + Wheel** (1 den): osy, scatter, prstenec hue/clustery, pinch hierarchie.
5. **M5 Tagy** (0.5 dne): VLM tagy, popisky clusterů, fasetový filtr, hledání.
6. **M6 Polish**: hex mřížka, video-scrub fallback, export vybrané sekvence jako GIF/MP4 (sdílení = promo).

---

## 6. Rizika / otevřené body

- UMAP je stochastický → fixovat `random_state`; při přidání nových obrázků použít `umap.transform` (ne nový fit), jinak se mapa přeskládá.
- CLIP částečně kóduje obsah; protože motiv je stejný, je to OK, ale pro směs motivů nutno CSD.
- Prázdné buňky při N ≠ G²: buď menší obdélník G×H, nebo doplnit duplikáty nejbližších (vizuálně neruší).
- Zero-shot osy jsou relativní — kalibrovat percentily na sadě, ne absolutně.
- Na 1000+ obrázků v assets hlídat velikost APK/IPA → lazy download pyramidy z ol1n.com CDN.

## 7. Rozšíření (později)
- Ten samý widget nad výstupem ComfyUI batch jobu = "style explorer" pro Ol1nLLM Lab.
- Vybranou trasu (sekvenci stylů) exportovat jako prompt-schedule → vygenerovat skutečné video morph (AnimateDiff/Wan) místo přepínání snímků.
- Učení z interakce: kam uživatel chodí nejčastěji → doporučené styly.
