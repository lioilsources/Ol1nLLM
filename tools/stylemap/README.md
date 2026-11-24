# Style map — pipeline

Z adresáře s tisíci obrázky téhož námětu v různých stylech udělá **pack**, který
čte widget `StyleMap` v appce (`lib/stylemap/`): mřížku, kde spolu sousedí
podobné styly, takže přejíždění prstem působí jako plynulá animace.

Plán a zdůvodnění: [`docs/STYLEMAP_PLAN.md`](../../docs/STYLEMAP_PLAN.md).
Tady je to, co z něj už existuje (milníky M1 až M5).

## Spuštění

```bash
make stylemap-env                       # jednou: venv s torch, open_clip, umap
make stylemap SET=<jméno sady> SESSIONS="<id> <id>" TITLE="…" TAG_REGEX='artist:[^,]+'
make stylemap-tags SET=<jméno sady>     # VLM tagy (jen v okně modelu, viz níž)
make stylemap-serve                     # packy pro telefon na LAN, port 8770
make stylemap-publish                   # packy na NAS, galerie je servíruje na /stylemaps/
make stylemap-video SET=<sada> NAME=… WHERE="model=…" RATE=4 FADE=0.4   # MP4 na výšku
make stylemap-video RUN=<běh labu> NAME=… RATE=3 LABEL=1                 # styl po stylu přes modely
make stylemap-video RUN=<běh labu> NAME=… GRID=1 RATE=2 LABEL=1          # všechny modely stylu na jednom snímku
```

Výstup jde do `build/stylemap/<SET>/`. Sada má dva možné zdroje:

**Sessions z FINETUNE gallery** (`SESSIONS`, jedna nebo víc). Obrázky se čtou
přes `GET /api/images?session=…`; `WHERE="score=1"` přidá kterýkoli filtr, který
ten endpoint bere, takže z ohodnocené session jde udělat mapa jen z přijatých
obrázků. Běh labu odeslaný přes `lab export --send` je v galerii právě jedna
session. Nahraná předloha běhu (`origin: upload`) se vynechává a obrázek, který
je ve dvou sessions, se vezme jednou. CF Access token se bere z prostředí nebo
z `.env.local`.

Stahují se **náhledy galerie** (delší strana 384 px), ne originály: vlastnosti
se počítají na 256 px, CLIP vidí 224 — originály by znamenaly třicetkrát větší
stahování pro stejnou mapu. Náhled v packu je pak ale jen ~260 px široký;
`FULL=1` stáhne originály a dá ostré 384px náhledy. Cache je
`build/stylemap/_blobs/` podle sha256, společná všem sadám.

**Běh labu na disku** (`RUN=<id>`, čte `build/lab/<RUN>/img` a
`wf/manifest.json`) — bez stahování a s originály, hodí se pro běh, který
v galerii ještě není.

Popisek a fragment promptu: galerie vrací jen text promptu, takže se fragment
vždy vytahuje přes `TAG_REGEX`. Běhy labu udělané přes `--prompts-yaml` nesou
jméno promptu v `promptBody` a regex nepotřebují.

## Kroky

| skript | čte | píše |
|---|---|---|
| `extract_features.py` | obrázky sady (galerie nebo běh) | `features.npz`, `items.json` |
| `perceptual.py` | obrázky sady | `lpips.npy` |
| `build_map.py` | `features.npz`, `lpips.npy` | `map.json` |
| `make_thumbs.py` | `map.json`, obrázky | `atlas.webp`, `t/<i>.webp`, `../index.json` |
| `tag_images.py` (volitelný) | obrázky sady | `tags.json` |

**Co se musí pustit znovu.** Kroky na sebe navazují přes soubory v adresáři
sady, takže se opakuje jen to, co se změnilo:

