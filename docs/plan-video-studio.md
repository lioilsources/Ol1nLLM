# Plán: Video studio v labu — stroboskop, plátno a mřížka napříč běhy

Plán pro Claude Code (Opus). Jedno repo (tohle), nástroj `tools/lab`. Cíl:
z patnácti přepínačů `make stylemap-video` a jednoho Python skriptu udělat
**ucelený nástroj v Go** s **YAML receptem** a **webovým studiem**, které
pomůže najít, co se dá s čím porovnat, ukáže náhled a teprve pak renderuje.

Zadání uživatele (2026-11-26): *„vidíš z předchozí komunikace, jak se snažím
napříč běhy/modely/styly/prompty najít match, aby stroboskop/plátno/grid byl
aspoň trochu podobný. Opus to teď rozsekal do nějakých make příkazů a scriptů,
chci něco ucelenějšího, např. YAML konfiguraci, UX, které mi pomůže apod.
Scripty v golangu, žádný Python, není potřeba. UX Svelte/Flutter.“*

Sepsáno 2026-11-26 po průzkumu kódu a po sérii videí vyrobených ručně
24.–25. 11. (PR #74–#77). **[V]** = ověřeno proti kódu nebo datům na disku,
**[I]** = návrh nebo odhad, který má implementace potvrdit, nebo opravit.

> **Stav:** M0–M4 hotové (2026-11-27); M5 (plynulé pořadí, „Doplň díry“)
> čeká na domluvu. M4: předloha jako dlaždice (`frame.reference`),
> `select.min_reaction`, varianty tempa ve studiu; studio na `/video/` (Svelte, API
> `video_api.go`), zkratka `/video/#run=…&template=…`; z M4 je hotový žebřík párování
> (`pair: exact | kind | order`) i skóre shody — byl potřeba už pro paritu.
> Paritní čísla §12 plán reprodukuje všechna (počty snímků, videí i délky);
> `make_video.py` a `make stylemap-video` jsou pryč. Co vyšlo jinak, než plán
> čekal:
> 0. **Výkon (§8) jen zčásti.** Plátno 6 modelů × 311 stylů: Go 65 s, Python
>    114 s (1,75×). Stroboskop 1 866 obrázků při 30/s: Go 114–117 s, Python
>    144 s. Měřeno na vytíženém stroji (load 5–12). Brzdou bylo čtení souborů:
>    dekodér PNG čte po 4 KB a systémová volání stála 68 % CPU — teď se
>    soubor čte celý. Zbývá dekódování PNG v Go (~36 ms na 1024², PIL zhruba
>    třetinu); `output.encoder: videotoolbox` uvolní procesor kódování.
> 1. **Postava není osa, když je v běhu jediná.** Běhy rodiny 64 scén mají
>    každý jednu postavu, ale pokaždé jinak napsanou (pro jinou rodinu
>    modelů). Jako osa by žádné dva běhy nespárovala; teď jde do otisku
>    nastavení a osou je jen tam, kde v jednom běhu rozlišuje sloupce.
> 2. **Rodina se počítá z naplánovaných promptů**, ne z obrázků — jinak se
>    přerušené běhy rozpadly do vlastních „rodin“. Rodina 64 scén má teď
>    32 běhů a 14 modelů.
> 3. **Studený index trvá ~25 s** (584 MB manifestů, disk), teplý ~1 s.
> 4. Paritní čísla sedí: šest modelů čtyř běhů volně 1 542, striktně 51
>    (s baseline). Návrhy ze skriptu 25. 11. vyšly o 4 a 1 nižší
>    (548 → 544, 422 → 421): skript počítal pět 0bajtových souborů
>    v `20261109-175450` jako obrázky.

## Shrnutí

- **Kolekce → Recept → Scénář → Render.** Všechny obrázky všech běhů jsou
  body v prostoru os (model, styl, prompt, flow…). Recept (YAML) říká, která
  osa jsou dlaždice, které osy jsou čas a co se filtruje. Scénář je čistý
  výpočet: seznam snímků, dílů a důvodů, proč něco vypadlo. Render ho jen
  nakreslí.
- **„Match“ je vidět dřív, než se renderuje.** Studio ukáže matici pokrytí
  (který model má který styl u kolika promptů), navrhne nejlepší kombinace
  a u volného párování řekne, jak moc si dlaždice odpovídají.
- **Náhled v prohlížeči z náhledů běhu** (`thumb/`), ve skutečném tempu.
  Render až na tlačítko, ve frontě, s výsledky na jednom místě.
- **Go místo Pythonu** pro všechno kolem videa; `make_video.py` a cíl
  `stylemap-video` zmizí. Python zůstává jen tam, kde nese model (ArcFace,
  WD14, pipeline map stylů) — ten se nepřepisuje.
- **UI ve Svelte** uvnitř lab serveru (stejná sestava jako FINETUNE gallery).
  Proč ne Flutter: §14.

## 1. Proč

Za dva dny vzniklo ručně 86 videí z osmi běhů a ukázalo se, kde to dře:

1. **Hledání, co jde spojit, bylo ruční.** Opakovaně se psal jednorázový skript:
   „které běhy mají stejné prompty“, „které i stejné styly“, „kolik úplných
   snímků dají které modely“. Odpovědi (stejných 64 scén má 31 běhů
   a 14 modelů; čtyři vybrané běhy mají společný jen styl „bez stylu“) přišly
   až po renderu naslepo nebo po dotazu.
2. **Přepínače místo modelu.** `RUN SET NAME WHERE ORDER OUTER GRID COLS MIX
   COMPLETE SPLIT LABEL RATE FADE VIDEO_ARGS` [V]: každý vznikl jako odpověď
   na jeden požadavek, neplatné kombinace se poznají až za běhu a nový pohled
   („dlaždice = flow“, „dlaždice = hodnota sweepu“) znamená další přepínač.
3. **Žádný náhled.** Render mřížky trvá 1–3 minuty, sada 16 videí deset.
   První render spojených běhů spadl po pěti videích na 0bajtovém obrázku.
4. **Video žije na špatném místě.** Zdrojem jsou běhy labu, ale skript je
   v `tools/stylemap` (Python), výstupy v `build/lab/<běh>/video/`
   a `build/lab/_merged/video/`, nastavení jen v historii shellu.

## 2. Co je dnes [V]

### 2.1 Co umí `make stylemap-video` a kam to půjde

| Dnes | Nově (recept, §5) |
|---|---|
| `RUN="a b c"` (spojení podle `promptBody`, první běh vyhrává) | `source.runs`, `source.prefer` |
| `SET=` (pack mapy stylů, LPIPS trasa) | neportuje se, viz §14 |
| `WHERE="model=… flow=…"` | `select` |
| `ORDER=style`, `OUTER=prompt\|style` | `time.axes: [prompt, style]` / `[style, prompt]` |
| sekvence „styl po stylu přes modely“ | `time.axes: [prompt, style, model]` |
| `GRID=1`, `COLS=` | `frame.tiles: model`, `frame.cols` |
| `MIX=1` | `time.loose: [style]` |
| `COMPLETE=1` | `time.complete` |
| `SPLIT=60` (řez jen mezi prompty / styly) | `output.split: {seconds, at}` |
| `LABEL=1` | `frame.title`, `frame.captions` |
| `RATE`, `FADE`, `--fps` | `time.rate`, `time.fade`, `output.fps` |
| `--model-order` | pořadí hodnot v `select.model` |
| `--fit`, `--size`, `--crf`, `--audio`, `--max-seconds` | `frame.fit`, `output.*` |
| ruční smyčka „video na model“, „video na flow“ | `output.per: [model]` / `[flow]` |

Chování, které musí port zachovat (ověřují paritní čísla v §12):

- **Pořadí stylů**: „bez stylu“ (`__baseline`) první, pak pořadí pickeru appky
  z `manifest.styles`, neznámé styly (kandidáti ze souboru) v pořadí prvního
  výskytu. **Modely**: pořadí z receptu, pak `manifest.models`, pak první
  výskyt. **Prompty**: pořadí běhu; u spojených běhů podle nejnižšího
  `promptIndex`, který daná scéna v některém běhu má.
- **Snímek mřížky** = jedna hodnota striktních časových os; model má po celé
  video stejnou dlaždici; chybějící obrázek je prázdný rámeček, nebo se snímek
  zahodí (`complete`).
- **MIX**: u každého promptu nejdřív hodnoty, které mají všechny dlaždice,
  pak každá dlaždice pokračuje svými zbylými hodnotami v pořadí pickeru.
- **Dělení**: díly do N vteřin, řez jen na hranici vnější skupiny; skupina
  delší než N dostane díl sama. Soubory `NAME-01.mp4`, `NAME-02.mp4`…
- **Čas**: snímek drží `fps / rate` snímků videa (i neceločíselně: pro snímek
  `k` platí `i = floor(k / hold)`), posledních `fade` podílu se prolíná do
  dalšího, poslední snímek dílu se neprolíná.
- **Vzhled** (konstanty v `make_video.py`, poměrně k šířce W a výšce H):
  okraj `0.02·W`; bezpečná zóna shora `0.085·H` (záložky TikToku), zdola
  `0.88·H` (titulek); titulek `0.042·W`, pruh titulku **vždy dva řádky**
  (mřížka neposkakuje), delší text se zkrátí výpustkou; popisek dlaždice
  `0.026·W` a druhý řádek `0.021·W`, zmenší se, když se nevejde (min. 12 px);
  pozadí `(16,16,18)`, box titulku `(40,40,44)`, prázdná dlaždice obrys
  `(60,60,64)`; jeden obrázek na snímek: `contain` na rozmazané kopii
  ztmavené na 45 %, nebo `cover`; popisek jednoho obrázku v boxu u `0.12·H`.
- **Automatická mřížka**: dělení na sloupce × řádky, které dá největší obrázek
  pro poměr stran běhu (6 čtverců na 9:16 = 2 × 3, 6 obrázků 2:3 = 3 × 2).

### 2.2 Data

- Běh = `build/lab/<YYYYMMDD-HHMMSS>/`: `wf/manifest.json`, `state.json`,
  `spec.json`, `img/<id buňky>.png`, `thumb/<id>.jpg` (delší strana 320 px),
  `metrics.json`, u běhů s promptovým souborem `prompt-bodies.json`
  a `characters.txt`. Adresáře s podtržítkem (`_refs`, `_merged`) server za
  běhy nepočítá (`loadRuns`).
- Na disku je 77 běhů, manifesty mají dohromady 584 MB (jeden až 10 MB,
  3 968 buněk). Číst je při každém dotazu nejde — index musí mít cache.
- Buňka manifestu nese: `id`, `flow`, `model`, `modelLabel`, `style`
  (`__baseline` = bez stylu), `styleLabel` (s rokem), `promptIndex`,
  `promptBody` (id položky promptového souboru; prázdné, když prompt psal
  uživatel do pole), `variant` (hodnota sweepu: `label`, `value`, `order`),
  `params` (seed, lora, loraStrength, faceIdentity, editDenoise, stylePosition,
  styleDialect, qualityPrefix, hint, poseMode, refName…), `dependsOn`
  (restyl → fotka pozice).
- `manifest.styles[]` nese `id`, `label`, `labelWithYear`, `kind`
  (`culture` / `artist` / `medium`), `year`. `manifest.prompts[i]` je popisek
  sloupce: `prefix · id scény · postava` (`PromptAxisEntry.label`
  v `dump_spec.dart`). **Postava a prefix v buňce samostatně nejsou.**
- Text promptu se běh od běhu liší i u téže scény (je psaný pro rodinu
  modelu), takže identita promptu **není text**.
- Běhy bývají přerušené (`cancelled`, `interrupted`) a `state.json` může
  tvrdit `running` u mrtvého běhu. Pravdu říká jen soubor na disku.
- Soubor `.png` může být JPEG (výsledky gen-queue); `imageutil.go` registruje
  oba dekodéry. Soubor může mít 0 bajtů (staré běhy před PR #77) — to je
  chybějící obrázek.

### 2.3 Kód a nástroje

- `tools/lab` je jeden Go modul, `package main`, go 1.26, jediná závislost
  `gopkg.in/yaml.v3`. Obrázky řeší stdlib (`imageutil.go`: box filtr pro
  náhledy; `metrics.go`: 512binový RGB histogram a `CosDist`).
- Web UI labu je vanilla JS bez buildu (`static/`, `go:embed`), 1 433 řádků
  `app.js`. Server poslouchá jen na loopbacku; `guard()` odmítá cizí `Origin`
  a ne-GET požadavky chtějí `X-Lab-Token` (token je v `<meta>` stránky).
  `/media/…` servíruje cokoli pod `build/lab` s `Cache-Control: immutable`
  na rok.
- FINETUNE gallery (sourozenecké repo) má Svelte 5 + Vite 6: zdroj ve `web/`,
  build do `server/webdist`, `//go:embed all:webdist`, v gitu jen zástupný
  `webdist/index.html`. Stejný vzor použij tady.
- CI (`.github/workflows/ci.yml`) pouští jen Flutter (analyze, test, Android
  a iOS build). **Go testy labu v CI neběží.**
- `ffmpeg` a `ffprobe` jsou na Macu z Homebrew, `node` taky.

## 3. Cílový stav

```
                ┌──────────────────── Studio (Svelte, /video/) ─────────────────────┐
                │ 1 Zdroj     2 Pokrytí      3 Skladba      4 Náhled      5 Render  │
                └─────┬────────────┬──────────────┬──────────────┬─────────────┬────┘
                      │            │              │              │             │
 build/lab/*  ──→  KOLEKCE  ───→  RECEPT  ────→  SCÉNÁŘ  ────→  náhled  ──→  RENDER
 manifest,         index všech    YAML: zdroje,  čistý výpočet: z thumb/     Go + ffmpeg
 img/, thumb/      obrázků a os,  výběr, role    snímky, díly,  v prohlížeči → MP4 a recept
                   rodiny běhů    os, čas,       důvody                      v jedné složce
                                  výstup         vyřazení
                      └──────────── totéž z terminálu: lab video … ────────────┘
```

Slovník (drž ho v kódu, UI i dokumentaci):

| Pojem | Význam |
|---|---|
| **Kolekce** | index všech obrázků všech běhů; obrázek = bod s hodnotami os |
| **Osa** | vlastnost, ve které se obrázky liší: `model`, `style`, `prompt`, `flow`, `variant`, `run`… |
| **Rodina běhů** | běhy se stejnou sadou promptů — jen ty jde poctivě dát vedle sebe |
| **Recept** | YAML soubor: co se bere, jakou roli má která osa, tempo, výstup |
| **Snímek** | jeden úsek videa (jeden obrázek, nebo mřížka dlaždic) |
| **Dlaždice** | jedno okno mřížky; patří jedné hodnotě osy dlaždic |
| **Scénář** | výsledek plánování: snímky, díly, statistiky, varování |
| **Díl** | jeden výstupní soubor (po dělení a rozvětvení `per`) |

Šablony pro první klik (jména jsou uživatelova):

| Šablona | Snímek | Čas | K čemu |
|---|---|---|---|
| **Stroboskop** | jeden obrázek | `[style]`, rychle, střih | co všechno jeden model se stylem udělá |
| **Průlet** | jeden obrázek | `[prompt, style]`, dělit po promptech | minutová videa jednoho modelu |
| **Plátno** | mřížka modelů | `[prompt, style]`, striktně | týž prompt i styl, modely vedle sebe |
| **Mix** | mřížka modelů | `[prompt, style]`, styl volně | stejný prompt, každý model svůj styl |

## 4. Kolekce: osy a identita

To je jádro „matche“. Každý obrázek (buňka s neprázdným souborem) má:

| Osa | Identita | Poznámka |
|---|---|---|
| `model` | id modelu | popisek `modelLabel` |
| `style` | id stylu, `__baseline` | k tomu `kind`, `year`, popisek s rokem |
| `prompt` | viz níže | |
| `flow` | `txt2img`, `img2img`, `repose`, `restyle`, `hair` | `position` (fotka pozice) jen jako zdroj pro `frame.reference` |
| `variant` | `variant.value` | pořadí `variant.order`; prázdné bez sweepu |
| `run` | id běhu | původ, ne obsah: osou je, jen když ji recept použije |
| `setup` | otisk nastavení běhu, které mění obraz | původ: seed, lora + síla, faceIdentity, faceDetail, editDenoise, stylePosition, styleDialect, qualityPrefix, hint, poseMode, latent, negativ, base model, hash předlohy |

**Identita promptu** má dvě úrovně a recept si vybírá (`source.prompt_identity`):

- `scene` — `promptBody` (id z promptového souboru). Výchozí, když ho mají
  všechny vybrané běhy. Text se liší podle rodiny modelu, scéna je táž.
- `column` — celý popisek sloupce `prefix · scéna · postava`, u běhů bez
  promptového souboru text řádku promptu. Výchozí jinde.

Když v jednom běhu připadá na jednu scénu víc sloupců (víc postav nebo
prefixů), vzniká osa `character` / `prefix` a platí pro ni pravidlo rolí (§5).
U starých běhů je odvoď z popisku (popisek = `[prefix ·] id [· postava]`,
`spec.json` zná `prompts` a `characters`). **Doplň do `dump.dart`, aby buňka
nesla `promptPrefix` a `character` samostatně** — nové běhy pak nic
neodvozují.

**Rodina běhů** = běhy se stejnou sadou identit promptu; flow, předloha
a nastavení jsou osy uvnitř rodiny, ne její hranice. Běh, který má jen
podmnožinu (10 z 64 scén), ukaž jako příbuzný, ne jako cizí [I].

**Kolize**: dva obrázky pro tutéž kombinaci os, které recept používá.
- Stejný `setup` ve dvou bězích (běh a jeho opakování): rozhoduje
  `source.prefer` (`first` | `newest` | `error`). Dnes natvrdo první běh.
- Různý `setup` (jiný seed, jiná síla úpravy): nejsou to stejné obrázky.
  Plánovač to **musí říct** („liší se: seed 777 × 101“) a nabídnout: vybrat
  jedno nastavení, nebo dát ose `setup` / `run` roli (dva běhy vedle sebe
  jako dlaždice jsou legitimní pohled: před změnou a po ní).

**Index a cache**: jeden kompaktní záznam na běh v
`build/lab/_video/.index/<běh>.json`, platný podle velikosti a mtime manifestu;
přítomnost obrázků z jednoho `ReadDir(img)` (jméno → velikost, 0 B = chybí).
Manifest čti úspornou strukturou (bez `prompt`, `negative`, `styleText`,
`applied` — to jsou ty megabajty). Studený průchod 77 běhů do pár vteřin,
teplý okamžitě [I]. Rozměr obrázku stačí z jednoho vzorku na (běh, model,
flow) přes `image.DecodeConfig`.

## 5. Recept (YAML)

Klíče anglicky a malými písmeny (jako promptové soubory), komentáře a chyby
česky. Parsuj s `KnownFields(true)`: neznámý klíč je chyba s číslem řádku.

```yaml
version: 1
name: mix-6-modelu                # → build/lab/_video/mix-6-modelu/

source:
  runs: [20261112-204624, 20261114-031858, 20261115-005933, 20261116-011614]
  # family: 20261112-204624       # místo runs: všechny běhy z rodiny tohoto běhu
  prompt_identity: scene          # scene | column
  prefer: first                   # kolize téhož obrázku: first | newest | error

select:                           # filtr; pořadí hodnot = pořadí dlaždic / času
  model: [animagine-xl, illustrious-xl, noobai-xl, pony, wai-illustrious, hassaku-illustrious]
  flow: txt2img
  # style: {not: [xray]}          # seznam, nebo {only: […]}, {not: […]}, {kind: [artist]}
  # prompt: {only: […]}
  # min_reaction: 0.15            # jen buňky, kde styl něco udělal (metrics.json)

frame:
  tiles: model                    # osa dlaždic; bez ní je na snímku jeden obrázek
  cols: auto                      # auto | 1…N
  fit: contain                    # contain | cover (jen bez dlaždic)
  title: prompt                   # none | auto | jméno osy
  captions: [model, style]        # none | auto | seznam os pod dlaždicí
  # reference: true               # první dlaždice = předloha běhu / fotka pozice (M4)

time:
  axes: [prompt, style]           # vnější → vnitřní
  loose: [style]                  # osy, které se mezi dlaždicemi smí lišit (MIX)
  pair: kind                      # párování volných hodnot: exact | kind | order (§6; kind od M4)
  complete: true                  # snímek s prázdnou dlaždicí zahodit
  order: {style: picker, prompt: run}   # style: picker | year | label | smooth
  rate: 2                         # snímků za vteřinu
  fade: 0.2                       # podíl snímku na prolínačku, 0 = střih

output:
  size: 1080x1920
  fps: 30
  per: []                         # samostatné video (sada) na hodnotu osy: [model], [flow]
  split: {seconds: 60, at: prompt}
  # max_seconds: 170              # zkrátit rovnoměrným výběrem celých skupin
  crf: 18
  # audio: hudba.mp3
```

**Pravidlo rolí** (nahrazuje všechny dnešní „tohle jde jen s tamtím“): každá
osa obsahu (`model`, `style`, `prompt`, `character`, `prefix`, `flow`,
`variant`), která má po `select` víc než jednu hodnotu, musí mít právě jednu
roli — `frame.tiles`, `time.axes`, nebo `output.per`. `run` a `setup` jsou
původ: roli nepotřebují a řeší se jen při kolizi (§4). Jinak plánování skončí
chybou,
která vyjmenuje hodnoty a nabídne opravy: *„osa flow má 2 hodnoty (repose,
img2img) a nemá roli: přidej ji do `time.axes`, do `output.per`, nebo vyber
jednu v `select.flow`.“* Další kontroly: `loose` musí být vnitřní část
`time.axes` a dává smysl jen s `tiles`; `split.at` musí být striktní časová
osa (výchozí vnější); `cover` jen bez dlaždic; `rate ≤ fps`.

Recepty videí z 24.–25. 11. Skutečné recepty zůstávají lokálně
v `build/lab/_video/`; do `tools/lab/candidates/` dej obdobné ukázky
s vymyšlenými id běhů.

```yaml
# Průlet jedním modelem, minutová videa po promptech (dnes: SPLIT=60 RATE=4)
source: {runs: [20261112-204624]}
time:   {axes: [prompt, style], rate: 4, fade: 0.2}
output: {split: {seconds: 60, at: prompt}}
```

```yaml
# Totéž styl → prompty, řez mezi styly (dnes: OUTER=style)
source: {runs: [20261112-204624]}
time:   {axes: [style, prompt], rate: 4, fade: 0.2}
output: {split: {seconds: 60, at: style}}
```

```yaml
# Plátno: tři modely vedle sebe přes styly, zvlášť video pro každou flow
source: {runs: [20261124-112650]}
select: {model: [cyberrealistic-xl, realvis-xl, lustify-zenith]}
frame:  {tiles: model, cols: 3}
time:   {axes: [style], rate: 2, fade: 0.2}
output: {per: [flow]}
```

```yaml
# Video na model + stroboskop přes všechny modely (dnes: 7 příkazů)
source: {runs: [20261120-175313]}
time:   {axes: [style], rate: 6, fade: 0.3}
output: {per: [model]}
---
source: {runs: [20261120-175313]}
time:   {axes: [style, model], rate: 30, fade: 0}
```

Ukázky jsou zkrácené (bez `version` a `name`). Soubor smí nést víc dokumentů
(`---`); každý je jedno video nebo sada.

## 6. Párování a pokrytí („match“)

Tři nástroje nad kolekcí; všechny čistě počítají, nic nerenderují.

**a) Pokrytí.** Pro zvolenou osu dlaždic (řádky) a vnitřní osu (sloupce)
matice: kolik hodnot zbylé osy má obrázek. Typicky model × styl, v buňce
„u kolika promptů z 64“. Z toho hned plyne, kolik snímků bude úplných.

**b) Návrhy.** „Které modely dát vedle sebe.“ Pro každý klíč snímku bitová
maska přítomných hodnot osy dlaždic; pro podmnožinu S velikosti k počet
klíčů, jejichž maska S obsahuje. Hodnot je do patnácti, takže se projdou
všechny podmnožiny. Výstup pro k = 2…N: nejlepší kombinace se dvěma čísly —
**striktně úplných** snímků (stejný prompt i styl) a **volně úplných** (stejný
prompt, styl libovolný). Tohle 25. 11. počítal jednorázový skript.

