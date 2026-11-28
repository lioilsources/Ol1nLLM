# Lab (`tools/lab/`)

Přesunuto z `CLAUDE.md`.


Nástroj pro otázku „co který model udělá s kterým promptem a nastavením".
Webové UI (`make lab`, běží na 127.0.0.1:8765) i terminál (`lab run`,
`lab score`, `lab check`) nad jednou Go binárkou; `make lab-dry` projede vše
bez ComfyUI a s placeholdery.

**Workflow staví kód appky** — `tools/lab/dump.dart` běží pod `flutter test`
a volá `ComfyUIService.prepareForTest` → `_prepare`, takže lab měří to, co
appka opravdu posílá. Modely, styly i pózy se čtou z registrů (`kImageModels`
prořezané podle nainstalovaných checkpointů, `kStylePresets`, `kPoseTemplates`)
a přes `manifest.json` tečou do UI — Dart zůstává jediným zdrojem pravdy.
Styly jdou v pořadí pickeru appky (`kStylePresetsSorted`) i s `labelWithYear`;
UI tím pořadím řadí panel, řádky výstupu i čipy filtru až při vykreslení, takže
i staré běhy (baseline první, kandidáti mimo registr hned za ní).

**Modely bez grafu (gen-queue / NIM)**: `flux-schnell` jede přes gen-queue, ne
ComfyUI, takže do `wf/<id>.json` jde místo grafu **request body** — a staví ho
zase appka (`FluxNimService.requestBody()`, kvůli tomu je to pojmenovaná
statická metoda a ne literál uvnitř `_infer`). `ManifestCell.backend`
(hodnoty z `image_backend.dart`, prázdno = starý běh = `comfyui`) rozhoduje
v `runner.go`, jestli se buňka pošle do ComfyUI, nebo přes `nim.go` do fronty
(submit 202 → poll 3 s → `/result`). CF Access token je tentýž, takže 401/403
zůstává `HTTPError` a strop „3× auth chyba = konec běhu" platí i tady.
Osy: **prompt, styl, seed** (+ laboratorní `param.stylePosition` /
`qualityPrefix` / `styleDialect`). Všechno ostatní — LoRA, póza, tvář,
`KSampler.*`, `LATENT`, img2img — je uzel grafu, který neexistuje, takže se
buňka **přeskočí s důvodem**; tiše ignorovat páčku by vyrobilo obrázek, co
vypadá jako její měření. Nepovinný override (`?cíl`) mixovaný plán pustí,
sweep na uzel ne (identické varianty pod různými štítky). 1024×1024 a 4 kroky
jsou napevno, protože je appka nenabízí — vystavit je jako osu by znamenalo
měřit něco, co appka neumí vyrobit. Motivace: `docs/style-matrix.md`
flux-schnell nikdy neměřil, takže jeho `styleNote` je jediný v registru bez
verdiktu za sebou. `flux-kontext` v labu není — img2img by chtěl referenci
dovnitř requestu.

Postup je **plán → dump → prohlédnout → generovat**: dump je zadarmo a vyrobí
přesný seznam buněk dřív, než se sáhne na GPU. Ke každému modelu se dumpuje
i `__baseline` (týž prompt bez stylu), bez kterého nejde odlišit „model na
styl reaguje" od „tohle maluje pokaždé". Generování je resumovatelné.

Sweep míří **na uzel** (`__cn_apply__.strength`, `KSampler.cfg`, `#5.steps`,
`param.editDenoise`), ne na jakýkoli vstup daného jména; cíl bez shody je
chyba, aby nesmyslný běh spadl před GPU, a chybí-li jen u některých modelů
(flux-manga mimo repose nemá `__cn_apply__`), přeskočí se ty buňky s uvedeným
důvodem. **`KSampler` ale flux-manga má** (zapečené cfg 1.0) — sweep
`KSampler.cfg/steps` ho zasáhne, nepřeskočí. `param.editDenoise` dostane jen
img2img; v txt2img a repose vzniknou totožné buňky. Co která volba sweepu
zasáhne (architektura × jazyk promptu × flow) je tabulka v
`tools/lab/README.md` („Nabídka sweep“). Čistá logika sweepů a overridů je
v `tools/lab/dump_spec.dart` a testuje ji `test/dump_spec_test.dart`.