| co je nového | co pustit | co zůstává |
|---|---|---|
| režim widgetu nad daty, která pack už má (Osy, Kolo, filtr) | nic | celý pack |
| pole v `map.json` (trasa, fasety, VLM tagy) | `build_map.py` + `make_thumbs.py` — vteřiny až minuta | stažené obrázky, CLIP, LPIPS |
| jiné vlastnosti nebo embedding | `extract_features.py` a vše za ním | stažené obrázky |
| obrázky přibyly | všechno | cache originálů v `_blobs/` |

`build_map.py` je deterministický (pevný seed pro UMAP, k-means i prohazování):
nad stejnými vstupy dá stejné buňky i trasu, takže doplnění tagů mapu
nepřeskládá. `make_thumbs.py` se po něm pouští jen proto, že `map.json` vzniká
celý znovu a pole o atlasu do něj doplňuje až tenhle krok.

**Vlastnosti** (`extract_features.py`): 13 levných statistik barvy a textury
(jas, kontrast, sytost, odstín, teplota, hustota hran, ostrost, počet barev,
zrno…), CLIP embedding (ViT-L/14, váhy OpenAI — proto varianta `quickgelu`,
jinak by aktivace neseděla k vahám) a z něj 9 zero-shot os (`fotka ↔ kresba`,
`anime ↔ západní komiks`…) a pravděpodobnosti média. Hodnoty jsou syrové.

**Mapa** (`build_map.py`): PCA na 50 dimenzí → UMAP do 2D → přiřazení na
čtvercovou mřížku (`linear_sum_assignment`, každý obrázek co nejblíž své UMAP
poloze, jeden na buňku). Prázdné buňky zůstanou prázdné a padnou tam, kde je
mapa řídká. K tomu k-means clustery, 1D trasa přes mřížku (zobecněná Hilbertova
křivka — po sobě jdoucí buňky vždy sdílejí hranu) a vlastnosti normalizované
na 0–1 mezi 2. a 98. percentilem sady. Skript vypíše **vzdálenost sousedů**
proti náhodnému rozmístění; to je číslo, podle kterého se pozná, jestli mapa
drží pohromadě.

**Vzdálenost pro oko** (`perceptual.py`): LPIPS (AlexNet) mezi každými dvěma
obrázky sady, při delší straně 160 px. CLIP říká, které styly jsou příbuzné;
LPIPS říká, jak tvrdý je střih mezi dvěma obrázky, a o ten jde při přejíždění
i přehrávání. LPIPS je kvadrát eukleidovské vzdálenosti v prostoru vážených
normalizovaných aktivací, takže se každý obrázek vloží jednou a celá matice je
jeden maticový součin (3 867 obrázků: 2,5 min vlastnosti, 37 s matice) místo
7,5 milionu průchodů sítí. Skript to na 16 párech ověří proti knihovně `lpips`
(odchylka 0,00002).

**Vyhlazení a trasa** (`build_map.py`, když najde `lpips.npy`): po přiřazení na
mřížku se prohazují obrázky nejvýš `--reach` buněk od sebe (výchozí 2), dokud
to snižuje LPIPS k sousedům — tvar mapy z UMAP zůstane, mění se jen pořadí
uvnitř sousedství. Prázdné buňky se nehýbou. Druhá trasa `tour` je pořadí
s nejmenšími kroky v LPIPS (nejbližší soused + 2-opt, cyklus rozstřižený
v nejdelším kroku); tu přehrává widget. Bez `lpips.npy` se obojí přeskočí
a widget hraje po Hilbertově křivce.

**Tagy z VLM** (`tag_images.py`, volitelné): jeden request na obrázek (384 px),
odpověď vynucená JSON schématem — `medium`, `palette`, `mood`, `line`,
`background` z uzavřených seznamů (`common.FACETS`, i s českými popisky)
a 3–6 volných klíčových slov. Uzavřené seznamy proto, aby faseta měla pár
chipů a ne jeden na každý pravopis; odpověď mimo seznam se zahodí. Tagy jsou
k filtrování a hledání, **ne** k rozmístění na mapě. Cache je per soubor
obrázku v `build/stylemap/_tags/`, takže přerušený běh nic neztratí a sada jde
otagovat napůl — `build_map.py` vezme, co je.