**c) Žebřík párování** pro volné osy (dnešní MIX umí jen první a poslední
příčku). V rámci jedné striktní skupiny (prompt):

1. `exact` — hodnota, kterou mají všechny dlaždice: striktní snímek.
2. `kind` — zbytek každé dlaždice seřaď podle (`kind`, `year`, id) a páruj
   stejný druh se stejným druhem, v něm nejbližší rok. Kulturu ke kultuře,
   umělce k umělci.
3. `order` — co zbude, v pořadí pickeru (dnešní chování).

Každý snímek si nese, na které příčce vznikl, a scénář to sčítá: *„shoda
stylu: 4 % přesná, 31 % stejný druh, 65 % jiná“*. To je číslo, podle kterého
se pozná, jestli „je to aspoň trochu podobné“, dřív než se cokoli vyrenderuje.
`pair: exact` nechá jen první příčku (= striktní plátno).

U čtyř běhů z 25. 11. žebřík nepomůže — každý běh kreslil jiný druh stylů
(kultury / média / dva běhy umělců) — a studio to má říct tím číslem, ne
tichým videem. Skutečná oprava je dogenerovat díry (M5).

**Volitelně (M5) `order: smooth`**: pořadí vnitřní osy s nejmenšími skoky
v obraze. Vzdálenost = `CosDist` histogramů náhledů (`metrics.go` to umí),
trasa nejbližší soused + 2-opt (algoritmus je v `tools/stylemap/build_map.py`,
funkce `tour`; přepiš ho do Go, je to 40 řádků). Nahrazuje LPIPS trasu packu.

