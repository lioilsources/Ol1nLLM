# lab

Dávkové experimenty nad ComfyUI: **co který model udělá s kterým promptem,
stylem a nastavením** — a co je přitom vlastně v grafu zapojené.

```bash
make lab          # webové UI na http://127.0.0.1:8765
make lab-check    # jen ověří prostředí (flutter, CF Access, fronta)
make lab-dry      # projede vše bez ComfyUI — na ověření nastavení, ne na výsledky
```

Nanečisto (`lab-dry`, nebo přepínač *režim* v UI) místo obrázků vyrábí
šrafované placeholdery. Je to způsob, jak ověřit, že dump, tabulka, panel
zapojení a metriky fungují, aniž by se sáhlo na GPU — ne způsob, jak něco
vygenerovat.

Workflow **staví kód appky** (`tools/lab/dump.dart` volá
`ComfyUIService.prepareForTest` → `_prepare`), takže lab měří to, co appka
opravdu posílá, ne napodobeninu, která se časem rozejde. Modely bere
z `kImageModels` prořezaných podle nainstalovaných checkpointů, styly
z `kStylePresets`, pózy z `kPoseTemplates` — nová položka v registru se
v labu objeví sama.

## Jak to běží

```
plán → dump → prohlédnout → generovat
```

Dump je zadarmo (bez GPU, jeden boot `flutter test`) a vyrobí přesný seznam
buněk i jejich zapojení. Tabulka se vykreslí s placeholdery **dřív**, než se
sáhne na GPU — proto sweep nemůže překvapit. Ke každému modelu se navíc
dumpuje `__baseline` (týž prompt bez bloku stylu); bez něj nejde odlišit
„model na styl reaguje" od „tohle maluje pokaždé".

Výstup jde do `build/lab/<čas>/`: `wf/` (workflow + `manifest.json`), `img/`,
`thumb/`, `state.json`, `metrics.json`, `dump.log`. Generování je
**resumovatelné** — hotové buňky se přeskakují, takže restart serveru ani
zavření prohlížeče nic nestojí.

## Terminál

```bash
lab check                                   # flutter, CF Access, fronta ComfyUI
lab run --subject "a ballerina" --models juggernaut-xl,pony \
        --styles ukiyoe,baroque --flows txt2img,repose --ref foto.png
lab run --ref-prompt "photo of a dancer" --sweep '__cn_apply__.strength=0.5|0.75|1.0'
lab resume build/lab/20260826-0023          # dopočítat přerušený běh
lab score build/lab/20260826-0023
lab export build/lab/20260826-0023 --send   # do FINETUNE gallery
```

`lab resume` je totéž co tlačítko *Pokračovat* v UI: generuje jen buňky bez
obrázku a drží workflow, se kterými běh začal — znovu nedumpuje, takže
navázání po zabitém terminálu stojí jen to, co opravdu chybí.

## Kandidáti stylů

Styly, které ještě nejsou v `kStylePresets`, se ověřují ze souboru:

```bash
lab run --subject "a ballerina" --models juggernaut-xl,pony --flows repose \
        --ref foto.png --styles-file candidates/artists.json \
        --styles monet,impressionist
```

Soubor je pole `{id, label, block, …}`; čte se i `artist` a `period`.
Ostatní klíče se tolerují — kandidátský soubor je pracovní dokument a pole
mu přibývají dřív než appce. Chybějící `id` nebo `block` je chyba už
v odhadu, ne až v dumpu.

`--styles` soubor zužuje a **id, které v souboru není, se vezme z registru**.
Kandidát tak stojí ve stejné tabulce, pod stejným seedem a předlohou, jako
existující styl, se kterým by mohl být duplicitní (`monet` × `impressionist`),
nebo jako nejslabší styl registru, který určuje laťku reakce. Id, které není
nikde, shodí dump dřív, než se sáhne na GPU.

