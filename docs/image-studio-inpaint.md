# Image Studio — inpaint, figurka, identita ve videu

Přesunuto z `CLAUDE.md`.

## Face inpaint (FLUX Fill + PuLID) — dva průchody

`flux_fill_inpaint_face.api.json` (přepínač „Přenese se IDENTITA obličeje
z reference" v editoru masky) jede **dva průchody**: Fill + PuLID + Redux
zamaluje masku, pak `FaceDetailer` (nody 100–109) přemaluje jen detekovanou
tvář na **FLUX.1-dev** s PuLID (weight 1.2, denoise 0.55, crop 1024²).

Proč: PuLID je trénovaný na FLUX.1-dev, ne na Fill — v jednom průchodu se do
Fill přenese jen část. Naměřeno (`tools/facebench`, ArcFace k referenci, 2 zdroje
× 3 reference × 3 seedy): jeden průchod **0.48**, s druhým průchodem **0.72**
(žádný výsledek pod 0.67). Druhý průchod má vlastní PuLID/EVA/InsightFace
loadery — sdílené s prvním průchodem skončí po samplingu offloadnuté na CPU
a `ApplyPulidFlux` spadne na cuda/cpu mismatch.

Co **nepomohlo** (změřeno, ne odhad): vypnutí Reduxu (0.42), `attn_mask` na
PuLID + užší crop + weight 1.3 (0.45), Kontext se dvěma referencemi (0.17 —
tvář vůbec nevymění). Strop téhle cesty je ~0.75–0.8: PuLID kóduje tvář do
jednoho embeddingu, tedy „typ" tváře, ne geometrii. Přes 0.9 by dal jen face
swap (licence jen pro nekomerční použití) nebo LoRA na osobu (20+ fotek).

## Kadeřník (automatická maska + inpaint)

Akce na dlaždici (nůžky, pravý horní roh vedle „Rozhýbat“/„Zachovej pózu“) →
`HairSheet` (Ženy/Muži, sekce, hledání bez diakritiky) →
`ImageStudioNotifier.hairRestyle(imageId, hairstyleId)`:

1. `ComfyUIService.analyseHair` pustí `assets/comfyui/hair_analyse.api.json`
   (face parsing přes ComfyUI-RMBG `FaceSegment` + `ClothesSegment`,
   **bez difuze**, sekundy) a stáhne čtyři masky — hair, face, hat, features
   (oči+obočí). Výstupy se párují podle prefixu jména souboru.
   Maska vlasů je **sjednocení dvou parserů** (`MaskComposite` `or`):
   `FaceSegment` (SegFormer na CelebAMask-HQ, tj. výřezy obličejů, vstup
   zmáčknutý na 512×512) na selfie z telefonu končí u hrudníku — 1,0 výšky
   tváře pod bradou, kde vlasy sahaly do 1,4 — a co nenajde, přežije
   přemalování (blond konce pod stříbrnými vlasy, dlouhé vlasy pod drdolem).
   `ClothesSegment` (SegFormer-B2 na ATR, celé tělo) dosáhne až ke koncům.
   Bench to nevidí: jeho předlohy mají vlasy oříznuté rámem přesně tam, kam
   face parsing dosáhne (`w-long` 1,02 = spodní okraj). Změřeno 2026-09-17
   na reálných selfie, `MangaPrompts/docs/hair-matrix.md`.
2. `buildHairMask` + `estimateHairColour` (`lib/models/hair_mask.dart`) v
   isolate: stará vlasy + čepice (dilatace), pás na čele u ofin, **obálka**
   podle délky (kam nové vlasy smí dorůst), minus obličej. Barva z *nasvícených*
   pramenů (50.–90. percentil jasu v jádru masky) — medián padal do stínů.
   **`keep` nemá obálku**: maska je jen stará silueta. To je správně pro
   ofinu, drdol a „Jen barva“, které žijí tam, kde staré vlasy jsou; styl
   bez ofiny a bez `updo` (vlny, kudrliny, copy) s `keep` neměl na staženém
   nebo krátkém účesu kam růst a vrátil se jako useknuté mikádo. Takové
   styly proto v katalogu nesou `long`; `test/hairstyle_catalog_test.dart`
   i `tgbot/tests/test_bench_catalog.py` invariant hlídají.
   Soubor je **zrcadlo** `MangaPrompts/tgbot/hairmask.py`: stejné konstanty,
   stejné kroky, stejná fixture v testech (`test/hair_mask_test.dart` ×
   `tgbot/tests/test_hairmask.py`). Měnit spolu; čísla kalibruje Tsumiki bench.
   Fotka bez použitelné tváře skončí `HairMaskException` dřív, než vznikne node.
3. Běžný `inpaint()` s `hairstyleId` → node s maskou (retry, resume, badge ve
   stromu i FINETUNE export fungují beze změny) → `ComfyUIService.hairInpaint`,
   tj. `prepareHairInpaint`: tentýž inpaint graf modelu, ale
   `mask_fill_holes: false` (obličej je v masce díra a vyplnění ho přemalovalo —
   Tsumiki bench kolo 0b, identita 0.11) a kontext 1.5.
   FLUX presety jedou `flux_hair_kontext.api.json` (Kontext + složení přes
   masku). Kontext výstup posune/zmenší až o 6 % — bez zarovnání byl přes čelo
   pruh starých vlasů a u krku dvojitý límec. Graf proto volá node
   `TsumikiAlignToReference` (MangaPrompts `comfyui_nodes/ComfyUI-Tsumiki`,
   nasazuje `comfyui_nodes/deploy.sh`); ComfyUI bez něj graf odmítne.
   Měkký okraj kompozitu (`GrowMaskWithBlur`) se škáluje podle fotky
   (`hairFeatherPx`: 0,6 % / 1,5 % delší strany, čte se z hlavičky masky,
   takže funguje i pro retry). Šablona má 6/12 px, což sedí benchi s 1216 px
   předlohami a na 2576 px fotce to byl tvrdý šev; SDXL crop si mísí sám
   (`mask_blend_pixels`). Blob zůstává i pro Kontext: jeden rovný šev je
   lepší než šev kolem každého pramene, který by zbyl po siluetě.

**Barva vlasů**: list má nahoře řadu barev (`kHairColours`, `HairColourPreset`
s frází do promptu, zrcadlo MangaPrompts `tgbot/haircolours.py`). Barva jde
s účesem, nebo sama přes „Jen barva“ — pak `hairstyleId` = `keep-cut`
(`kKeepCutPreset`) a maska je v režimu `hair` (jen stará silueta, bez obálky),
protože střih zůstává. Katalog barev je generovaný z gate stejně jako účesy.

Prompt = `hairPrompt()` z
`lib/models/hairstyle_preset.dart`, doslova Tsumiki `hairPrompt` s dosazenou
barvou. Katalog `kHairstyles` (`hairstyle_catalog.dart`) je **generovaný**
(`MangaPrompts/tgbot/tools/bench/export_catalog.py --ol1nllm`) z verdiktů
benche (`MangaPrompts/docs/hair-matrix.md`); s prázdným katalogem je akce
skrytá.

**Gate je per engine, ne průnik** (`HairstylePreset.engines`,
`HairColourPreset.engines`): položka se veze, jakmile ji přijme *jeden* engine,
a nese který. Enginy si totiž protiřečí v obou směrech — Kontext udrží
platinovou blond, kde ji SDXL přemaluje na hnědou (`colour_ok 0%`), a SDXL
udrží rozpoznatelné mikádo nebo pixie, kde je Kontext ztratí
(`recognised 33%`). Průnik zahazoval 20 změřených položek, většinu běžných
střihů: katalog vyrostl ze 7 účesů + 8 barev na **29 + 17** (15 na obou,
11 jen Kontext, 20 jen SDXL).

Model proto vybírá **účes, ne naopak** (`planHairRun()`): styl určí engine,
engine určí model. Kdyby rozhodoval vybraný model, byl by styl změřený jen na
SDXL dostupný náhodou — podle toho, čím uživatel zrovna generoval. Enginy mají
napevno svůj model, `kHairEngineModel`: Kontext = `flux-fill`, SDXL =
`juggernaut-xl`, protože právě `Juggernaut-XL_v9_RunDiffusionPhoto_v2` bench
měřil; jiný SDXL checkpoint tentýž graf vyrenderuje, ale žádný verdikt ho
nepokrývá. Model už vybraný se drží, jen když je jedním z těch dvou.
Když styl a barva nemají společný engine (blond lob — blond prošla jen na
Kontextu, lob jen na SDXL), **vyhraje styl** a `HairPlan.note` to řekne:
odmítnout věrohodný požadavek je horší než ho spustit s výhradou, a úkol gate
je říkat pravdu, ne zakazovat. Řádek účesu v `HairSheet` má **náhled**
(`assets/hair/<id>.jpg`, `HairstylePreset.preview`): výstup benche pro ten
účes na primárním syntetickém portrétu skupiny — na každém řádku tatáž tvář,
takže oko srovnává jen vlasy; žádné stock fotky ani osobní data. Chip barvy
nese **vzorek** (`HairColourPreset.swatch`): barvu, kterou bench na přijatých
buňkách *naměřil*, ne cílový rozsah. Obojí generuje `export_catalog.py
--bench/--colours-bench` spolu s katalogem; `test/hairstyle_catalog_test.dart`
spadne na položce bez náhledu nebo vzorku i na náhledu bez položky. Lab: flow `hair` + `lab hairmasks`
(`tools/lab/README.md`).

## Tančící figurka (`FigureService`, UGCFactory `ugc.ol1n.com/v1/fc`)

Tlačítko 3D na dlaždici nabízí dvě věci: **3D model k tisku** (Trellis2 →
STL/GLB, beze změny) a **tančící 3D figurku**. Figurku dělá fantasy-character
pipeline z repa UGCFactory na NAS: RMBG a TRELLIS na SPARKu, pak v Blenderu
na NAS úklid meshe, kostra (šablona i MIA, vyhraje ta, co se v tanci míň trhá),
přenos tanců a export GLB. 6–10 min. Stejný CF Access token jako zbytek —
`ugc.ol1n.com` pouští jakýkoli platný service token účtu. URL jde přebít
`UGC_FC_URL` (LAN `http://joda:8095` jen s `make debug`).

- Figurka dostane **všechny tance** z `GET /animations?category=dance`
  (katalog `availableDances`, app-scoped jako `availableScenes` — každé místo,
  které staví stav znovu, ho musí přenést; hlídá to `test/figure_test.dart`).
  Jedno GLB tak nese všechny klipy a v prohlížeči se přepínají bez nového kola.
- **glTF animace se jmenují podle id klipu** (server tak pojmenuje NLA tracky),
  takže `FigureViewerScreen` přehrává tanec jen přes `animation-name`. Při
  změně tance se `<model-viewer>` staví znovu (klíč podle klipu): měnit atribut
  živě by chtělo `WebViewController`, a ten model_viewer_plus dává jen přes
  přímou závislost na webview_flutter.
- Uzel `GenNode.isFigure` se chová jako 3D/video: `jobId` = id postavy na
  serveru, obnova přes `FigureService.follow`, retry s id jen dotáhne výsledek.
  Po dokončení zůstane `figureId` (jobId se maže) a `clipIds` v pořadí na časové
  ose. Průběh: stav postavy říká **poslední hotový** krok, běžící je ten další
  (`figureProgress` → `figureStageLabel`).
- Stažení GLB se kontroluje proti délce v hlavičce glTF (`glbLooksComplete`) —
  uříznuté stažení projde jako 200 a prohlížeč by pak ukázal prázdno.
- Tvář z TRELLISu je rozmazaná a mesh se v tanci trochu natahuje; jako figurka
  obstojí, jako fotka ne. Nejlepší vstup je celá postava stojící čelem. Měření
  kvality koster a přenosu tanců: UGCFactory `nas/docs/FANTASYCHARACTER_PLAN.md` §13.

## Identita ve videu (`tools/facebench/vidbench.py`)

Tatáž stupnice, ale pro klip s **dvěma** lidmi (couple karta v Tsumiki,
`MangaPrompts/reports/couple_phase0.md`). `bench.py` měří **největší** obličej
v obrázku, takže u dvojice měří jednoho člověka a podle velikosti bboxu
nedeterministicky jednou A a jednou B; `vidbench.py` proto doplňuje čtení po
snímcích a párování detekcí na osoby, zatímco `embedding()`/`sim()` importuje,
aby čísla zůstala porovnatelná s 0.48 / 0.72 z face inpaintu.

Párování je **prostorové, ne podle podobnosti**: obličeje se skládají do stop
přes IoU se snímkem předtím (stopa přežije 6 snímků výpadku) a teprve celá
stopa se přiřadí referenci podle průměrného embeddingu. Přiřazovat každý snímek
zvlášť „k té referenci, které je podobnější" by vybíralo maximum z dvojice a
skóre by se samo nafouklo. `margin` v souhrnu říká, o kolik je vítězné
přiřazení lepší než prohozené — pod ~0.05 jsou ti dva zaměnitelní a číslům
se nedá věřit.

Gate je **p10 čistých snímků**, ne minimum, a okludované snímky o pass/fail
nerozhodují (polibek, profil a zavřené oči srážejí skóre z důvodů, které nejsou
selhání identity). Bez okluzní mapy z preprocesu se čistota odhaduje z detekce
(`det_score`, |yaw|, velikost tváře); pipeline může předat vlastní seznam přes
`--clean-frames`. Práh patří kalibrovat per akce, proto se `--action` zapisuje
do CSV — prahy se odvodí z naměřených běhů, nevymýšlejí se dopředu.

Ověřeno na SPARKu na syntetickém klipu (dvě tváře, křížení, změna velikosti,
mp4 komprese): stopy přežily přiblížení (200/200 snímků), přiřazení je nezávislé
na pořadí `--refs`, margin 0.78 a cross-podobnost 0.17–0.20. **Rychlost gate:
200 snímků × 2 osoby = 69 s** (0,35 s/snímek) — InsightFace na SPARKu jede na
`CPUExecutionProvider`, protože onnxruntime v ComfyUI venv nemá CUDA EP.

⚠ **Stupnice je slepá na profil proti čelní referenci.** Změřeno na couple
klipu: týž klip proti *profilovému* výřezu téhož člověka dá medián 0.52–0.61,
ale proti **čelní** referenční fotce 0.05–0.17 — i pro obrázek, který
z reference evidentně je. Rozdíl není v identitě, ale v úhlu. Proto jsou prahy
čistoty (`--max-yaw`, `--min-det`, `--min-face`) parametry, ne konstanty, a
proto gate u akcí, kde jsou obličeje z definice v profilu (polibek, objetí),
nemá data — což je poctivější než vyrobit číslo, které nic neměří.