Model je `openclaw-default` (qwen36) přes LiteLLM na SPARKu
(`http://SPARK_HOST:8080/v1`) a běží jen v okně **19:15–00:50**, souběžnost
nejvýš 2 (domluveno s plánovačem SPARKu 2026-10-08; model se dělí s Právníkem
a StoryTellerem). Mimo okno vrací gateway 500 — skript po osmi chybách po sobě
skončí, stejně jako v `--until` (výchozí 00:50).

Bez `tags.json` má pack fasety jen dvě: model (když jich sada míchá víc)
a médium podle CLIP zero-shotu.

**Náhledy** (`make_thumbs.py`): atlas je celá mapa jako jeden obrázek
(buňka 32 px na šířku) — widget ho kreslí jako mozaiku a výřez z něj ukazuje
jako okamžitý placeholder. `t/<i>.webp` (384 px) je ostrý náhled, který se
dotáhne, když prst na buňce zůstane.

## Formát packu

```
build/stylemap/
  index.json                 {"packs": [{id, title, n, aspect, atlas}]}
  <SET>/map.json             mřížka, osy, clustery, obrázky
  <SET>/atlas.webp
  <SET>/t/<i>.webp
```

`map.json` → `images[]`: `i` (index, jméno náhledu), `id` (obrázek v galerii,
nebo buňka běhu labu),
`label`, `tag` (fragment promptu), `style` a `model` (id z registrů appky, když
je zdroj zná — pick pak nastaví chip stylu), `cell` `[sloupec, řádek]`, `umap`, `cluster`,
`hilbert`, `tour` (pozice na trase pro přehrávání, jen s LPIPS), `medium`,
`f` (hodnoty v pořadí `axes[]`), `tags` (faseta → hodnota) a `words` (klíčová
slova z VLM). Nahoře `facets[]`: klíč, český název a hodnoty s počty — jen
fasety, ve kterých je z čeho vybírat. Cesty jsou relativní;
odkud se pack servíruje, ví až `StyleMapService` (`STYLEMAP_URL`).

## První sada: `noobai-artists` (2026-10-08)

Z běhu `noobai-artists-v3` (3 867 obrázků, `TAG_REGEX='artist:[^,]+'`):

| | |
|---|---|
| mřížka | 63×63, 102 prázdných buněk (všechny v jednom rohu) |
| vzdálenost sousedů (CLIP, kosinová) | 0,182 proti 0,276 při náhodném rozmístění — poměr 0,66 |
| dimenze stylu | 50 % rozptylu v 15 dimenzích, prvních 50 drží 74 % |
| čas na M2 (MPS) | vlastnosti 2 min, CLIP 9 min, mapa 20 s, náhledy 1 min |
| velikost packu | náhledy 68 MB, atlas 2,2 MB, `map.json` 1,3 MB |

**Tahle sada není to, na co je mapa stavěná.** Každý umělec v ní má jinou
pózu, oblečení i účes, takže CLIP třídí i podle obsahu, ne jen podle stylu
(kolik z uspořádání připadá na co, změřené není). Poslouží k vývoji widgetu; skutečná mapa stylů chce běh s pevným námětem
(`tools/lab/candidates/native-artists.yaml` na větvi `lab/prompt-candidates`, 979 buněk; celý na GPU zatím neběžel).

## Sady s pevným námětem (2026-10-08, z galerie, `FULL=1`)

| sada | obrázků | mřížka | sousedé / náhodně | co se mění |
|---|---|---|---|---|
| `noobai-artists-vermeer` | 84 | 10×10 | 0,118 / 0,207 (0,57) | 42 umělců × s Vermeerem a bez, NoobAI |
| `artist-styles-3models` | 378 | 20×20 | 0,166 / 0,296 (0,56) | 41 stylů umělců + základ × 3 modely × 3 barvy vlasů |