Metriky (reakce vůči baseline, rozptyl stylů, změna proti předchozí hodnotě
sweepu) měří **barvu, ne převzetí stylu** — jsou k předvýběru, rozhodnout musí
pohled na obrázky. Kalibrace z reálného měření: `docs/style-matrix.md`.

**Tvář (ArcFace)**: v běhu s referencí se ke každé buňce spočítá podobnost
největší tváře k referenci — `tools/lab/arcface.py` přes lokální venv
(`make lab-arcface`, insightface **antelopev2** na CPU, modely zkopírované ze
SPARKu), volaný z `identity.go` při výpočtu metrik, cache `identity.json`
v adresáři běhu. Detekce i výběr největší tváře jsou stejné jako
`tools/facebench` a bench Kadeřníka, takže čísla sedí na stupnici 0.48 / 0.72
(šest buněk benche do 0.006). Chybějící venv nebo pád skriptu běh neshodí, jen
se místo čísel ukáže poznámka. **Mezi modely čísla nesrovnávat**: ArcFace je
naučený na fotkách a u anime modelů vychází blízko nuly (noobai-xl s InstantID
0.06, juggernaut-xl 0.68) — nízké číslo tam neodliší jiného člověka od
nakreslené tváře; čte se hodnota sweepu v rámci modelu.

**Prompty po rodinách (`--prompts-yaml`, v UI pole pod textem promptů)**: YAML
`jméno: {danbooru, juggernaut, flux}` — týž námět napsaný pro tagový
checkpoint, fotoreal SDXL a FLUX, aby šly položit vedle sebe pod jedním seedem
místo tří běhů. **Rodinu vybírá model, ne soubor**: `PromptDialect.booru`
⇒ `danbooru`, jinak dedikovaný graf / gen-queue ⇒ `flux`, generická SDXL
šablona ⇒ `juggernaut` (`promptFamilyFor()` v `dump_spec.dart`; nový model se
zařadí sám). Tři koše proti dvěma hodnotám `PromptDialect` — přirozená půlka
se dělí znovu, protože věta pro Juggernaut není věta pro FLUX; je to
**laboratorní** pojem, ne pole na `ImageModelSpec`, appka má jedno pole
promptu a nikdy by ho nečetla. Textové pole se s tím **násobí** (každý řádek
je prefix přes všechny prompty ze souboru), prázdné pole = prázdný prefix.
Chybějící rodina **zastaví běh** — fráze poslaná tagovému modelu vyrobí
obrázek, co vypadá jako měření toho promptu a není jím; odhad to řekne před
startem (manifest nese `promptFamily` na modelu), dump je pojistka. YAML parsuje
**Go** (`promptbodies.go`, první závislost modulu — `gopkg.in/yaml.v3`), protože
odhad potřebuje počet na každý úhoz; do `dump.dart` jde už normalizovaný JSON
v adresáři běhu, takže parser je v systému jediný a resume hraje tytéž prompty.
`manifest.prompts` nese **popisky** sloupců (text se liší model od modelu),
buňka `promptBody` a v `prompt` text přečtený zpátky z grafu. Ukázka:
`candidates/prompts-example.yaml`.

**Tagy z předlohy (`--ref-tags`, v UI zaškrtávátko pod referencí)**: WD14
booru tagy předlohy se připojí za každý prompt, s prázdným polem jsou promptem
samy — img2img z fotky na booru modelu bez psaní. `tools/lab/wd14.py` je
zrcadlo taggeru FINETUNE gallery (týž model, preprocess i prahy), běží lokálně
na CPU (`make lab-wd14`). Tagy popisující fotku jako médium (`realistic`,
`photo (medium)`, `blurry`…) se vynechávají, jinak by booru model táhly zpátky
k fotce. Běh je ukládá do `ref-tags.json`, ne do `spec.json`. Podrobnosti:
`tools/lab/README.md`.