Kandidát může mít i `booru` — tentýž styl v danbooru tazích. Dostanou ho
modely s `promptDialect: booru` (Pony, Illustrious, anime SDXL), ostatní
`block`; bez `booru` jde `block` všem. Každá buňka manifestu proto nese
`styleText` — text stylu, který model opravdu dostal — a v parametrech
`styleDialect`. Ukazuje je tooltip buňky a zásuvka.

`candidates/cultural-booru.json` doplňuje booru text 39 kulturním stylům, které
ho v registru nemají (s bloky převzatými z registru, takže `natural` pošle
přesně to, co appka). Tagy jsou návrh k měření; co by měnilo obsah místo stylu
(vousy, roucha, tygr, „x-ray“, anatomie), je vynechané a popsané v `note`.

Osa `param.styleDialect=natural|booru` pošle všem modelům tentýž dialekt bez
ohledu na jejich vlastní. Tak jde srovnání tagů s frázemi zopakovat bez ručně
psaných variant id (viz ablace třetí vlny v `docs/style-matrix.md`).

## Účesy (flow `hair`)

Kadeřník v appce (dlaždice → nůžky) je inpaint s maskou, kterou nikdo
nekreslí: face parsing na serveru najde vlasy a tvář, `lib/models/hair_mask.dart`
z nich postaví masku podle tvaru účesu. Lab to rozděluje na dva kroky, protože
dump běží bez sítě:

```bash
lab hairmasks --ref portret.png                 # analýza + masky pro všechny tvary
lab run --flows hair --ref portret.png --hair-masks build/lab/hairmasks/portret \
        --models flux-fill,juggernaut-xl --hairstyles pixie,wolf-cut,m-buzz \
        --subject "-"
```

`hairmasks` nahraje referenci, pustí `assets/comfyui/hair_analyse.api.json`,
stáhne čtyři masky (výstupy páruje podle prefixu jména, ne podle pořadí), přes
`tools/lab/hairmask.dart` postaví masku pro každý **tvar** z kandidátů
(`candidates/hairstyles.json`, kopie z MangaPrompts bench) a nahraje je na
server. Odmítnutý tvar (bez tváře, málo vlasů) se zapíše do `masks.json` a dump
jeho buňky přeskočí s důvodem. Buňka = model s `inpaint` × účes × varianta;
styly ani prompty se nenásobí (`--subject` je jen formalita CLI). Graf staví
`ComfyUIService.prepareHairInpaint`, tedy totéž, co pošle appka.

Z hodnocení účesů lab spočítá jen identitu (metrika *tvář*, stejná stupnice
jako bench); délku, ofinu a CLIP rozpoznání dělá
`MangaPrompts/tgbot/tools/bench/score.py` na SPARKu,
výsledky jsou v `MangaPrompts/docs/hair-matrix.md`. Webové UI flow `hair`
nenabízí, jen terminál.

## Sweep a override

Jedna osa na běh. Cíl se míří **na uzel**, ne na jakýkoli vstup daného jména:

| tvar | význam |
|---|---|
| `__cn_apply__.strength` | syntetický uzel vložený appkou |
| `#5.steps` | id uzlu ze šablony |
| `KSampler.cfg` | všechny uzly té třídy |
| `param.editDenoise` | skutečný parametr `_prepare` (znovu volá builder) |
| `?<cíl>` | nulová shoda tolerována |

**Cíl bez jediné shody je chyba.** Sweep síly ControlNetu nad flow, kde žádný
ControlNet není, je nesmyslný běh a má spadnout před GPU. Když cíl chybí jen
u některých modelů (flux-manga mimo repose nemá `__cn_apply__`), přeskočí se
ty buňky a důvod je vidět v tabulce.

Rozdíl, na kterém záleží: `steps/cfg/sampler/scheduler/rozměry` **přebíjejí
preset modelu** — sweep je nastaví všem stejně, takže rozbije kalibraci
(juggernaut-lightning má 6 kroků schválně) a výsledek pak není verdikt
o modelu; takové buňky mají v tabulce odznak. Naproti tomu
`editDenoise/seed/latent/pose` jsou parametry flow a chovají se jako v appce.