Obě jsou repose nad jednou předlohou se seedem 777, tedy to, na co je mapa
stavěná, a poměr vychází líp než u `noobai-artists` (0,66). V první se mapa
rozpadla na dvě souvislé oblasti — s Vermeerem a bez.

## Plynulost (M3, 2026-10-08)

LPIPS mezi sousedy na mřížce před vyhlazením a po něm, a průměrný krok trasy:

| sada | sousedé před → po | náhodně | krok: Hilbert → `tour` | náhodně |
|---|---|---|---|---|
| `noobai-artists-vermeer` | 0,294 → 0,266 (−10 %) | 0,451 | 0,276 → 0,233 | 0,432 |
| `artist-styles-3models` | 0,424 → 0,375 (−12 %) | 0,571 | 0,386 → 0,241 | 0,573 |
| `noobai-artists` | 0,459 → 0,403 (−12 %) | 0,547 | 0,403 → 0,317 | 0,547 |

Vyhlazení dalo to, co plán čekal (10–20 %), a CLIP sousedství nerozbilo
(poměr k náhodnému rozmístění 0,62 / 0,56 / 0,66, před ním 0,57 / 0,56 / 0,66).
Větší dosah už skoro nepřidá: na `artist-styles-3models` −10 % při dosahu 1,
−12 % při 2 i 3. Trasa je znát víc než mřížka — 2D mřížka musí každému obrázku
najít čtyři sousedy, trasa jen dva.

Čísla jsou LPIPS při 160 px, tedy barva a rozvržení; jak plynule přehrávání
působí na telefonu, z nich neplyne.

## Sady ze sessions (2026-10-08, z galerie, `FULL=1`)

| sada | obrázků | CLIP sousedé / náhodně | LPIPS sousedů před → po | krok: Hilbert → `tour` |
|---|---|---|---|---|
| `long-layered-redhead` | 252 | 0,56 | 0,398 → 0,357 | 0,364 → 0,249 |
| `long-blond-hair` | 300 | 0,51 | 0,386 → 0,338 | 0,347 → 0,230 |
| `curly-blond-hair` | 225 | 0,60 | 0,467 → 0,431 | 0,433 → 0,350 |
| `blond-curly-hair` | 132 | 0,63 | 0,463 → 0,419 | 0,425 → 0,292 |
| `curly-redhead` | 224 | 0,48 | 0,368 → 0,326 | 0,325 → 0,227 |
| `naked-woman` | 208 | 0,51 | 0,338 → 0,300 | 0,305 → 0,226 |

## Video na výšku (`make stylemap-video`, `make_video.py`)

Slideshow jako **MP4 1080×1920** (9:16, H.264, 30 fps, yuv420p, faststart),
tedy formát, který TikTok, YouTube Shorts i Instagram Reels berou bez
přepočítávání. Renderuje se **lokálně na Macu** (ffmpeg), nic nikam neposílá.

### Rychlý tahák

```bash
# běh labu → videa podle modelu
make stylemap-video RUN=<běh> NAME=noobai WHERE="model=noobai-xl" RATE=6 FADE=0.3

# běh labu → styl po stylu přes všechny modely, s popisky
make stylemap-video RUN=<běh> NAME=styly RATE=3 LABEL=1

# běh labu → všechny modely stylu na jednom snímku (mřížka)
make stylemap-video RUN=<běh> NAME=mrizka GRID=1 RATE=2 LABEL=1

# běh labu → 2 modely pod sebou, jen úplné snímky, minutová videa po promptech
make stylemap-video RUN=<běh> NAME=pod-sebou GRID=1 COLS=1 COMPLETE=1 SPLIT=60 RATE=3

# mapa stylů (pack) → slideshow po LPIPS trase jako v appce
make stylemap-video SET=<sada> NAME=mapa RATE=8 FADE=0.3
```