## 7. Scénář

Výstup plánování; jediný vstup náhledu, renderu i testů. JSON (hodnoty jsou
ilustrační):

```
{
  "recipe":  { …normalizovaný recept… },
  "axes":    { "model": [{id, label}], "style": [{id, label, kind, year}], "prompt": [...] },
  "layout":  { "w": 1080, "h": 1920, "title": {x,y,w,h} | null,
               "tiles": [ {x,y,w,h, "caption": {x,y,w,h}} ] },
  "slides":  [ { "key": {"prompt": "…", "style": "…"}, "match": "exact|kind|order",
                 "title": "…", "tiles": [ {run, cell, model, style, prompt, img, thumb} | null ],
                 "captions": [["Pony", "Schiele (1890)"], …] } ],
  "videos":  [ { "name": "mix-6-modelu-01", "per": {}, "from": 0, "to": 93,
                 "seconds": 46.5, "groups": ["…", "…", "…"] } ],
  "stats":   { "slides": 1542, "seconds": 771.0,
               "dropped": {"incomplete": 2720, "empty_file": 7, "collision": 64, "filtered": 0},
               "match": {"exact": 64, "kind": 0, "order": 1478} },
  "warnings": [ "Shorts: díl 05 má 185 s (limit 180 s)", … ]
}
```

