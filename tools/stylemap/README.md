# Style map — pipeline

Z adresáře s tisíci obrázky téhož námětu v různých stylech udělá **pack**, který
čte widget `StyleMap` v appce (`lib/stylemap/`): mřížku, kde spolu sousedí
podobné styly, takže přejíždění prstem působí jako plynulá animace.

Plán a zdůvodnění: [`docs/STYLEMAP_PLAN.md`](../../docs/STYLEMAP_PLAN.md).
Tady je to, co z něj už existuje (milníky M1 a M2).

## Spuštění

```bash
make stylemap-env                       # jednou: venv s torch, open_clip, umap
make stylemap SET=<jméno sady> SESSIONS="<id> <id>" TITLE="…" TAG_REGEX='artist:[^,]+'
make stylemap-serve                     # packy pro telefon na LAN, port 8770
make stylemap-publish                   # packy na NAS, galerie je servíruje na /stylemaps/
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
| `build_map.py` | `features.npz` | `map.json` |
| `make_thumbs.py` | `map.json`, obrázky | `atlas.webp`, `t/<i>.webp`, `../index.json` |

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
`hilbert`, `medium`, `f` (hodnoty v pořadí `axes[]`). Cesty jsou relativní;
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

## Co zatím není

Z plánu chybí: LPIPS mezi sousedy a swap-refinement, TSP trasa a režim Scrub
(M3), režimy Pad a Wheel (M4), VLM tagy (M5), dogenerování děr (§8), StyleSpec
a aplikace na fotku (§9). `features.npz` místo parquetu je záměr — o závislost
míň, dokud to nečte nic jiného než `build_map.py`.