**`KSampler` má i flux-manga.** Jeho šablony (`flux_manga_*.api.json`) mají
sampler zapečený (cfg 1.0, euler/simple, 20 kroků txt2img, 28 img2img) a
`_prepare` ho nepatchuje, protože `ckptName == null`. Sweep `KSampler.cfg`
nebo `.steps` ho ale **zasáhne** — ověřeno nanečisto, uzel `18`, 0 přeskočených
buněk. FLUX je distilovaný na cfg 1: vyšší hodnota zdvojí čas a obraz zhorší.
Odhad běhu na to varuje jen u sweepu nebo overridu `KSampler.*` („sampler
zapečený v šabloně … přepíše“); jiné cíle (seed, LoRA) flux-manga dostane jako
každý jiný model.

### Modely: architektura a jazyk promptu jsou dvě osy

Lab nabízí jen ComfyUI modely (NIM flux-schnell / flux-kontext ne), prořezané
podle checkpointů na serveru.

| skupina | modely | jazyk promptu (`promptDialect`) |
|---|---|---|
| SDXL, fotoreal | `juggernaut-xl`, `juggernaut-xl-lightning` | věta (`natural`) |
| SDXL, anime | `pony`, `atomix-pony-anime`, `illustrious-xl`, `noobai-xl`, `wai-illustrious`, `animagine-xl` | booru tagy |
| FLUX | `flux-manga` (txt2img, img2img, repose), `flux-fill` (jen inpaint) | věta |
| SD 1.5 | `sd15` (bez ControlNetu, bez pózy) | věta |

**Architektura** (SDXL / FLUX / SD 1.5) rozhoduje, co se do grafu dá zapojit:
LoRA (`loraFamily`, viz níž), ControlNety, metodu tváře. **Jazyk** rozhoduje,
jak se píše prompt a který text stylu se pošle. Všechny booru modely jsou SDXL,
ale ne každý SDXL je booru — Juggernaut čte věty a tagy mu nepomáhají. Obě osy
se nekryjí ani u LoRA: `animagine-xl` má LoRA rodinu `sdxl` jako Juggernaut,
a přitom čte tagy.

### Nabídka „sweep — jedna osa“ v UI

| volba | cíl | výchozí hodnota | koho zasáhne |
|---|---|---|---|
| síla ControlNetu | `__cn_apply__.strength` | šablona pózy 1.0, auto hloubka 0.7, repose 0.75, repose flux 0.55 (odhad) | SDXL se šablonou pózy, SDXL img2img bez šablony (auto hloubka), repose a `POSE_MODE=depth`; flux-manga jen v repose. `sd15` nikdy |
| konec ControlNetu | `__cn_apply__.end_percent` | 1.0, repose 0.9 | jako řádek výš |
| síla úpravy | `param.editDenoise` | preset `img2imgDenoise` (~0.72) | jen **img2img** u generické šablony (SDXL + `sd15`). Šablona pózy ji přebije (0.9), inpaint jede na 1.0, flux-manga má denoise zapečený. V txt2img a repose se builderu vůbec nepředá — buňky vzniknou, ale jsou totožné |
| cfg ⚠ | `KSampler.cfg` | preset (SDXL 5–6.5, Lightning 2.0, flux 1.0) | **všechny** modely včetně flux-manga (viz výš) |
| kroky ⚠ | `KSampler.steps` | preset (SDXL 28–30, Lightning 6, flux 20/28) | všechny |
| seed | `param.seed` | 777 | všechny; na odhad, jestli je rozdíl styl, nebo šum |
| LoRA | `param.lora` | — (`none` = bez LoRA) | kombinace z jiné architektury (`loraFit` incompatible) se přeskočí už v plánu |
| síla LoRA | `param.loraStrength` | `kDefaultLoraStrength` 0.9, rozsah −1…2 | jen s vybranou LoRA |
| síla tváře — embedding | `__face_apply__.ip_weight` | 0.6 (odhad, ne měření) | **jen SDXL**, metoda `instantid`/`both`, a jen kde je odkud číst tvář (níž) |
| síla tváře — klíčové body | `__face_apply__.cn_strength` | 0.8 | jako řádek výš |
| síla tváře (PuLID) | `__face_apply__.weight` | 0.9 | **jen flux-manga** se zapnutou tváří v repose |
| metoda tváře | `param.faceIdentity` | `none` | SDXL: tři různé mechanismy; flux: každá hodnota je PuLID (manifest píše, co doopravdy běželo) |
| text stylu | `param.styleDialect` | jazyk modelu | jen s vybraným stylem; rozdíl dává jen styl s `booru` textem (umělci), kulturní styly posílají obě hodnoty stejně |
| síla dotažení tváře | `__face_detail__.denoise` | 0.4 | jen se zapnutou identitou **a** dotažením; SDXL i flux |
| pozice stylu | `param.stylePosition` | `end` (appka) | jen s vybraným stylem: `end` = prefix, námět, styl; `front` = prefix, styl, námět; `first` = styl, prefix, námět. Bez prefixu (Juggernaut, flux, nebo `qualityPrefix=off`) je `front` totéž co `first` |
| kvalitativní prefix | `param.qualityPrefix` | `on` (appka) | modely s `positivePrefix`: anime SDXL (`masterpiece, best quality…`, u NoobAI `very awa`) a pony score tagy. Juggernaut a flux žádný nemají, buňky vyjdou stejné |