- `layout` počítá Go (§8) — náhled v prohlížeči jen umístí náhledy do stejných
  obdélníků, takže náhled a render nemůžou vypadat jinak.
- `slides` u API stránkuj (`?from=&to=`); 4 000 snímků × 6 dlaždic jsou
  jednotky MB.
- Před renderem ověř hlavičku každého použitého souboru (`DecodeConfig`).
  Nečitelný obrázek = chybějící, s důvodem ve statistice. Render nesmí spadnout
  v polovině sady.

## 8. Render v Go

- **Balíček** `tools/lab/internal/video` — čistá knihovna bez `Env` a HTTP:

  ```
  index.go    běh → záznamy, cache, rodiny        match.go   pokrytí, návrhy, párování
  axes.go     osy, identita, pořadí               layout.go  geometrie snímku
  recipe.go   YAML ↔ struct, validace, šablony    compose.go snímek → image.RGBA
  plan.go     recept + index → scénář             render.go  ffmpeg, prolínačka, díly
  font.go     písmo, měření, zalamování
  ```
  `package main` přidá jen `video_cli.go` (`lab video …`) a `video_api.go`.
- **Druhá závislost modulu: `golang.org/x/image`** — `draw.CatmullRom` pro
  zmenšování, `font/opentype` a vestavěný Go font (`gofont`), aby text
  nezávisel na fontech systému. Test projde všechny `labelWithYear` registru
  a jména modelů a spadne na chybějícím glyfu (čeština, „—“, „·“, „…“);
  pak buď jiný vložený font, nebo systémový jako záloha.