Výstup: `build/lab/<RUN>/video/<NAME>.mp4`, resp.
`build/stylemap/<SET>/video/<NAME>.mp4` (se `SPLIT` → `<NAME>-01.mp4`, `-02` …).
Ve Finderu: `open build/lab/<RUN>/video/`, do telefonu AirDropem.

### Jak to celé funguje

```
  ZDROJ                 FILTR          POŘADÍ               SNÍMEK            ČAS / SOUBORY
  ─────                 ─────          ──────               ──────            ─────────────
  RUN=<běh labu>  ┐                    ORDER=style ┐        1 obrázek    ┐    RATE, FADE
   (img/ + manifest)│→  WHERE=…   →     (u RUN)    │→       (výchozí)    │→   SPLIT=60 → -01,-02…
  SET=<mapa stylů>┘    COMPLETE=1      ORDER=tour  ┘        GRID=1 mřížka┘    --max-seconds
   (map.json+lpips)                     (u SET)              COLS, LABEL       --audio
```

### 1. Zdroj: `RUN=` nebo `SET=`

| | `RUN=<běh labu>` | `SET=<mapa stylů>` |
|---|---|---|
| Čte | `build/lab/<RUN>/img/*.png` + `wf/manifest.json` | `build/stylemap/<SET>/` (map.json, items.json, lpips.npy) |
| Potřebuje | jen numpy + Pillow (jede systémový `python3`) | postavenou mapu (`make stylemap`, venv s torch) |
| Ví o obrázku | model, styl, flow, **prompt**, popisky z appky | model, styl, médium, VLM tagy, pozice na trase |
| Výchozí pořadí | `style` | `tour` |

Nedoběhlý (zrušený) běh nevadí — bere se, co je na disku.

### 2. Filtr: `WHERE=` a `COMPLETE=1`

```
WHERE="model=noobai-xl model=pony flow=repose"
        └──── nebo ─────┘          a zároveň
```
Hodnoty **stejného** klíče jsou alternativy, **různé** klíče musí platit
všechny (jako filtr v appce). Klíče: `model`, `style`, `flow`; u mapy i
`medium` a VLM tagy.

`COMPLETE=1` (jen s `GRID=1`) zahodí snímky, kde některému modelu obrázek
chybí — místo prázdné dlaždice:

```
  bez COMPLETE                 s COMPLETE=1
  ┌──────┬──────┐              (snímek vynechán,
  │ pony │  ░░  │  ← lustify    video jde rovnou
  │      │ chybí│     nedoběhl  na další styl)
  └──────┴──────┘
```

### 3. Pořadí: `ORDER=style` nebo `ORDER=tour`

```
ORDER=style  (výchozí u RUN)                 ORDER=tour  (výchozí u SET)
prompt 1 ─┬─ bez stylu ─ model A, B, C      obrázky po LPIPS trase: každý další
          ├─ Lascaux   ─ model A, B, C      se od předchozího liší co nejmíň
          ├─ Bauhaus   ─ model A, B, C      (stejné pořadí jako přehrávač v appce)
          └─ …                              S WHERE se trasa naplánuje znovu jen
prompt 2 ─┬─ bez stylu ─ model A, B, C      přes vybrané obrázky (--no-replan =
          └─ …                              pořadí celé mapy)
```
- **Styly** jdou v pořadí pickeru appky (kultury podle doby, umělci podle roku
  narození, média A–Z), baseline „bez stylu“ vždy první.
- **Modely** v pořadí běhu, nebo vlastní: `VIDEO_ARGS="--model-order a,b,c"`
  (neuvedené modely jdou za ně).
- Víc flow (repose + img2img) se střídá uvnitř stylu; jednu vybereš
  `WHERE="flow=repose"`.

### 4. Snímek: jeden obrázek, nebo mřížka (`GRID=1`, `COLS=`, `LABEL=1`)

