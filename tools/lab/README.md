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

## Řazení tabulky

Sloupce jsou vždycky modely (omezená osa). Uvnitř flow se dá přepnout, co je
nadřazené:

- **styl → prompty pod sebou** (výchozí) — jeden styl, pod ním všechny prompty.
  Odpovídá otázce „drží ten styl napříč náměty?"
- **prompt → styly pod sebou** — jeden námět, pod ním všechny styly. Odpovídá
  otázce „co ten model udělá s mým promptem v různých stylech?"

Volba se pamatuje v prohlížeči.

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