- **Skládání**: `Layout()` vrátí obdélníky, `Compose()` nakreslí snímek do
  `image.RGBA`. Obrázky jiného poměru stran (běhy 1024² vedle 896×1152) se do
  boxu dlaždice vejdou celé; box má poměr většiny. Rozmazané pozadí
  u `contain`: zmenšit na ~1/16, zvětšit zpět, ztmavit — nemusí sedět na pixel
  s Pythonem, jen vypadat stejně.
- **Roura do ffmpeg** jako dnes: syrové snímky na stdin,
  `-f rawvideo -pix_fmt rgba -s WxH -r FPS -i -`, výstup
  `-c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -movflags +faststart`,
  zvuk `-c:a aac -b:a 192k -shortest`. Držený snímek piš opakovaně z téhož
  bufferu, prolínačku míchej ve smyčce přes bajty, další snímek skládej
  dopředu v gorutině (dekódování a zmenšování dlaždic paralelně).
- **Robustnost**: zápis do `*.part.mp4` a přejmenování; zrušení přes `context`
  zabije ffmpeg a uklidí; jeden render najednou (fronta), zámek generování
  GPU (`runlock.go`) se videa netýká.
- **Výkon** [I]: aspoň dvakrát rychlejší než Python na třech měřených
  případech (Python: 311 snímků mřížky 2×3 při 2/s = 155 s videa za 106 s;
  311 snímků po jednom při 6/s = 52 s videa za 33 s; 1 866 snímků při 30/s =
  62 s videa za 144 s). Když ne, zkus `h264_videotoolbox` jako volbu
  `output.encoder`, ne jako výchozí (horší poměr kvalita/velikost).