```
 bez GRID (1 obrázek)     GRID=1 auto (6 čtverců)  GRID=1 COLS=3      GRID=1 COLS=1 (2 modely)
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐ ┌──────────────────┐
│░░░░░░░░░░░░░░░░░░│     │ [Lascaux (…)]    │     │ [Bauhaus (1919)] │ │                  │
│░┌──────────────┐░│     │┌───────┐┌───────┐│     │┌────┐┌────┐┌────┐│ │  ┌────────────┐  │
│░│              │░│     ││   A   ││   B   ││     ││ A  ││ B  ││ C  ││ │  │     A      │  │
│░│   obrázek    │░│     │└───────┘└───────┘│     │└────┘└────┘└────┘│ │  │            │  │
│░│  (contain)   │░│     │┌───────┐┌───────┐│     │┌────┐┌────┐┌────┐│ │  └────────────┘  │
│░│              │░│     ││   C   ││   D   ││     ││ D  ││ E  ││ F  ││ │  ┌────────────┐  │
│░└──────────────┘░│     │└───────┘└───────┘│     │└────┘└────┘└────┘│ │  │     B      │  │
│░ rozmazané pozadí│     │┌───────┐┌───────┐│     │                  │ │  │            │  │
│░░░░░░░░░░░░░░░░░░│     ││   E   ││   F   ││     │                  │ │  └────────────┘  │
└──────────────────┘     │└───────┘└───────┘│     └──────────────────┘ └──────────────────┘
                         └──────────────────┘
```
- **Bez GRID** je na snímku jeden obrázek. `--fit contain` (výchozí) ho ukáže
  celý na jeho rozmazané ztmavené kopii, `VIDEO_ARGS="--fit cover"` ořízne
  na výšku (z 2:3 uteče ~15 % šířky z každé strany).
- **`GRID=1`**: jeden snímek = jeden styl (prompt, flow) a **všechny modely**.
  Rozložení se samo vybere tak, aby obrázky byly co největší; `COLS=N`
  vnutí N sloupců (`COLS=1` pod sebou, `COLS=2` vedle sebe). Model má po celé
  video stejnou dlaždici. `RATE` tu znamená **stylů** za vteřinu.
- **`LABEL=1`** vypálí popisky. Bez mřížky: box „styl / model“ nahoře. V mřížce:
  název stylu nahoře (pruh má vždy výšku dvou řádků, aby mřížka neposkakovala)
  a jméno modelu pod každým obrázkem. Popisky sedí pod záložkami, které TikTok
  a Shorts kreslí nahoře, a mřížka končí nad místem pro jejich titulek dole.

### 5. Čas: `RATE`, `FADE`, `SPLIT`, `--max-seconds`

```
RATE=2, FADE=0.25        (jeden snímek = 1/RATE s = 0,5 s)
 obrázek 1          obrázek 2          obrázek 3
├──────────────╱╲──────────────╱╲──────────────┤
               └┘ prolínačka = FADE × 0,5 s     FADE=0 → tvrdý střih

SPLIT=60 (vteřin), dělí se jen mezi prompty:
 prompt 1 │ prompt 2 │ prompt 3 ║ prompt 4 │ prompt 5 │ prompt 6 ║ prompt 7 …
 └──────── NAME-01.mp4 ≤ 60 s ─┘└──────── NAME-02.mp4 ≤ 60 s ─┘└─ NAME-03 …
```
- **`RATE`** obrázků (u mřížky stylů) za vteřinu, 0–30. Jeden obrázek přes
  celou obrazovku snese 4–8/s, mřížka se šesti modely 1–2/s.
- **`FADE`** podíl času snímku na prolínačku (výchozí 0.4, `0` = střih). Při
  vysoké rychlosti je čistší střih.
- **`SPLIT=N`** rozseká výstup na víc videí po nejvýš N vteřinách, **jen mezi
  prompty** — prompt nikdy nepřeteče do dalšího videa; prompt delší než N
  dostane video sám.