Pozice stylu a prefix jsou **jen laboratorní osy** — appka posílá vždy
`prefix, námět, styl` (`applyStylePreset`, `_prepare`). Existují kvůli otázce,
proč anime modely styl nepřevezmou: CLIP váží dřívější tokeny víc a tagy
estetického hodnocení v prefixu jdou první. Skládání je v
`composeCellPrompt()` (`dump_spec.dart`), builder dostane `positivePrefix:
false`, když prefix píše buňka sama (`first`) nebo je vypnutý. Hodnoty jdou
i jako override pro celý běh: `--override 'param.qualityPrefix=off'`
a sweep pozice vedle toho. Manifest je u buňky nese v `params`, prompt
v tabulce je čtený zpátky z grafu.

„Odkud číst tvář“ = uzel `__depth_src__`: repose, `POSE_MODE=depth`, nebo SDXL
img2img bez šablony pózy (auto hloubka). Šablona kostry fotka není — tvářové
cíle tam nemají uzel a buňky se přeskočí. Síla FaceID
(`__faceid_apply__.weight`, 0.8) v nabídce není; z terminálu jde
`--sweep '__faceid_apply__.weight=0.6|0.8|1.0'`, stejně jako tvary `#id.vstup`
a `?cíl`.

## LoRA a trigger words

Nabídka LoRA v ovládacím panelu je **živá ze serveru**
(`/object_info/LoraLoader`) a není abecední — řadí se podle toho, jak která
sedí na vybrané modely, podle registru appky
(`lib/models/lora_family.dart`). Bez vybraného modelu se řadí podle linie.

Za jménem jsou v závorce **trigger words** — slova, na která soubor reaguje.
Nejsou hádaná z názvu; čtou se z hlavičky samotného `.safetensors` přes
`GET /view_metadata/loras`, ve třech úrovních důvěry:

| zdroj | co to je |
|---|---|
| `metadata` | výslovné pole s triggerem (`avatar_trigger`) |
| `tagy` | popisky, které měl **každý** trénovací obrázek (`ss_tag_frequency`, pokrytí ≥ 99 %) |
| `dataset` | názvy trénovacích složek, když soubor popisky nemá (`7_hoodie` → `hoodie`) |

