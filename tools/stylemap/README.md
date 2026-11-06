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
(`http://192.168.88.66:8080/v1`) a běží jen v okně **19:15–00:50**, souběžnost
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

## Co zatím není

Z plánu chybí: popisky clusterů z VLM tagů (jsou zatím z média a medoidu),
pinch-hierarchie s ostřejším atlasem, dogenerování děr (§8), StyleSpec
a aplikace na fotku (§9). `features.npz` místo parquetu je záměr — o závislost
míň, dokud to nečte nic jiného než `build_map.py`.