**Pozice → restyle (flow `restyle`)**: běh se dvěma modely — `--base-model`
(v UI „model pozice“) nakreslí z textu fotku, `--models` ji přemalují do stylu
přes ControlNet nad txt2img šablonou (graf „zachovej pózu“). Model pozice
může být i `qwen-image` (je i v appce, jen txt2img), čte sloupec `flux`
i negativ, podrobnosti v `tools/lab/README.md`. Prompt má tři
vrstvy: pozice (`--prompts-yaml`, YAML i CSV `id,juggernaut,pony,flux,negative` — negativ pozice se připojí za negativ běhu, v obou krocích),
postava (`--characters`, řádek = postava) a styl; první krok dostane pozici
+ postavu, druhý všechny tři. Fotka vzniká jednou na pozici × postavu, buňka
restylu ji nese jako `dependsOn` / `hintImage` a runner jede fotku po fotce
(`position`, upload a přepsání `LoadImage`, hned její restyly; staré pořadí
„nejdřív všechny fotky“ vrací `LAB_STAGE_ORDER=photos-first`). `--hint depth|canny`
(osa `param.hint`): hrany jsou **jen laboratorní** cesta přes
`StructureHint` v `comfyui_service.dart`, appka posílá vždy hloubku.
Podrobnosti a co se přeskakuje: `tools/lab/README.md`.

**Kandidáti stylů**: `--styles-file` čte `id/label/block` a volitelně
`booru/artist/period`, ostatní klíče toleruje. Id, které v souboru chybí, se
vezme z registru — kandidát tak stojí ve stejné tabulce jako styl, se kterým
by mohl být duplicitní; id, které není nikde, shodí dump před GPU. Text stylu
se volí **per buňka** podle `promptDialect` modelu a manifest ho nese jako
`styleText` (plus `params.styleDialect`); osa `param.styleDialect=natural|booru`
dialekt přebije. Přerušený běh z terminálu dokončí `lab resume DIR` — totéž
co *Pokračovat* v UI, bez nového dumpu. Doplní každou buňku bez obrázku, tedy
i selhané (restart ComfyUI uprostřed běhu odepíše zbytek fronty na HTTP 502
během vteřin); z kořene repa `make lab-resume [RUN=<id>]`, bez RUN poslední
běh. UI u doběhlého běhu s chybami nabízí *Doplnit selhané*.

**Proč anime modely styl nepřevezmou** — dvě laboratorní osy a jeden soubor:
`param.stylePosition=end|front|first` (appka posílá `end` = prefix, námět,
styl, v repose `front`; flow `restyle` a `repose` mají výchozí `front` —
měření v `tools/lab/README.md`) a `param.qualityPrefix=on|off` (tagy estetického hodnocení z
`positivePrefix`, u NoobAI `very awa`, jdou první a CLIP je váží nejvíc).
Skládá je `composeCellPrompt()` v `dump_spec.dart`; builder má kvůli tomu
`positivePrefix: false`, výchozí `true` appku mimo repose nemění. A
`tools/lab/candidates/cultural-booru.json`: booru tagy pro 39 kulturních stylů,
které je v registru nemají (booru text měli jen umělci), s bloky převzatými
z registru — sweep `param.styleDialect=natural|booru` nad tímto souborem je
přímé srovnání. Tagy jsou **návrh k měření**, ne verdikt; motivy, které by
měnily obsah místo stylu (vousy, tetování mimo polynéský styl, roucha, tygr,
„x-ray“, anatomie), jsou vynechané a zapsané v poli `note`.

**LoRA a trigger words**: ovládací panel nabízí LoRA živě ze serveru,
seřazené podle `loraFit` vůči vybraným modelům (bez modelu podle linie);
za jménem jsou v závorce **trigger words** čtené z hlavičky souboru
(`GET /view_metadata/loras`) — výslovné pole > tagy s pokrytím ≥ 99 %
> názvy trénovacích složek, booru boilerplate a složky pod 8 obrázků
vypadávají. Cache `build/lab/lora-triggers.json` je trvalá (hlavička se
nemění). LoRA je i osa sweepu (`param.lora`, hodnota `none` = buňka bez ní;
`param.loraStrength`), nekompatibilní kombinace se přeskočí s důvodem už
při plánu.