Booru boilerplate (`1girl`, `solo`, `looking at viewer`) vypadává, i když
pokrývá celý dataset — napsat ho zpátky nic neudělá. Složka pod 8 obrázků
nemluví vůbec. Z 36 LoRA na serveru takhle vyjde trigger u 19 (17× z tagů,
1× z výslovného pole, 1× z názvu složky); zbytek hlavičku buď nemá, nebo v ní
není nic použitelného — a lab to řekne, místo aby si vymýšlel.
Vyčtená metadata se cachují v `build/lab/lora-triggers.json` — hlavička daného
souboru se nemění, takže se čtou jednou za život.

Tlačítko *vložit do promptů* předsadí triggery na začátek každého řádku
promptu (dřívější tokeny mají větší CLIP váhu — stejný důvod, proč appka
řetězí prompty odpředu).

Sílu bere lab z appky (`kDefaultLoraStrength`), rozsah je −1…2: záporná
hodnota koncept **odtlačuje**, proto má posuvník značku na nule.

LoRA je i osa sweepu:

```bash
lab run --subject "a ballerina" --models illustrious-xl \
        --sweep 'param.lora=none|style-usnr-thin-paint.safetensors'
lab run --subject "a ballerina" --lora style-usnr-thin-paint.safetensors \
        --sweep 'param.loraStrength=0|0.5|0.9|1.4'
```

`none` je hodnota jako každá jiná — dá buňku bez LoRA, tedy srovnávací
baseline uvnitř téhož sweepu.

Buňky, kde LoRA na model architekturou nesedne, se **přeskočí s důvodem**
(SD 1.5 LoRA na SDXL není no-op: UNet klíče nesedí, ale sdílený CLIP-L ano,
takže jen rozhodí prompt). Odhad to řekne dřív, než se pustí GPU — a když
nesedne na *žádný* vybraný model, je to blocker.

## Řazení tabulky

Sloupce jsou vždycky modely (omezená osa). Uvnitř flow se dá přepnout, co je
nadřazené:

- **styl → prompty pod sebou** (výchozí) — jeden styl, pod ním všechny prompty.
  Odpovídá otázce „drží ten styl napříč náměty?"
- **prompt → styly pod sebou** — jeden námět, pod ním všechny styly. Odpovídá
  otázce „co ten model udělá s mým promptem v různých stylech?"

Volba se pamatuje v prohlížeči.

## Odeslání do FINETUNE gallery

Hotový běh jde poslat do galerie na NAS (`finetune.ol1n.com`) — tam se výstupy
hodnotí a staví z nich LoRA datasety. Stejný protokol, jaký používá appka na
session (`lib/services/finetune_export_service.dart`), takže běh z labu a
session z telefonu dopadnou do stejné knihovny.

```bash
lab export build/lab/20260826-0023            # jen vypíše, co by šlo
lab export build/lab/20260826-0023 --send     # teprve tohle odesílá
```

V terminálu je u odesílání pruh podle **bajtů, ne obrázků** — buňky se
velikostí liší i trojnásobně, takže pruh počítaný z kusů by poskakoval:

```
  [████████████░░░░░░░░░░░░] 148/304  612 MB / 1.2 GB  8 MB/s  zbývá 1m14s
```

Když výstup neteče do terminálu (přesměrování, smyčka přes víc běhů), místo
překreslování se vypíše řádek po každé desetině.

V UI je u dokončeného běhu tlačítko; první klik se zeptá, druhý odesílá.
**Odeslání je opt-in schválně** — je to ven z počítače a galerie nemá mazací
endpoint.

Mapování: **jedna buňka = jeden uzel** (prompt, model, seed, jeden obrázek).
Když měl běh předlohu, visí buňky pod kořenovým uzlem s ní (`origin: upload`),
takže je v galerii vidět, z čeho matice vyšla; txt2img buňky jsou kořeny samy
o sobě. Sampler, kroky a cfg se čtou **z odeslaného grafu**, ne z presetu
modelu — po sweepu nebo overridu už preset neplatí a čísla u obrázku musí
sedět na obrázek.

Protokol je content-addressed a idempotentní: druhé odeslání téhož běhu
nepošle ani bajt obrazových dat navíc, jen doplní, co přibylo. Id session i
uzlů jsou UUIDv5 odvozené z id běhu a buňky, takže re-export míří na tutéž
session místo aby vyrobil druhou.