- **`VIDEO_ARGS="--max-seconds N"`** naopak **zkrátí** jedno video rovnoměrným
  výběrem (u `ORDER=style` po celých stylech). Se `SPLIT` se nejdřív zkrátí
  a pak rozdělí — obvykle chceš jen jedno z nich.

Délka videa ≈ počet snímků ÷ `RATE`. Příklad: 62 stylů na prompt při `RATE=4`
= 15,5 s na prompt → `SPLIT=60` dá 3 prompty na video.

### 6. Ostatní (`VIDEO_ARGS="…"`)

| Volba | Co dělá |
|---|---|
| `--audio song.mp3` | zvuková stopa (AAC), ořízne se na délku videa. Hudbu radši až v TikToku/YouTube — mají licence. |
| `--size 1080x1350` | jiný rozměr (4:5 pro Instagram feed) |
| `--crf 23` | menší soubor (výchozí 18 = vysoká kvalita; 23 ≈ poloviční velikost, v telefonu bez rozdílu) |
| `--fps 30` | snímků videa za vteřinu (strop pro `RATE`) |
| `--no-replan` | u `SET` s filtrem hrát v pořadí celé mapy |

### Limity platforem

| | TikTok | YouTube Shorts | Instagram Reels |
|---|---|---|---|
| Formát | 9:16, 1080×1920 ✓ | 9:16 ✓ | 9:16 ✓ |
| Délka | do 10 min | **do 3 min** (delší = běžné video) | do 3 min |
| Nahota | stáhne | stáhne | stáhne |

Na Shorts tedy `SPLIT=170` nebo kratší; nejlíp fungují desítky vteřin
(`SPLIT=60`).

## Co kam jde (síť, NAS, telefon)

| Příkaz | Čte | Zapisuje | Síť |
|---|---|---|---|
| `make stylemap SESSIONS=…` | FINETUNE gallery (`/api/images`, náhledy nebo `FULL=1` originály) | `build/stylemap/<SET>/` | **ano** — `finetune.ol1n.com`, CF Access |
| `make stylemap RUN=…` | `build/lab/<RUN>/` | `build/stylemap/<SET>/` | ne |
| `make stylemap-tags` | pack | `tags.json` v packu | **ano** — VLM na SPARKu, v okně modelu |
| `make stylemap-video` | pack (`SET`) nebo běh labu (`RUN`) z disku | `build/stylemap/<SET>/video/` nebo `build/lab/<RUN>/video/` | **ne** — jen lokální ffmpeg |
| `make stylemap-publish` | `build/stylemap/` | NAS `joda:…/FineTuneGallery/stylemaps` (rsync) | **ano** — LAN/ssh na JODU |
| `make stylemap-serve` | `build/stylemap/` | — (HTTP na :8770 pro telefon v LAN) | jen LAN |

- **Na NAS (a tím do appky) jdou jen mapy** — `stylemap-publish` kopíruje
  výhradně `index.json`, `*/map.json`, `*/atlas.webp` a `*/t/*.webp`. Videa,
  `features.npz`, `lpips.npy`, `items.json` a cache se **neposílají**, ani když
  leží ve složce packu. Galerie mapy servíruje na
  `finetune.ol1n.com/stylemaps/<SET>/`, appka si je čte přes `STYLEMAP_URL`.
- **Videa zůstávají na Macu**, nic je nikam nenahrává. Do telefonu AirDropem
  z Finderu (do Fotek), odtud na TikTok/Shorts/Reels.
- **Do FINETUNE gallery jako session** se běh labu dostane jen přes
  `lab export --send` (obrázky a metadata, ne mapa ani video).

## Co zatím není

Z plánu chybí: popisky clusterů z VLM tagů (jsou zatím z média a medoidu),
pinch-hierarchie s ostřejším atlasem, dogenerování děr (§8), StyleSpec
a aplikace na fotku (§9). `features.npz` místo parquetu je záměr — o závislost
míň, dokud to nečte nic jiného než `build_map.py`.