**Zachovat tvář**: `--face-identity=none|instantid|faceid|both` a
`--face-detail` (v UI blok „tvář“ pod pózou; checkbox dotažení je aktivní jen
s identitou). Osy sweepu `__face_apply__.ip_weight` a
`__face_apply__.cn_strength` (InstantID), `__face_apply__.weight` (PuLID),
`param.faceIdentity`, `__face_detail__.denoise`. Manifest u každé buňky nese `faceIdentity`
a `faceDetail` **čtené z grafu**, takže flux napíše `pulid`, i když se
objednal `faceid`. Odhad varuje předem tam, kde by přepínač tiše nic
neudělal: bez repose/depth flow (není odkud tvář číst), detailer bez
identity, a batch > 1 s detailerem (nezměřené). Podmínku „je odkud číst tvář"
počítá `Spec.hasDepthSource` — pozor na img2img větev, auto-depth u SDXL se
snadno zapomene a varování by pak lhalo.

Prohlížeč nemůže volat ComfyUI přímo (nevrací CORS hlavičky a CF Access
odmítá preflight 403), proto ten lokální server; drží CF creds, takže
poslouchá jen na loopbacku a mutující požadavky chtějí `X-Lab-Token`.

**Video napříč běhy (`lab video`)**: index všech obrázků všech běhů podle os
(model, styl, prompt, flow…), rodiny běhů se stejnými prompty, matice pokrytí
a návrhy, které modely dát vedle sebe. Plán `docs/plan-video-studio.md`,
návod `tools/lab/README.md`. Recept v YAML, `lab video plan` (scénář bez
renderu), `lab video render` / `make lab-video` (Go + ffmpeg, výstup
`build/lab/_video/<jméno>/`). Studio ve Svelte na `/video/` (odkaz „video →“
v hlavičce labu): rodiny běhů, pokrytí, skladba, náhled a render bez terminálu.

**Kompletní matice z jedné fotky** (`make lab-complete REF=…`,
`tools/lab/complete.sh`): repose s tváří přes všechny SDXL modely × všechny
styly a na čtyřech modelech, které danbooru tagy znají, přes nativní umělce
a postavy (`TOP=100` = sto s nejvíc díly na danbooru, pořadí v
`candidates/native-*-ranked.tsv`). Strop 400 buněk se ho netýká — hlídá ho jen
server pro UI. Běží sám po částech v oknech, kdy na SPARKu jede ComfyUI
(07:10–12:50), a navazuje. Na sdíleném GPU se runner chová ohleduplně přes
`LAB_SHARED_PAUSE` (čeká na prázdnou frontu, pauza mezi buňkami)
a `LAB_MAX_CELL_SECONDS` / `LAB_MAX_FIRST_CELL_SECONDS` (pomalá buňka = pád na
CPU ⇒ konec běhu); podrobnosti a podmínky dohodnuté s plánovačem SPARKu jsou
v `tools/lab/README.md`.

**Odeslání běhu do FINETUNE gallery**: `lab export DIR --send` (nebo tlačítko
u dokončeného běhu; odesílání je opt-in, protože galerie nemá mazací
endpoint). Jedna buňka = jeden uzel; předloha běhu je kořenový uzel
(`origin: upload`) a buňky pod ním. Sampler/steps/cfg se čtou z odeslaného
grafu, ne z presetu (po sweepu preset neplatí). Session i uzly mají UUIDv5
odvozené z id běhu, takže re-export doplňuje tutéž session. Placeholdery
z dry-runu se neposílají. Galerie má vlastní registr modelů (repo
FineTuneGallery, `server/meta.go`) — lab se na něj před odesláním zeptá přes
`/api/meta` a modely, které v něm nejsou, vyjmenuje: obrázky dojdou, ale
nepůjde podle nich filtrovat.