Neodesílá se: běh nanečisto (jsou to šrafy), buňky bez obrázku, buňky
přeskočené při dumpu. A když galerie nezná některý model z běhu (má vlastní
registr, který za appkou zaostává), řekne se to — obrázky dojdou, ale nepůjde
podle nich filtrovat, dokud ten model někdo do galerie nepřidá.

## Jak číst metriky

- **reakce** — vzdálenost od `__baseline` téhož modelu: „změnil ten blok stylu
  vůbec něco?"
- **rozptyl** — průměrná vzdálenost mezi styly v jedné skupině: nízká znamená,
  že model bloky stylů ignoruje.
- **změna proti předchozí hodnotě** — u sweepu: „udělal ten knob něco?"

Všechny tři měří **barvu, ne převzetí stylu**. Slouží k předvýběru; rozhodnout
musí pohled na obrázky. Kalibrace z reálného měření je v `docs/style-matrix.md`.

- **tvář** — ArcFace podobnost největší tváře v buňce k referenci běhu
  (`tools/lab/arcface.py`): 1.0 táž tvář, ~0.6 pořád táž osoba, pod 0.4 jiný
  člověk. Na dlaždici vlevo nahoře (zelená ≥ 0.6, žlutá 0.4–0.6, červená pod
  0.4, „bez tváře“, když detektor nic nenašel), v detailu buňky i s počtem tváří
  a výškou v px, a v `lab score` průměr a minimum po modelech a hodnotách sweepu.

Stejné modely (insightface **antelopev2**), detekce 640×640 a výběr největší
tváře jako `tools/facebench` a bench Kadeřníka, takže čísla sedí na jejich
stupnici: šest buněk benche na Macu vyšlo do 0.006 od hodnot ze SPARKu
(insightface 2.0 vs. 1.0.1 na výsledku nic nemění).

Jak číslo nečíst:

- **Mezi modely ne.** ArcFace je naučený na fotkách; u anime modelů vychází
  blízko nuly (běh `20260911-060721`: juggernaut-xl s InstantID 0.68, flux-manga
  0.32, noobai-xl 0.06) a nízké číslo tam neodliší jiného člověka od nakreslené
  tváře. Porovnávej hodnoty sweepu **v rámci jednoho modelu**.
- **Pod ~40 px výšky tváře** (celá postava v txt2img) je číslo šum.
- Počítá se jen v běhu s referencí (repose, img2img, depth), ne nanečisto.

Nastavení jednou: `make lab-arcface` — venv v `tools/lab/.venv` (insightface,
onnxruntime, OpenCV; první instalace chvíli sestavuje balíčky) a modely
zkopírované ze SPARKu do `~/.insightface/models/antelopev2` (437 MB). Jiné
cesty přes `LAB_ARCFACE_PYTHON` a `LAB_INSIGHTFACE_ROOT`. Bez nastavení běh
doběhne normálně a místo čísel ukáže, co chybí. Jede na CPU, ~0.4 s na buňku;
výsledky se ukládají do `identity.json` v adresáři běhu podle velikosti a času
obrázku, takže `lab score` nad hotovým během nic nepřepočítává a navázaný běh
spočítá jen nové buňky. Starší běh dostane čísla přes `lab score <adresář>`.

## Poznámky k prostředí

- CF Access creds se berou z `.env.local` (`CF_ACCESS_CLIENT_ID`,
  `CF_ACCESS_CLIENT_SECRET`). Bez nich server nastartuje a vysvětlí se —
  běh nanečisto funguje i tak.
- Server poslouchá jen na `127.0.0.1` a mutující požadavky chtějí
  `X-Lab-Token`, protože drží ty creds a jinak by na něj dosáhla kterákoli
  stránka v prohlížeči.
- Prohlížeč nemůže volat ComfyUI přímo: nevrací CORS hlavičky a CF Access
  odmítá preflight (403). Proto ten lokální server.