## 9. CLI a API

```
lab video index [--refresh] [--json]        rodiny běhů, osy, počty, varování (0B soubory)
lab video coverage --runs a,b --rows model --cols style
lab video suggest  --runs a,b --tiles model [--k 3]
lab video new --run X --template platno > recept.yaml     kostra s komentáři
lab video plan   recept.yaml [--slides]     shrnutí scénáře, nic nerenderuje
lab video render recept.yaml [--only 03]    render do build/lab/_video/<name>/
```

Makefile: `make lab-video RECIPE=…` (= `lab video render`). API (ne-GET
s `X-Lab-Token`, jako zbytek labu):

| Endpoint | K čemu |
|---|---|
| `GET /api/video/index` | rodiny, běhy, osy (`?refresh=1` zahodí cache) |
| `POST /api/video/coverage`, `/suggest` | matice a návrhy pro rozpracovaný recept |
| `POST /api/video/plan` | recept → scénář (bez `slides`), `GET …/slides?from=&to=` |
| `GET/PUT/DELETE /api/video/recipes/{name}` | YAML v `build/lab/_video/<name>/recipe.yaml` |
| `POST /api/video/render`, `GET /api/video/jobs/{id}` (SSE), `DELETE` | fronta, průběh po dílech, zrušení |
| `POST /api/video/reveal` | `open -R` na výsledek (jen cesty pod `build/lab/_video`) |

Výstup jedné sady: `build/lab/_video/<name>/` = `recipe.yaml` + souhrn scénáře
+ MP4. Videa v prohlížeči přes `/media/_video/…`, ale s `?v=<mtime>` — handler
posílá `immutable` na rok a přerenderované video se stejným jménem by
prohlížeč ukazoval staré.

## 10. Studio (Svelte)

Zdroj `tools/lab/web/` (Svelte 5 + Vite 6, verze jako FINETUNE gallery), build
do `tools/lab/webdist/`, `//go:embed all:webdist`, v gitu jen zástupný
`index.html` („sestav UI: `make lab-web`“). `make lab` build pustí, když jsou
zdroje novější; bez `node` lab běží dál a `/video/` to řekne. Token jako
dnes z `<meta>` (server ho do `index.html` dosadí). Stávající `static/app.js`
se **nemění** kromě odkazu „video“ v hlavičce a tlačítka „Video z tohoto
běhu“ (`/video/#run=<id>`) — jiné session na něm pracují souběžně.

