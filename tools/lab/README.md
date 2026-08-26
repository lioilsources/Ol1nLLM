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
lab score build/lab/20260826-0023
lab export build/lab/20260826-0023 --send   # do FINETUNE gallery
```

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
u některých modelů (flux nemá `KSampler`), přeskočí se ty buňky a důvod je
vidět v tabulce.

Rozdíl, na kterém záleží: `steps/cfg/sampler/scheduler/rozměry` **přebíjejí
preset modelu** — sweep je nastaví všem stejně, takže rozbije kalibraci
(juggernaut-lightning má 6 kroků schválně) a výsledek pak není verdikt
o modelu; takové buňky mají v tabulce odznak. Naproti tomu
`editDenoise/seed/latent/pose` jsou parametry flow a chovají se jako v appce.

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

## Poznámky k prostředí

- CF Access creds se berou z `.env.local` (`CF_ACCESS_CLIENT_ID`,
  `CF_ACCESS_CLIENT_SECRET`). Bez nich server nastartuje a vysvětlí se —
  běh nanečisto funguje i tak.
- Server poslouchá jen na `127.0.0.1` a mutující požadavky chtějí
  `X-Lab-Token`, protože drží ty creds a jinak by na něj dosáhla kterákoli
  stránka v prohlížeči.
- Prohlížeč nemůže volat ComfyUI přímo: nevrací CORS hlavičky a CF Access
  odmítá preflight (403). Proto ten lokální server.