```
┌ lab · video ──────────────────────────────────────────────────────────────────────────────────────┐
│ Šablona: [Stroboskop] [Průlet] [Plátno] [Mix]          Recept: mix-6-modelu  [Uložit]             │
├────────────────────────┬──────────────────────────────────────────────────┬───────────────────────┤
│ 1 ZDROJ                │ 2 POKRYTÍ   řádky [model]   sloupce [styl]       │ 4 NÁHLED              │
│ * 64 scén              │              kultury   umělci    média           │  ┌───────────────┐    │
│   31 běhů · 14 modelů  │ [x] animagine ████▓▓▓▓ ▓▓▓▓░░░░ ░░░░░░░░         │  │ [   prompt  ] │    │
│   flow (o) txt2img     │ [x] pony      ░░░░░░░░ ████████ ░░░░░░░░         │  │ ┌───┐  ┌───┐  │    │
│        ( ) restyle     │ [x] wai       ░░░░░░░░ ████████ ░░░░░░░░         │  │ │   │  │   │  │    │
│   [x] 1112-204624 3822 │ [ ] lustify   ▓▓░░░░░░ ░░░░░░░░ ░░░░░░░░         │  │ └───┘  └───┘  │    │
│   [x] 1114-031858 3812 │ úplných snímků: 64 striktně · 1 542 volně        │  │ ┌───┐  ┌───┐  │    │
│   [ ] 1108-085453  418 │ shoda stylu: 4 % přesná · 0 % druh · 96 % jiná   │  │ │   │  │   │  │    │
│ - 1 prompt · repose    │ [Navrhni kombinace]  3 dlaždice: animagine+…     │  │ └───┘  └───┘  │    │
│                        ├──────────────────────────────────────────────────┤  └───────────────┘    │
│   …                    │ 3 SKLADBA                                        │  > ----o------  2/s   │
│ hledat: [          ]   │ snímek  ( ) obrázek  (o) mřížka                  │  díl 03/16 · 46 s     │
│                        │ dlaždice [model]  sloupce [auto]                 │                       │
│                        │ čas  [prompt] → [styl ~volně]  [x] jen úplné     │  [ ] bezpečné zóny    │
│                        │ tempo --o-- 2/s  prolínačka -o-- 0.2             │                       │
│                        │       = 1 prompt 12 s · díl 5 promptů            │                       │
│                        │ výstup  dělit po [60] s na [prompt]              │                       │
│                        │         video na [—]   formát [9:16]             │                       │
│                        │ ! osa flow má 2 hodnoty:                         │                       │
│                        │   [video na flow] [jen repose] [jen img2img]     │                       │
├────────────────────────┴──────────────────────────────────────────────────┴───────────────────────┤
│ 5 RENDER  16 dílů · 12:51 · odhad 9 min   [Renderovat]   ▓▓▓▓▓▓░░░░ díl 5/16   [Zrušit]           │
│   hotovo: mix-6-modelu-01.mp4  46 s  31 MB  [Přehrát] [Ve Finderu]    [Kopírovat příkaz]          │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Co má UI udělat za uživatele:

1. **Zdroj.** Běhy seskupené do rodin, nejdřív ty s nejvíc modely. U běhu
   datum, modely, hotovo/celkem, stav, varování. Výběr běhu označí ostatní
   štítky „stejné prompty“, „i stejné styly“, „jiná předloha“, „jiný seed“.
   Flow se v rodině přepíná, protože txt2img a restyle téže scény vedle sebe
   nejsou srovnání modelů.
2. **Pokrytí.** Teplotní mapa; zaškrtávátka řádků a sloupců rovnou mění
   `select`; souhrn úplných snímků a shody se přepočítá na každý klik. Klik
   na buňku ukáže náhledy té kombinace. „Navrhni kombinace“ vypíše nejlepší
   výběry pro 2…N dlaždic, klik je použije.
3. **Skladba.** Osy jako čipy, které se přetahují mezi rolemi (dlaždice / čas /
   video na… / filtr). Varování z validace jsou tlačítka s opravou. Vedle tempa
   je vidět, co znamená v čase („1 prompt = 12 s“, „díl = 5 promptů“)
   a limity platforem (Shorts a Reels 180 s).
4. **Náhled.** Rám 9:16 poskládaný z `thumb/` podle `layout` ze scénáře,
   přehrávání ve skutečném tempu i s prolínačkou (CSS), posuvník s ryskami
   dílů a skupin, volitelně překryv bezpečných zón TikToku. Klik na snímek
   ukáže, z kterého běhu a buňky je která dlaždice, a nabídne „vynechat tento
   styl / prompt“.
5. **Render.** Fronta, průběh po dílech, zrušení; výsledky s přehrávačem,
   velikostí a délkou, „Ukázat ve Finderu“, „Kopírovat příkaz“. Seznam
   uložených receptů k znovuotevření a duplikaci.

UI česky, stejný vizuální jazyk jako dnešní lab (tmavé, `app.css` proměnné).
Ověřuj na **dry bězích** (`make lab-dry` dělá šrafované zástupné obrázky) —
skutečné běhy obsahují explicitní obsah a do screenshotů, testů ani
dokumentace nepatří.

## 11. Milníky

Každý milník je samostatný PR, po kterém je nástroj použitelnější než předtím.

**M0 — Kolekce a pokrytí z terminálu.** `internal/video`: index s cache,
osy a identita (§4), rodiny, pokrytí, návrhy. `lab video index | coverage |
suggest`. `dump.dart`: `promptPrefix` a `character` v buňce. CI: job „Lab
(Go)“ — `gofmt -l`, `go vet`, `go test ./...` v `tools/lab`.
*Hotovo, když:* testy nad umělými běhy v `t.TempDir()` (pomocná funkce, která
zapíše manifest, state a malé PNG) pokrývají identitu promptu, kolize, 0B
soubory a přerušený běh; na disku uživatele `lab video index` najde rodinu
64 scén (31 běhů, 14 modelů) a `suggest` vrátí čísla z §12.

**M1 — Recept a scénář.** YAML, validace s opravami, šablony, plánovač
(striktní, volné osy s dnešním párováním — `pair: exact | order` —,
`complete`, `per`, `split`, `max_seconds`, pořadí). `lab video new | plan`.
*Hotovo, když:* recepty z §5 dají počty snímků, dílů a délky z §12; testy
převzaté z Pythonu (dělení: `[(0,62),(62,103)]` pro tři skupiny po 31 a jednu
po 10 při 0,25 s a limitu 20 s; skupina nad limit sama; MIX: společné hodnoty
první) a nové na pravidlo rolí.

**M2 — Render v Go, Python pryč.** `layout`, `compose`, `font`, `render`;
`lab video render`, `make lab-video`. Smaž `tools/stylemap/make_video.py`,
cíl `stylemap-video` a sekci „Video na výšku“ v `tools/stylemap/README.md`;
návod (i s ASCII schématy, přepsanými na recept) přesuň do
`tools/lab/README.md`, v `docs/lab.md` a `docs/style-map.md` nech odkaz.
*Hotovo, když:* testy geometrie (dlaždice se nepřekrývají, drží bezpečné zóny,
mezi snímky se nehýbou), skládání (pixely na malém plátně), glyfů a krátkého
renderu přes `ffprobe` (přeskoč bez ffmpeg) projdou; paritní videa mají stejný
počet dílů a délky jako Python a výkon podle §8.

**M3 — Studio.** API (§9), Svelte app (§10): zdroj, pokrytí, skladba, náhled,
render, uložené recepty. CI: `npm ci && npm run build`.
*Hotovo, když:* na dry bězích jde celý průchod — vybrat rodinu, uvidět
pokrytí, složit plátno i mix, přehrát náhled, vyrenderovat sadu, otevřít ji
ve Finderu — bez terminálu; handlery mají testy přes `httptest`.

**M4 — Lepší párování.** Žebřík `exact → kind → order` a skóre shody ve
scénáři i UI; `frame.reference` (předloha nebo fotka pozice jako první
dlaždice); `select.min_reaction`; varianty tempa jedním klikem („ještě 1/s
a 4/s“). *Hotovo, když:* testy žebříku; u běhů se stejnými druhy stylů skóre
`kind` roste proti `order`.

**M5 — Volitelné, po domluvě.** `order: smooth` (histogramová trasa);
„Doplň díry“: z matice pokrytí založit běh labu, který dogeneruje chybějící
kombinace (spec z existujícího běhu, jeho `prompt-bodies.json`
a `characters.txt`, jen chybějící modely × styly × scény), s odhadem buněk
a času předem — to je jediná skutečná oprava „každý běh má jiné styly“.

## 12. Paritní čísla [V]

Naměřeno Python skriptem 24.–25. 11. na disku uživatele. Běhy jsou jen tam,
do testů v repu nepatří; slouží k ruční kontrole portu, dokud Python existuje.

| Běh / recept | Snímků | Délka | Dílů |
|---|---|---|---|
| `20261120-175313`, video na model, `rate 6` | 311 na model | 51,8 s | 6 videí |
| tentýž, `[style, model]`, `rate 30`, střih | 1 866 | 62,2 s | 1 |
| tentýž, plátno modelů (auto 2 × 3), `rate 2` | 311 | 155,5 s | 1 |
| `20261124-112650`, plátno 3 × 1, `per: [flow]`, `rate 2` | 311 na flow | 155,5 s | 2 videa |
| `20261116-225258`, 2 modely, `complete`, `rate 3`, dělit 60 s na prompt | 1 371 (vypadlo 613) | 457,0 s | 9: 4× 51,7 · 55,3 · 2× 51,7 · 51,0 · 40,7 s |
| `20261112-204624`, `[prompt, style]`, `rate 4`, dělit 60 s | 3 822 | 955,5 s | 20 |
| tentýž, `[style, prompt]`, dělit na styl | 3 822 | 955,5 s | 21 |
| čtyři běhy (`…204624`, `…031858`, `…005933`, `…011614`), plátno 6 modelů, styl volně, `complete`, `rate 2` | 1 542 (vypadlo 2 720; 4 262 před `complete`) | 771,0 s | 16 |

Kolekce čtyř běhů: 64 scén, 6 modelů, 13 740 obrázků (13 747 včetně sedmi
0bajtových), `animagine-xl` sloučený ze dvou běhů.

Rodina 64 scén na disku (běhy s aspoň 200 obrázky): 31 běhů, 14 modelů, flow
txt2img (20 běhů, 13 modelů), restyle (10 běhů, 8 modelů) a repose.

Návrhy, které 25. 11. spočítal jednorázový skript (striktně úplné snímky,
tj. stejná scéna i styl u všech modelů):

| Běhy | Modely | Snímků |
|---|---|---|
| `20261109-055940`, `-094145`, `-175450` (txt2img, 62 stylů) | animagine-xl, autismmix-pony, pony | 548 |
| k tomu `20261110-012605` | + flux-schnell | 422 |
| `20261112-060344`, `20261112-124446` (restyle, stejný seed) | animagine-xl, noobai-xl | 827 |
| `20261108-085453`, `20261108-130340` (txt2img) | animagine-xl, lustify-zenith | 417 |

## 13. Pasti

- **Pravdu říká disk.** Stav běhu může lhát, soubor může být prázdný nebo
  JPEG pod příponou `.png`. Chybějící = neexistuje, 0 B, nebo nejde dekódovat.
- **Prompt není text.** Stejná scéna má pro každou rodinu modelu jiný text;
  identita je id scény (a postava), ne řetězec.
- **Různé poměry stran** v jedné mřížce (1024² × 896×1152) — box podle
  většiny, ostatní celé uvnitř.
- **Popisky jsou dlouhé** („Picasso — kubistický portrét (Dora Maar) (1881)“):
  zalamovat, zmenšovat, pruh titulku držet stejně vysoký.
- **Malé dlaždice.** Sedm obrázků v řadě je 150 px na dlaždici; UI má
  u takového rozložení říct velikost dlaždice a nabídnout víc řádků.
- **Limity platforem.** Shorts a Reels do 3 minut (delší Short není Short),
  TikTok do 10; při `crf 18` a 30 obrázcích za vteřinu vyjde 220 MB na minutu.
- **`/media/` je `immutable`** — výsledky adresuj s verzí.
- **Sdílený pracovní strom.** V hlavním adresáři pracují souběžně jiné
  session, přepínají větve a nechávají rozdělanou práci. Pracuj ve vlastním
  `git worktree`, nesahej na cizí soubory, necommituj `pubspec.lock` přepsaný
  lokálním Flutterem (CI má jinou verzi).
- **Veřejné repo.** Žádné texty promptů, id scén ani obrázky ze skutečných
  běhů v testech, ukázkách, dokumentaci a screenshotech; žádné LAN adresy.
- **CI**: jeden ze dvou iOS buildů bývá `CANCELLED` (souběh push a PR), to
  není chyba; rozhoduje druhý.
- **Invarianty labu platí dál** (`CLAUDE.md`): lab měří to, co appka opravdu
  posílá; u stylů nic nevyřazovat potichu — proto scénář každé vyřazení
  počítá a vysvětluje.

## 14. Rozhodnutí k potvrzení uživatelem

1. **Svelte, ne Flutter** (doporučeno). Data (GB obrázků), ffmpeg i lab server
   jsou na Macu; server drží CF Access token, proto poslouchá jen na loopbacku.
   Svelte uvnitř lab serveru znamená žádný další server, žádný release
   a stejnou sestavu, jakou už má FINETUNE gallery. Flutter by dával smysl,
   jen kdyby studio mělo žít v telefonu — pak by Mac musel vystavit API do
   sítě a vývojový nástroj by šel cestou vydávání appky. Hotová videa se do
   telefonu dostanou i bez toho (AirDrop; případné publikování na NAS je jiný
   plán).
2. **Pack mapy stylů jako zdroj videa (`SET=`) se neportuje.** Nikdy se
   nepoužil (na tomto Macu není ani venv pipeline), mapy má přehrávač v appce
   a plynulé pořadí dá `order: smooth` (M5) bez Pythonu.
3. **Druhá závislost Go modulu `golang.org/x/image`** (kvalitní zmenšování
   a písmo). Alternativa — text přes ffmpeg `drawtext` — by rozdělila
   rozložení mezi Go a ffmpeg a náhled by přestal odpovídat renderu.
4. **Recepty a výstupy v `build/lab/_video/<name>/`** (mimo git; odkazují na
   lokální běhy). V repu jen ukázky v `tools/lab/candidates/`.
5. **Výchozí `complete: true` a popisky vypnuté**; šablona Mix popisky zapíná
   (styly se v dlaždicích liší).
6. **Job „Lab (Go)“ v CI** a později build webu — pár minut navíc na každý PR.

## 15. Mimo rozsah

- Python, který nese model: `arcface.py`, `wd14.py`, pipeline map stylů
  (`tools/stylemap/*.py` kromě `make_video.py`).
- Přepis stávajícího UI labu do Svelte. Kolekce se může později hodit pro
  tabulku napříč běhy, ale to je jiný plán.
- Publikování videí na NAS a do appky, nahrávání na TikTok / YouTube.
- Hudba a titulky nad rámec jedné zvukové stopy.

## Jak pracovat

- Milník = větev ve vlastním worktree = PR; merge až po potvrzení uživatelem.
- Odpovědi uživateli česky; komentáře v kódu anglicky, UI a dokumentace česky
  (jako zbytek repa).
- Po každém milníku aktualizuj blok **Stav** nahoře, `tools/lab/README.md`
  a `docs/lab.md`.
- Když měření nebo data vyvrátí něco označeného [I], oprav plán, ne data.
