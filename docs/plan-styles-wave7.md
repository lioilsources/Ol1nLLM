# Plán: sedmá vlna stylů — opravy, 50+ umělců, 50+ kultur, 100+ médií

> **Handoff pro implementační session.** Tenhle soubor je necommitnutý
> na větvi `lab/prompt-candidates` a commituje se **spolu s implementací**,
> ne samostatně. Začni krokem 1 v § 5 — opravou escapování závorek
> v booru tazích (§ 0.1): je to pár řádků v `style_preset.dart` + test
> + jeden lab běh před/po, a výsledek rozhoduje, jak číst všechno ostatní.
> Nic z § 2–4 nejde do registru bez měření v labu (`tools/lab/README.md`,
> `docs/style-matrix.md` pro formát zápisu). Lab má od 2026-10-28 strop
> 4000 buněk na běh, stránkování a skrývání sloupců (commit `ad078aa`).

Stav registru (`lib/models/style_preset.dart`, 2026-10-31): **82 stylů** —
40 kulturních a epochálních (20 s `booru`), 42 podle umělců (všech 42
s `booru`). Měření, na kterých stojí, jsou ve `docs/style-matrix.md` (vlny
1–6). Tenhle plán je pro implementační session (Opus) a drží zásadu
předchozích vln: **do registru nic bez měření v labu** — text v plánu je
kandidát, ne verdikt.

Cíl ve třech částech, v tomhle pořadí, protože první část mění, co měří
druhá a třetí:

0. **Opravy** toho, co v registru je — jedna chyba v odesílání tagů, dva
   bloky, které neprošly na žádném dialektu, skupina „béžová stěna“, popisky
   neměřených modelů, rekvizity v blocích umělců.
1. **Nová kategorie „média a techniky“** (100+): olej, akvarel, tuš,
   kaligrafie, tužka, pastel, lepenka, linoryt, mozaika, vitráž… — nový druh
   stylu, který vyžaduje změnu datového modelu (třetí sekce v pickeru).
2. **Rozšíření stávajících kategorií**: 50+ umělců, 50+ kultur a epoch.

Rozpočet měření je díky dnešnímu stropu labu **4000 buněk na běh**
(dřív 400): jedna kategorie × 6 modelů × 2 náměty × 1 seed se vejde do
jednoho běhu, takže kandidátské běhy nemusí být rozkouskované jako vlny 1–2.

---

## 0. Opravy stávajícího registru

### 0.1 Závorky v booru tazích se posílají neescapované — **chyba, oprava před vším ostatním**

V registru je 41 výskytů `(medium)` / `(style)` (`oil painting (medium)`,
`colored pencil (medium)`, `fine art parody`…). ComfyUI parser promptu čte
`(text)` jako **zdůraznění s váhou 1.1** a závorky zahodí — model tedy
dostane `oil painting` + samostatné slovo `medium` s váhou 1.1, ne danbooru
tag `oil painting (medium)`. Správný zápis pro ComfyUI je `\(medium\)`.
V kódu se neescapuje nikde (`grep '\\('` v `comfyui_service.dart`,
`image_studio_provider.dart`, `style_preset.dart` — nula zásahů).

Dopad: všechny booru modely (Pony, Illustrious, NoobAI, WAI, Hassaku,
Animagine, Atomix, AutismMix) dostávaly u 41 z 62 stylů s tagy médium
rozbité. Pravděpodobně to je část vysvětlení vlny 5 („ani jeden Pony model
nevyrobí médium — styl dorazí jako kostým“).

Co udělat:
- Escapovat `(` a `)` v textu stylu **při odesílání do ComfyUI**, ne
  v registru — registr má zůstat čitelný danbooru slovník a stejné tagy čte
  i lab i FINETUNE export. Místo: `applyStylePreset()` dostane parametr
  (nebo `ComfyUIService._prepare()` escapuje celý blok stylu, ale ten už
  blok od promptu neodliší — proto raději v provideru `_styled()`, kde se
  ví, co je styl a co uživatel). NIM backendy (flux) escapování nepotřebují
  a stejně dostávají `block`, ne `booru`.
- **Neescapovat uživatelský prompt**: uživatel může váhy `(…:1.3)` psát
  schválně.
- Test v `style_preset_test.dart`: pro booru dialekt a ComfyUI cíl jsou
  všechny závorky escapované; pro natural dialekt se text nemění.
- **Změřit před a po** (lab, `param.styleDialect=booru`, 4 booru modely,
  ~15 stylů s `(medium)` tagem, repose + txt2img, seed 777): jestli se
  u Pony/Illustrious objeví médium. Výsledek do `style-matrix.md` jako vlna
  7a — je to první změna, která může přepsat verdikty vln 3–5 o booru
  modelech, takže se zapisuje, i kdyby vyšla negativně.

> **Výsledek 7a (2026-10-31):** oprava zůstává, ale styl měřitelně nezměnila
> (`docs/style-matrix.md`). Tvrzení výš, že „pravděpodobně vysvětluje vlnu 5“,
> neplatí.

### 0.1b Mrtvé tagy v registru (nález při implementaci, 2026-10-31)

Proti API Danbooru: z 418 různých tagů v 62 `booru` textech **227 neexistuje
nebo má pod 50 postů** (334 ze 771 výskytů) — `stylized`, `earth tones`,
`post-impressionism`, `flat background`, `visible brushstrokes`, `naive art`,
`mosaic`, `tempera (medium)` (3 posty). CLIP je přečte jako běžná slova, takže
vlna 4 přesto naměřila zlepšení, ale jako tagy je model nezná. Přepis živými
tagy (`tools/lab/candidates/booru-v2.json`, `@v1` proti `@v2`) je běh **7h**;
do registru jde jen tam, kde `@v2` na archu vyhraje.

### 0.2 Bloky, které neprošly na žádném dialektu — přepsat

Z vlny 4: `dunhuang`, `romanfresco` dávají na obou dialektech „plochý
pastelový oděv“; chyba je v popisu. Z vlny 1: `assyrian`, `mesopotamian`,
`hebrew`, `arabian` = „kamenný reliéf v zemitých tónech“ → béžová stěna
u většiny modelů. Z vlny 5: dno Pony linie u `baroque`, `inca`,
`romanfresco`.

Společný problém těch bloků: popisují **náladu a materiál** („calm
monumental presence“, „earthy tones“, „weathered texture“), ne **co je na
obraze vidět**. Recept na přepis — každý blok musí mít aspoň tři z těchto
čtyř konkrétních kotev, a to v tomhle pořadí: *médium/nosič* → *linie
a tvar figury* → *paleta jmenovitě* → *jeden nezaměnitelný motiv*:

| id | dnes | návrh kotev (kandidát, změřit) |
|---|---|---|
| `dunhuang` | „flowing ribbons, ochre and lapis, weathered plaster“ | *mineral pigment mural on plaster*, **flying apsaras with long trailing scarves**, malachite green + lapis + oxidized red-brown skin (typické zhnědlé olovo), lotus halo, musical instruments |
| `romanfresco` | „soft pastel colors, classical drapery“ | *buon fresco on red (Pompeian red) wall panel*, **fourth-style architectural frame**, black and cinnabar red fields, garland and candelabrum ornament, matte chalky surface |
| `assyrian` | „strong outlines, low-relief shading“ | *carved alabaster slab*, **lamassu / winged genie profile**, square curled beard in rows of spiral curls, rosette bracelet, cuneiform band, monochrome pale stone — **ne „earth tones“** |
| `mesopotamian` | „composite profile, carved stone texture“ | sumerský **votive figure with huge inlaid eyes**, hands clasped, fleece skirt (kaunakes), shell-and-lapis inlay — tím se odliší od `assyrian`, dnes jsou skoro synonyma |
| `hebrew` | „simple strong outlines, modest earth palette“ | Historicky nejslabší základ (starověké hebrejské umění figuru skoro nemá). Návrh: **přejmenovat obsah** na *Dura-Europos synagogue fresco* (3. stol., jediné dochované figurální) — frontální figury v řadách, parthské kalhoty a kaftan, zjednodušené tváře, červeno-okrová a šedá na omítce. Id `hebrew` zůstává (persistuje se na uzlech), label se změní |
| `arabian` | „elegant elongated figures, soft desert tones“ | *Qaryat al-Faw mural* / nabatejský styl: frontální busta s **velkýma očima a hroznem vína**, bílá omítka, červený a černý obrys — konkrétní, ne „calm presence“ |
| `inca` | „geometric patterns, gold and red“ | **tocapu grid** (čtvercová mřížka geometrických znaků) na tunice, stupňovitý motiv, barevné pásy vlny, zlatá maska — a pro booru variantu `checkered`, `geometric pattern`, `andean` |
| `baroque` | „chiaroscuro, deep shadows, rich dark colors“ | na Pony dno; pro **booru** dialekt přidat `tenebrism`, `candlelight`, `dark background`, `oil painting \(medium\)`, `baroque`, `fine art parody`; blok nechat |

Měření: přepsané bloky + staré jako kontrola, 6 modelů (juggernaut-xl,
illustrious-xl, noobai-xl, pony, flux-schnell, flux-manga), oba náměty
(baletka, muž u stolu), repose + txt2img. Laťka jako ve vlně 4: pohled
na arch, metrika jen řadí.

### 0.3 Smíšená skupina z vlny 4 — druhý seed a ruční doplnění

18 kulturních stylů bez `booru` (assyrian, ledger, maya, inca, thangka,
dogon, minoan, egyptian, minhwa, greek, filipino, baroque, woodcut, persian,
impressionist, chineseink, ukiyoe, illumination) má kandidátské tagy
v `tools/lab/candidates/cultural-booru.json`, ale jeden seed nerozlišil
efekt od šumu. Vlna 4 výslovně žádá **druhý seed** před zápisem a `egyptian`
označuje za ruční přidání (hieroglyfy na lemu, které barevná metrika
nevidí). Po opravě 0.1 je to navíc úplně jiné měření (tagy s `(medium)`
dorazí poprvé celé). Spustit znovu se seedy 777 a 778, 4 booru modely.

### 0.4 Rekvizity v blocích umělců — druhý námět pro všech 42

Vlna 3 zapsala známé omezení: bloky umělců nesou rekvizity a vedlejší
postavy (Kahlo opici, Chagall milence, Kandinskij jezdce, Mucha svatozář)
a mimo Degase se měřily jen na baletce v repose, kde je drží hloubková
mapa. V txt2img na jiném námětu můžou obsah přepsat. Od vlny 5 jsou styly
v appce v txt2img. Spustit všech 42 na „a man reading at a table“ v txt2img
na 4 modelech (juggernaut-xl, illustrious-xl, flux-schnell, pony) a
u každého stylu rozhodnout: **nechat / vyškrtnout rekvizitu z bloku**
(ne vyhodit styl — Degas byl krajní případ, kde rekvizita byla celý styl).
Kandidáti na škrt podle textu: `kahlo` (monkey, flowers in hair), `chagall`
(floating lovers, goat), `kandinsky-early` (rider), `hockney-pool`
(swimming pool), `gauguin` (tahitian women), `rivera` (workers), `hopper`
(diner). Pravidlo pro Opuse: rekvizita smí zůstat, jen když je zároveň
**materiálem obrazu** (Lichtensteinovy rastry, Seuratovy tečky), ne když
je obsahem.

### 0.5 Popisky modelů (`styleNote`)

Šest modelů nese `_unmeasured`: `cyberrealistic-xl`, `realvis-xl`,
`lustify-zenith`, `hassaku-illustrious`, `autismmix-pony`, `sdxl-base`.
Každý probe v jednom běhu: 20 stylů (10 kulturních, 10 umělců; po vlně 7
i 10 médií), txt2img, oba náměty. Popisek je jedna věta o **výchozí scéně**
modelu (zásada z vlny 1), ne výčet schopností.

`flux-manga` má „stylů zná jen pár“ z vlny 1 (25 stylů, img2img = Kontext).
Vlna 6 na něm změřila 42 umělců v repose s rozptylem 0.528 — popisek
je zastaralý. Přepsat podle vlny 6 (+ nového měření).

`flux-kontext` nebyl změřen nikdy (lab ho neumí, img2img chce referenci
v requestu). Popisek je odhad. Buď ho označit jako `_unmeasured`, nebo
(volitelně, větší práce) doplnit do labu `nim.go` img2img s referencí
base64 — pak jde kontext změřit stejně jako schnell. Pro vlnu 7 **není
podmínka**; zapsat jako follow-up.

### 0.6 Co se z měření ví o každé rodině — a co z toho plyne pro nové texty

| rodina | modely | dialekt | co změřeno | důsledek pro vlnu 7 |
|---|---|---|---|---|
| FLUX (T5) | flux-schnell, flux-manga, flux-kontext | natural | schnell: 82/82 txt2img (vlna 5), manga: 42 umělců repose/img2img (vlna 6); věta pro T5 nic nepřidala (ablace 3a) | `block` stačí; psát ho jako výčet vizuálních kotev, ne jako větu. Kontext neměřen |
| SDXL fotoreal (CLIP) | juggernaut-xl, -lightning, cyberrealistic, realvis, lustify, sdxl-base | natural | juggernaut: vše; ostatní nic | „nejširší rozsah, styl inscenuje jako kostým a kulisu“ — **média** jsou hypotéza, že tahle rodina konečně dostane materiál místo kostýmu, protože médium kostýmem být nemůže. Bloky ≤ 35 slov (CLIP 77 tokenů; ComfyUI sice dělí na chunky, ale druhý chunk je slabší) |
| Illustrious linie (booru) | illustrious-xl, noobai-xl, wai, hassaku | booru | tagy > věta na všech (vlna 4: 0.76–0.93 vs 0.39–0.69); tag umělce nepomohl | danbooru má **bohatý slovník médií** (`watercolor \(medium\)`, `marker \(medium\)`, `graphite \(medium\)`, `gouache \(medium\)`, `screentone`, `lineart`, `pixel art`, `papercraft`, `clay \(medium\)`, `plush`, `figure`…) — média jsou kategorie, kde tagy sedí nejlíp. Po 0.1 je poprvé dostanou celé |
| Animagine | animagine-xl | booru | jako Illustrious, slabší | totéž |
| Pony linie (booru) | pony, atomix, autismmix | booru | jména hashovaná; médium nikdy (vlna 5) | po 0.1 znovu; navíc osa `param.stylePosition=front` (score tagy jdou první, styl na konci má nejnižší váhu — hypotéza, že u Pony styl před námětem pomůže; lab osu má, nikdy se na Pony neměřila) |
| SD 1.5 | sd15 | natural | „styl nepřejímá“ | neměřit, nechat |

---

## 1. Datový model a UI — co musí vzniknout před kandidáty

### 1.1 Kategorie stylu

Dnes picker dělí sekce podle `artist != null`. Třetí kategorie to nezvládne.
Přidat:

```dart
enum StyleKind { culture, artist, medium }
```

na `StylePreset` jako `kind` (povinné; `artist`/`period` zůstávají, jen
u `StyleKind.artist` jsou povinné — test to hlídá). Picker: tři sekce
„Kultury a epochy“ / „Umělci“ / „Média a techniky“ — a protože s ~300
položkami přestává stačit jedna lista, **sekce sbalitelné** s počtem
v hlavičce (vzor `HairSheet`: sekce + hledání bez diakritiky). Hledání
`styleMatchesQuery` rozšířit o `period` (hledá „1920“ → art deco, lempicka)
a o český klíč sekce.

Soubor `style_preset.dart` by měl ~3 000 řádků. Rozdělit na `part`y:
`style_presets_cultures.dart`, `style_presets_artists.dart`,
`style_presets_media.dart`, `kStylePresets` = konkatenace. Test unikátnosti
id přes celek zůstává.

### 1.2 Co se nemění

- `GenNode.styleId` — jeden styl na uzel. **Skládání médium + umělec
  (akvarelový Mucha) je mimo rozsah**; je to lákavé, ale zdvojnásobí
  prostor měření a změní persistenci. Zapsat jako follow-up.
- `blockFor(dialect)` — dvě pole, `block` a `booru`; ablace 3a platí.
- Styl se připojuje za prompt; inpaint styl nedostává.
- Kadeřník má vlastní katalog, nedotýká se.

### 1.3 Lab

- `--styles-file` toleruje cizí klíče, takže kandidátské JSONy mohou nést
  `kind` už teď. Manifest ať `kind` propíše do `styles[]`, aby ho
  `sheets.py` mohl použít jako skupinu řádků.
- `sheets.py` `WAVES`: každý zapsaný běh vlny 7 dostane arch v `docs/sheets/`
  (zapečené WebP, jako dřív).
- Escapování z 0.1 **musí dělat i `dump.dart`** (staví graf stejným kódem
  appky — pokud se escapuje v provideru, lab ho obchází; proto raději
  pomocná funkce v `style_preset.dart`, kterou volá obojí).

---

## 2. Kandidáti — média a techniky (122)

Recept na text. **`block`** (≤ 30 slov): *médium na nosiči* → *stopa
nástroje* → *jak se chová barva/okraj* → *povrch*. Žádné nálady, žádné
„beautiful“. **`booru`**: danbooru tagy médií (`xxx \(medium\)` — v registru
bez escapování, escapuje odesílání), `traditional media` nebo `3d`/`photo
\(medium\)` podle povahy, + 3–5 vizuálních tagů (`visible brushstrokes`,
`paper texture`, `monochrome`, `sketch`, `lineart`). Label česky.

Duplicity s registrem jsou vyřešené předem: `chineseink` (sumi-e),
`ukiyoe` (mokuhanga), `woodcut` (expresionistický dřevořez),
`papercut`, `stainedglass`, `illumination`, `davinci-chalk` (sanguine),
`goya-caprichos` (akvatinta), `warhol` (sítotisk), `lichtenstein`
(komiksový rastr), `seurat` (pointilismus), `matisse-cutout` — ty se
**nepřidávají znovu**; blízké položky níž jsou záměrně jiné (linoryt ≠
dřevořez, risograf ≠ sítotisk).

### Malba (18)
| id | label | kotvy |
|---|---|---|
| `oil-impasto` | Olej — impasto | tlusté nánosy, hřebeny barvy, stopy špachtle, lesk oleje |
| `oil-glazing` | Olej — lazury (staří mistři) | hladké průsvitné vrstvy, tmavá imprimitura, sfumato okraje, krakeláž |
| `oil-alla-prima` | Olej — alla prima | mokré do mokrého, široké tahy, nedokončené okraje, viditelné plátno |
| `palette-knife` | Špachtle | ploché hrany barvy, žádný štětec, lámané plochy |
| `acrylic-flat` | Akryl — ploché plochy | matné, ostré hrany, saturované, bez textury |
| `acrylic-pour` | Akryl — lití (fluid art) | buňky, mramorování, kovové pigmenty |
| `watercolor-wet` | Akvarel — mokré do mokrého | rozpité okraje, květy barvy, bílá papíru, granulace |
| `watercolor-dry` | Akvarel — suchý štětec | zrnitý tah, tvrdý papír, lavírované stíny |
| `watercolor-ink-line` | Akvarel s perokresbou | tenká tušová linka + lehká lavura (urban sketch) |
| `gouache` | Kvaš | krycí matná barva, plochý poster look, lehce křídový |
| `egg-tempera` | Vaječná tempera | jemná šrafura štětcem, matná, na desce s křídovým podkladem |
| `casein` | Kaseinová tempera | sametový mat, lehce pastelové, rychlé tahy |
| `encaustic` | Enkaustika (vosk) | tavený vosk, hloubka vrstev, škrábané linie, mléčný lesk |
| `fresco-buon` | Freska | mokrá omítka, matné minerální pigmenty, denní švy (giornate), prasklá omítka |
| `airbrush` | Airbrush | hladké gradienty, žádný tah, chromový lesk, 80. léta |
| `spray-stencil` | Sprej přes šablonu | tvrdé hrany, přestřiky, kapky, zeď |
| `finger-paint` | Malba prsty | otisky prstů, rozmazané, dětsky syté |
| `miniature-gouache` | Miniatura na slonovině | drobounké tečkování, hladký lesklý nosič, oválný formát |

### Kresba (16)
| id | label | kotvy |
|---|---|---|
| `graphite` | Tužka | grafit, tonální šrafura, rozmazané stíny, bílý papír |
| `graphite-hard` | Tvrdá tužka — technická | tenká rovnoměrná linka, bez stínování, konstrukční čáry |
| `colored-pencil` | Pastelky | vrstvené voskové barvy, zrno papíru, lesk z tlaku |
| `charcoal` | Uhel | černý sametový, rozmazané plochy, vymazávané světla, drť |
| `conte` | Conté / křída na tónovaném papíru | černá + bílá křída na šedém/hnědém papíře, tři barvy |
| `silverpoint` | Stříbrná tužka | stříbrošedá tenká linka, teplý podklad, bez korekcí |
| `ballpoint` | Propiska | modrá/černá kuličková, hustá křížová šrafura, lesk inkoustu |
| `fineliner` | Fineliner — perokresba | tenké černé linie, stippling, bílé pozadí, bez tónů |
| `nib-ink` | Redispero a tuš | proměnná tloušťka linky, cákance, šrafura |
| `brush-ink` | Štětec a tuš (ne sumi-e) | expresivní černé tahy, suchý štětec, komiksové inkoustování |
| `marker` | Lihové fixy (Copic) | ploché vrstvené tóny, pruhy překryvu, bílý highlight |
| `crayon` | Voskovky | voskový lesk, hrubé zrno, dětská kresba |
| `soft-pastel` | Suchý pastel | prachové měkké přechody, rozmazané prsty, sametová barva |
| `oil-pastel` | Olejový pastel | mastné syté tahy, sgrafitové škrábání, lesk |
| `chalkboard` | Křída na tabuli | bílá/pastelová křída na černé, prašné okraje |
| `scratchboard` | Škrabaná technika | bílé linie škrábané do černé, rytinový vzhled |

### Kaligrafie a písmo (8)
| id | label | kotvy |
|---|---|---|
| `calligraphy-chinese` | Čínská kaligrafie (kchaj-šu) | černá tuš, hranaté tahy štětcem, červená pečeť, svislé sloupce |
| `calligraphy-cursive` | Divoká kurzíva (cchao-šu) | spojité tahy, rozstřik, rytmus |
| `calligraphy-arabic` | Arabská kaligrafie (thuluth) | protáhlé tahy seříznutým perem, zlatý ornament, modrá |
| `blackletter` | Gotická textura (blackletter) | lomené tahy širokým perem, hustá černá, iniciála |
| `copperplate` | Copperplate / anglická kurzíva | tenké vlasové a tlusté tahy, obloučky, špičaté pero |
| `brush-lettering` | Brush lettering | tlustý/tenký tah štětcovým fixem, akvarelový přechod |
| `hangul-calligraphy` | Korejská kaligrafie | štětec, kruhové tahy, tuš na hanji |
| `graffiti-wildstyle` | Graffiti wildstyle | propletená písmena, šipky, 3D stín, outline |

### Grafika a tisk (14)
| id | label | kotvy |
|---|---|---|
| `linocut` | Linoryt | tlusté bílé rýhy, plná černá, lehce nerovný tisk |
| `etching` | Lept | tenké rovnoběžné rýhy, tón z hustoty, deska s okrajem |
| `drypoint` | Suchá jehla | sametový otřep na linkách, černé měkké linie |
| `mezzotint` | Mezzotinta | ze tmy do světla, sametová černá, bez linií |
| `lithograph` | Litografie | mastná křída, zrno kamene, tónové plochy |
| `risograph` | Risograf | 2–3 spotové barvy, nedokonalý soutisk, zrno |
| `letterpress` | Knihtisk | vtlačené písmo, jedna barva, bavlněný papír |
| `monotype` | Monotyp | jediný otisk, rozmazané plochy, ghost print |
| `cyanotype` | Kyanotypie | pruská modř, bílá silueta, papírové zrno |
| `gyotaku` | Gyotaku (otisk ryby) | otisk tuší na rýžovém papíře, šupiny, prázdné oko |
| `block-print-textile` | Dřevěný razítkový tisk na látku | opakovaný vzor, nerovnoměrný tlak, indigo |
| `halftone-newsprint` | Novinový rastr | hrubé CMYK tečky, nažloutlý papír, lehký soutisk |
| `screentone-manga` | Manga screentone | tónové folie, síťované stíny, černobílá kresba |
| `engraving-banknote` | Rytina (bankovka) | guilloche, jemné křížení, jednobarevný intaglio |

### Textil a vlákno (10)
| id | label | kotvy |
|---|---|---|
| `embroidery` | Výšivka | satén stehy, viditelné nitě, plátno |
| `cross-stitch` | Křížková výšivka | pixelová mřížka křížků, Aida plátno |
| `tapestry-weave` | Gobelín | tkaná struktura, matné vlněné barvy, zubaté okraje tvarů |
| `quilt` | Patchwork / quilt | sešité látkové dílky, prošívání, potisk látek |
| `batik` | Batika | voskové praskliny, indigo/hnědá, rozpité okraje |
| `tie-dye` | Batika vázaná | spirály, rozpité duhové kruhy |
| `felt` | Plstění | chlupatý povrch, měkké tvary, vlněná barva |
| `knitted` | Pletené | očka, vlna, cop vzor |
| `lace` | Krajka | bílá prolamovaná vlákna na tmavém pozadí |
| `beadwork-loom` | Korálková výšivka | lesklé skleněné korálky v mřížce |

### Papír a lepenka (9)
| id | label | kotvy |
|---|---|---|
| `cardboard` | Lepenka | vlnitá lepenka, řezané hrany, hnědá, lepicí páska |
| `paper-collage` | Trhaný papír (koláž) | vrstvy, trhané bílé okraje, potištěné útržky |
| `origami` | Origami | skládaný papír, ostré hrany, geometrické plochy |
| `papier-mache` | Papírmaš | hrbolatý povrch, noviny pod barvou, lak |
| `quilling` | Quilling | stočené proužky papíru, prostorové spirály |
| `pop-up-book` | Vystřelovací kniha | kulisy z papíru v hloubce, přehyby |
| `paper-sculpture-layered` | Vrstvený papír (paper cut light box) | siluety v hloubce, podsvícení |
| `kirigami` | Kirigami | řezaný + skládaný bílý papír, stíny |
| `sticker-collage` | Samolepková koláž | lesklé nálepky, bílý lem, překryvy |

### Socha a objekt (18)
| id | label | kotvy |
|---|---|---|
| `marble` | Mramorová socha | bílý mramor, hladké přechody, stopy dláta v pozadí |
| `bronze` | Bronz | zelenohnědá patina, lesklé hrany, tmavý kov |
| `terracotta` | Terakota | cihlově červená pálená hlína, matná, drobné praskliny |
| `wood-carving` | Řezba ve dřevě | stopy dláta, letokruhy, teplé dřevo |
| `soapstone` | Mastek / hladký kámen | hladké oblé tvary, šedozelený kámen |
| `ice-sculpture` | Ledová socha | průhledný led, lom světla, modravé |
| `sand-sculpture` | Pískový reliéf | zrnitý okrový písek, ostré hrany |
| `claymation` | Plastelína (claymation) | otisky prstů, matné syté barvy, stop-motion |
| `porcelain-figurine` | Porcelánová figurka | lesklá glazura, pastelové barvy, zlatý lem |
| `blue-white-porcelain` | Modrobílý porcelán | kobaltová modř pod glazurou, bílý střep, krakeláž |
| `ceramic-raku` | Raku keramika | kovový lesk, praskliny, kouřová černá |
| `mosaic-tesserae` | Mozaika | kamenné/skleněné kostičky, spáry, zlaté tesery |
| `cloisonne` | Email cloisonné | kovové přepážky, syté skelné barvy |
| `glass-blown` | Foukané sklo | průhledné, barevné žíly, odlesky |
| `brick-toy` | Stavebnicové kostky | hranaté dílky, lesklý plast, studs |
| `wax-figure` | Vosková figura | voskový polotransparentní povrch, panoptikum |
| `wire-sculpture` | Drátěná socha | tenký kovový drát, kontura v prostoru, stíny |
| `repousse-metal` | Tepaný kov (repoussé) | vystouplé tvary v plechu, zlatý/měděný lesk, tepání |

### Fotografické a mechanické (10)
| id | label | kotvy |
|---|---|---|
| `daguerreotype` | Daguerrotypie | zrcadlová stříbrná deska, měkká ostrost, oválná maska |
| `tintype` | Ferotypie | tmavý kov, skvrny, mokrý kolodiový proces |
| `polaroid` | Polaroid | bílý rám, vybledlé barvy, lehký flash |
| `lomography` | Lomo / cross process | vinětace, posunuté barvy, přepal |
| `pinhole` | Dírková komora | měkká kresba, dlouhý čas, vinětace |
| `infrared-film` | Infračervený film | bílá listí, tmavá obloha, zrno |
| `double-exposure` | Dvojexpozice | průsvitné překryvy, silueta + krajina |
| `photogram` | Fotogram | bílé siluety na černé, bez objektivu |
| `xray` | Rentgen | modročerný negativ, kosti, průsvit — *pozor, mění obsah; měřit na obou námětech* |
| `thermal` | Termokamera | falešné barvy, duhová škála |

### Digitální a jiné (9)
| id | label | kotvy |
|---|---|---|
| `pixel-art` | Pixel art | viditelné pixely, omezená paleta, dithering |
| `voxel` | Voxel | 3D kostky, izometrie |
| `low-poly` | Low poly | ploché trojúhelníky, tvrdé stíny |
| `vector-flat` | Vektor — flat design | čisté tvary, bez přechodů, bez obrysů |
| `cel-shaded` | Cel shading | dvoustupňové stíny, tlustý obrys |
| `ascii-art` | ASCII art | znaky v monospace, zelený terminál |
| `blueprint` | Blueprint | bílé linie na modré, kóty, mřížka |
| `isometric-diagram` | Izometrické schéma | 30° osy, čisté barvy, technické |
| `neon-sign` | Neonová reklama | svítící trubice, odraz na mokré zdi, tma |

### Ostatní materiály (10)
| id | label | kotvy |
|---|---|---|
| `pyrography` | Vypalování do dřeva | hnědé spálené linie, dřevo, gradient hořením |
| `marquetry` | Intarzie | dýhy různých dřev, hladké plochy, lesk |
| `sgraffito-plaster` | Sgrafito | škrábaná omítka, dva tóny, renesanční fasáda |
| `stained-concrete` | Beton | šedý hrubý povrch, otisk bednění |
| `rust-patina` | Rez a patina | oranžová rez, modrozelená měděnka |
| `latte-art` | Latte art | mléčná pěna na kávě, hnědobílá |
| `gingerbread` | Perník | cukrová poleva, hnědý perník, lineární ornament |
| `pressed-flowers` | Lisované květiny | sušené okvětní lístky, papír, průsvit |
| `sand-painting` | Malba pískem | barevný písek, zrno, geometrie — *odlišit od navajo (kultura)* |
| `tattoo-flash` | Tattoo flash (old school) | tlustý černý obrys, omezená paleta, žlutý papír |

Kategorie, které sem **nepatří** a plán je vědomě vynechává: „styly“
obsahu (steampunk, vaporwave, cyberpunk — mění scénu, ne materiál), lite
efekty (glitch, chromatická aberace — spíš postprocess), a vše, co by na
figuře změnilo tělo (voxel a low-poly jsou na hraně — měřit).

---

## 3. Kandidáti — umělci (63)

Recept z `docs/plan-artist-styles.md` § „Recept“ platí: `block` ≤ 35 slov,
*médium/období + „by Jméno“* první, 4–6 vizuálních znaků, povrch nakonec;
`booru` bez jména; `artist` + `period` pro UI. **Rekvizity jen jako
materiál (viz 0.4).** Autoři, kteří už byli zamítnuti (Michelangelo,
Modigliani, Zrzavý, Freud, Rockwell, Rembrandt, Degas), se **neopakují**
se stejným blokem; Caravaggio a Velázquez nesou riziko „= baroque“ a plán
je zařazuje s explicitně jiným blokem (modely, ne nálada).

Ilustrátoři a čeští autoři jsou zastoupeni víc, než by odpovídalo
„světoznámosti“, záměrně: ilustrace má nejčitelnější rukopis a čeští autoři
jsou pro uživatele appky domácí.

| id | artist | period | nezaměnitelná kotva |
|---|---|---|---|
| `durer-engraving` | Albrecht Dürer | mědirytiny 1500–1520 | hustá křížová šrafura, mědirytinová černobílá |
| `bosch` | Hieronymus Bosch | 1490–1510 | drobné hybridní tvorové, panoramatická scéna, průsvitné koule |
| `bruegel` | Pieter Bruegel st. | 1559–1569 | vesnické scény, drobné figury z nadhledu, zimní krajina |
| `van-eyck` | Jan van Eyck | 1430s | lazurový olej, mikroskopický detail, konvexní zrcadlo, červený turban |
| `titian` | Tizian | benátský kolorit 1540–1570 | teplý benátský kolorit, volný štětec v pozdním díle |
| `caravaggio` | Caravaggio | tenebrismus 1600–1610 | jeden zdroj světla zleva, špinavé nohy modelu, černé pozadí — *riziko = baroque* |
| `velazquez` | Diego Velázquez | 1630–1660 | stříbřitě šedá paleta, volné tahy zblízka, dvorní portrét |
| `rubens` | Peter Paul Rubens | 1610–1640 | růžová masitá pleť, vířivá kompozice, modré stíny v pleti |
| `fragonard` | Jean-Honoré Fragonard | rokoko 1760–1770 | pastelové růžové a mint, zahrada, hravý štětec |
| `david-neoclassical` | Jacques-Louis David | neoklasicismus 1784–1800 | hladký štětec, sochařské tělo, římská scéna, vlys |
| `ingres` | J.-A.-D. Ingres | 1808–1856 | porcelánová pleť, protáhlá záda, hladké linie |
| `friedrich` | Caspar David Friedrich | romantismus 1818–1830 | figura zezadu (Rückenfigur), mlha, mlhavá krajina |
| `turner` | J. M. W. Turner | pozdní 1835–1845 | rozpuštěné světlo, vír barvy, žlutá a bílá |
| `blake` | William Blake | 1795–1820 | barevné tisky, protáhlé svalnaté postavy, plamenné linie |
| `hokusai` | Kacušika Hokusai | 1830s | pruská modř, vlna s drápy, Fudži — *riziko = ukiyoe; blok přes Hokusaiovy „manga“ skici* |
| `hiroshige` | Utagawa Hirošige | 1833–1858 | déšť v šikmých čarách, bokashi gradient oblohy |
| `yoshitoshi` | Cukioka Jošitoši | 1880s | dramatické pózy, přízraky, moderní barvy mejdži |
| `kuniyoshi` | Utagawa Kunijoši | 1830–1850 | válečníci v tetování, tricky kompozice, koček |
| `manet` | Édouard Manet | 1863–1882 | černá jako barva, ploché osvětlení, bar |
| `renoir` | Pierre-Auguste Renoir | 1876–1885 | prosvítající skvrny světla přes listí, měkká pleť |
| `cassatt` | Mary Cassatt | 1880–1900 | matka s dítětem, pastel, japonský výřez |
| `whistler` | James McNeill Whistler | nokturna 1870s | tónová šedomodrá, mlha, „arrangement in grey“ |
| `sargent` | John Singer Sargent | 1884–1900 | bravurní dlouhý tah, bílý satén, tmavé pozadí |
| `sorolla` | Joaquín Sorolla | 1900–1910 | ostré středomořské slunce, bílé šaty, pláž |
| `zorn` | Anders Zorn | 1890–1910 | Zornova paleta (4 barvy), voda, červenohnědá pleť |
| `repin` | Ilja Repin | 1870–1890 | ruský realismus, Volha, hnědé tóny, davová scéna |
| `bilibin` | Ivan Bilibin | pohádkové ilustrace 1899–1910 | tlustý černý obrys, ornamentální rám, ruské pohádky |
| `vrubel` | Michail Vrubel | 1890–1902 | krystalické fasety, fialová a modrá, démon |
| `kirchner` | Ernst Ludwig Kirchner | Die Brücke 1908–1914 | ostré úhly, kyselé růžové a zelené, berlínská ulice |
| `marc` | Franz Marc | 1911–1914 | modří koně, barevné prizmy — *obsah; měřit na obou námětech* |
| `dix` | Otto Dix | Neue Sachlichkeit 1920–1926 | nelítostný veristický portrét, lazury, poválečné |
| `klee` | Paul Klee | 1920–1930 | mřížky barev, dětská linka, hieroglyfy |
| `leger` | Fernand Léger | 1920–1950 | trubkové postavy, primární barvy, černý obrys |
| `de-chirico` | Giorgio de Chirico | metafyzická malba 1912–1918 | prázdné náměstí, dlouhé stíny, arkády, figurína |
| `miro` | Joan Miró | 1925–1950 | biomorfní tvary, černé linie, primární barvy, hvězdy |
| `rousseau` | Henri Rousseau | 1891–1910 | naivní džungle, ploché velké listy, měsíc |
| `ensor` | James Ensor | 1888–1896 | masky, kostry, kyselé barvy, dav |
| `hammershoi` | Vilhelm Hammershøi | 1898–1910 | šedé interiéry, žena zezadu, prázdné dveře |
| `larsson` | Carl Larsson | 1895–1910 | akvarelový domácí interiér, švédské barvy, linka |
| `wyspianski` | Stanisław Wyspiański | pastely 1895–1907 | pastelový portrét dítěte, secesní linka, květy |
| `malczewski` | Jacek Malczewski | 1890–1920 | symbolismus, fauni a smrt vedle autoportrétu, polská krajina |
| `beksinski` | Zdzisław Beksiński | 1970–1985 | dystopická krajina, kostry, rezavě hnědá, bez názvu |
| `wyeth` | Andrew Wyeth | tempera 1948–1970 | suchá tempera, vybledlá tráva, hnědá, osamělost |
| `grant-wood` | Grant Wood | regionalismus 1930s | zaoblené kopce, hladká malba, americká gotika |
| `okeeffe` | Georgia O'Keeffe | 1920–1950 | zvětšený květ, hladké gradienty, kost, poušť |
| `jacob-lawrence` | Jacob Lawrence | 1940–1960 | ploché tempery, úhlové figury, syté primární barvy |
| `bearden` | Romare Bearden | koláže 1964–1975 | koláž z fotografií a papíru, fragmentované tváře |
| `kehinde-wiley` | Kehinde Wiley | 2005–2020 | fotorealistická figura před barokním florálním vzorem, který ji obrůstá |
| `kusama` | Yayoi Kusama | 1960–2020 | puntíky přes vše, dýně, nekonečné sítě |
| `murakami` | Takashi Murakami | superflat 2000–2015 | plochý veselý vzor, květiny s obličeji, hladký lesk |
| `moebius` | Moebius (Jean Giraud) | 1975–1990 | čistá linka ligne claire, pastelové pouště, sci-fi |
| `frazetta` | Frank Frazetta | 1965–1980 | olejová fantasy, dynamické svalnaté tělo, tmavé pozadí |
| `giger` | H. R. Giger | 1975–1985 | biomechanika, airbrush, monochrom šedá |
| `rackham` | Arthur Rackham | 1905–1920 | sépiová perokresba + akvarel, křivé stromy, skřítci |
| `dore` | Gustave Doré | 1860–1870 | dřevorytová ilustrace, dramatické světlo, husté šrafy |
| `sorayama` | Hajime Sorayama | 1978–1990 | chromové airbrush roboty, odlesky |
| `burian` | Zdeněk Burian | 1930–1970 | pravěk, kvaš, mamuti, teplý realismus |
| `born` | Adolf Born | 1970–2000 | karikaturní protáhlé postavy, pastelové barvy, dlouhé nosy |
| `trnka` | Jiří Trnka | 1940–1965 | loutková estetika, ilustrace pohádek, měkké tvary |
| `ales` | Mikoláš Aleš | 1880–1900 | lunety, národní motivy, tvrdý obrys, perokresba |
| `toyen` | Toyen | 1930–1950 | surrealismus, rozpité šedé, prázdné krajiny, dívky |
| `kupka-early` | František Kupka | před abstrakcí 1900–1910 | symbolistní figura, barevné spektrum, Mánesova linka |
| `preisler` | Jan Preisler | 1900–1910 | secesní symbolismus, modrozelená, mladík s koněm |

---

## 4. Kandidáti — kultury a epochy (56)

Tytéž zásady jako u 0.2: každý blok má konkrétní **motiv a nosič**, ne
náladu. Zamítnuté z vlny 2 (`ethiopian`, `wayang`, `amate`, `suprematism`,
`mughal`, `prerafael`, `adire`, `inuit`) se vrací jen dvě s jiným blokem:
`prerafael` (byl ≈ greek, protože blok popisoval mramorovou pleť; nový:
*zrzavé vlasy, květinová louka v detailu, středověké šaty, jasné lazury*)
a `inuit` → `inuit-printmaking` (Cape Dorset stonecut, ne „≈ ukiyoe“).

### Pravěk a starověk (10)
`cave-painting` (Lascaux: okr a uhel na skále, zvířata, otisky dlaní), `cycladic`
(mramorová idolka, složené ruce, bez tváře), `greek-vase-black` (černofigurová
keramika — **jiné než `greek`**, který je mramor), `greek-vase-red`
(červenofigurová), `etruscan-tomb` (fresky Tarquinia, tanečníci, červenohnědá
pleť), `roman-mosaic` (podlahová mozaika, tesery, geometrický rám),
`fayum` (fajjúmský mumiový portrét — enkaustika, velké oči, frontální),
`scythian-gold` (zvířecí styl, zlato, stočené šelmy), `moche` (peruánská
keramika, krémová a červenohnědá, linka), `nazca` (geoglyfy a keramika,
ploché barvy, stylizovaná zvířata).

### Středověk Evropa (8)
`kells` (insulární iluminace, propletence, spirály — jiné než `illumination`,
které je gotická), `bayeux` (vyšívaný pás, ploché figury, latinské popisky),
`romanesque-fresco` (katalánské apsidy, tvrdý obrys, modré a okrové pásy),
`gothic-altarpiece` (zlaté pozadí, polychromovaný, Mistr Theodorik),
`danse-macabre` (pozdně gotický dřevořez s kostlivci), `urnes-viking`
(propletená zvířata, dřevořezba), `pskov-icon` (ruská ikona — odlišit od
`byzantine`: plochější, červené pozadí, Novgorod/Pskov), `armenian-manuscript`
(kilikijská iluminace, sytá modrá, ptačí písmo).

### Novověk Evropa (10)
`flemish-still-life` (vanitas, tmavé pozadí, lesk na skle), `rococo` (bez
Fragonarda jako jména: pastel, zlaté rokaje, putti), `neoclassicism` (bílý
mramor, hladký štětec, řecká architektura), `romanticism-storm` (bouře,
ztroskotání, dramatická obloha), `hudson-river` (luminismus, široké údolí,
zlaté světlo), `orientalism` (19. stol. „harém“, teplé interiéry, dlaždice —
*obsahově citlivé, měřit na obou námětech*), `arts-and-crafts` (W. Morris:
hustý květinový vzor, plochá tapeta), `victorian-fairy` (drobné víly, hustý
detail, noc), `symbolism` (Moreau/Khnopff: sfinga, tajemství, zlaté
ornamenty), `nabis` (Bonnard/Vuillard: vzorované interiéry, plochá barva).

### 20. století hnutí (10)
`expressionism-painting` (Blaue Reiter/Brücke — malba, ne dřevořez), `dada-collage`
(fotomontáž, text, Hannah Höch), `de-stijl` (Mondrian/Van Doesburg: primární
barvy, černé pruhy — *bez figury; měřit zda vůbec*), `bauhaus-poster`
(geometrie, kruh/čtverec/trojúhelník, sans-serif), `precisionism` (Sheeler:
čisté tovární hrany), `socialist-realism` (hrdinský dělník, červené prapory,
akademická malba), `polish-poster` (polská plakátová škola: metafora, hrubý
štětec, ruční písmo), `psychedelic-poster` (Wes Wilson: vlnité písmo,
duhové vibrující barvy), `memphis-80s` (Memphis design: pastel + černé
tečky, cik-cak), `pin-up-50s` (Elvgren/Vargas: lesklý airbrush, pin-up —
*měřit na mužském námětu*).

### Asie (10)
`nihonga` (minerální pigmenty na hedvábí, plátkové zlato, plochá tvář),
`yamato-e` (emaki svitek, střecha odfouknutá, mraky z mlhy), `enso-zen`
(jeden kruh tuší, prázdno — *téměř bez figury, měřit*), `kano-screen`
(zlatý paraván, borovice, tygr — *riziko = rinpa*), `nianhua` (čínské
novoroční tisky, syté červené, baculaté děti), `peking-opera-mask`
(malovaná tvář, symetrie, červená/černá/bílá), `tang-sancai` (tříbarevná
glazura, keramická figurka), `madhubani` (Mithila: dvojitá linka, vyplněné
vzory, žádné prázdné místo), `warli` (bílé trojúhelníkové figurky na hnědé),
`pattachitra` (Urísa: tvrdý černý obrys, červené pozadí, lotus).

### Afrika, Amerika, Oceánie (8)
`benin-bronze` (plakety, reliéf, korálový náhrdelník), `ndebele` (geometrické
fasády, černé linky, pastel), `kuba-cloth` (rafiový samet, geometrické
rastry), `tingatinga` (tanzanský naivní styl, lesklé emaily, zvířata),
`san-rock-art` (jihoafrické skalní malby, eland, běžící figury), `haida-formline`
(formline, ovoid, černá/červená), `navajo-sand` (symetrické yei figury, písek),
`kamasan-bali` (wayang-like malba na plátně, hnědé a okrové — *odlišit od
zamítnutého `wayang` nosičem: plátno, ne kůže*).

---

## 5. Postup pro Opuse — kroky a brány

1. **Oprava 0.1 (escapování)** + test + lab běh 7a (před/po na booru
   modelech). Zápis do `style-matrix.md`. *Brána:* nic dalšího se neměří,
   dokud není jasné, jak moc 0.1 mění booru výsledky — mohlo by to změnit
   i verdikty 0.3.
2. **Datový model 1.1**: `StyleKind`, party, picker se třemi sbalitelnými
   sekcemi, hledání přes `period`. Testy: každý `artist` má `kind: artist`,
   každé `medium` má `booru` (tagy médií existují pro všechna) — ne naopak.
   Lab: `kind` v manifestu a `sheets.py`.
3. **Kandidátské soubory**: `tools/lab/candidates/media.json` (122),
   `artists-wave7.json` (63), `cultures-wave7.json` (56), `fixes-wave7.json`
   (přepsané bloky z 0.2 + staré jako kontrola). Formát `--styles-file`
   (`id/label/block/booru/artist/period/kind`). Texty podle receptů v § 2–4;
   **u médií booru tagy ověřit proti danbooru wiki** (tag `xxx (medium)`
   musí existovat; co neexistuje, nahradit opisem — `traditional media` +
   vizuální tagy).
4. **Dvě kola (rozhodnutí uživatele 2026-10-31):** první kolo = všichni
   kandidáti přes 7 zástupců rodin: juggernaut-xl, illustrious-xl, noobai-xl,
   pony, **animagine-xl**, flux-schnell, flux-manga (počty níž jsou pro 6
   modelů, se sedmým vyjdou o 1/6 vyšší). Pak stránka pro uživatele; jen styly,
   které vybere, jedou ve druhém kole přes všech 16 modelů, které lab umí
   a styl přejímají (bez flux-kontext, flux-fill, sd15).

   **Běhy** (každý ≤ 4000 buněk, seed 777, náměty baletka + muž u stolu):
   - 7b média: 122 × 6 modelů (juggernaut-xl, illustrious-xl, noobai-xl,
     pony, flux-schnell, flux-manga) × 2 náměty × txt2img = 1 464 + baseline.
     Pak nejlepších ~40 v repose s referencí.
   - 7c umělci: 63 × 6 × 2 × txt2img = 756; vítězové v repose.
   - 7d kultury + opravy: (56 + 8 + 8 kontrol) × 6 × 2 = 864.
   - 7e Pony `param.stylePosition=front|end` na 30 stylech (po 0.1).
   - 7f probe 6 neměřených modelů × 30 stylů × 2 náměty = 360 → `styleNote`.
   - 7g druhý námět pro 42 stávajících umělců (0.4): 42 × 4 × 1 = 168.
5. **Rozhodnutí dělá uživatel (2026-10-31):** nic se nevyřazuje bez jeho
   souhlasu, ani citlivé položky. Model měří vše a připraví stránku s archy
   a návrhem; registr se mění až po odsouhlasení. Dál původní postup:
   **Návrh verdiktů** jako ve vlnách 2–4: metrika řadí, rozhoduje pohled na arch;
   tabulka přidáno / zahozeno-barva / zahozeno-obsah / zahozeno-duplicita
   s důvodem u každé položky. Archy do `docs/sheets/` přes `WAVES`.
6. **Zápis do registru** jen prošlých; `styleNote` přepsat u všech
   měřených modelů. Aktualizovat hlavičkový komentář `style_preset.dart`
   (dnes říká „82 stylů“) a `CLAUDE.md` odstavec „Styly“.

Laťka počtu: cíl 50+/50+/100+ je cíl pro **kandidáty**, ne pro registr.
Když projde 70 médií místo 100, je to výsledek měření, ne selhání plánu —
viz vlna 2, kde ze 24 prošlo 15.

## 5b. Srovnání rychlosti SPARK × L40S (přání uživatele, 2026-10-31)

Po první frontě, **před LAB_DONE**: stejné grafy, 20 buněk na model (5 SDXL +
flux-manga), seed 777, `LAB_PARALLEL=1`, prázdná fronta, na SPARKu přes broker.
První buňka modelu = načtení, zvlášť; jinak medián. Fp8 na L40S označit,
flux-schnell porovnat zvlášť (jiná cesta). Výsledek na stránku vlny 7. Pozor:
`q-l40s.sh` posílá LAB_DONE sám, kalibraci je tedy potřeba zařadit před něj.

## 6. Co nedělat

- Nepřidávat styl bez `booru`, pokud existuje danbooru tag — po 0.1 je
  to poprvé, kdy tagy dorazí celé, a natural blok na booru modelu je
  prokazatelně slabší (vlna 4).
- Nepsat `styleNote` od stolu (`_unmeasured` je k tomu).
- Neskládat dva styly na uzel (follow-up, § 1.2).
- Neměnit id existujících stylů (persistují se na uzlech a v FINETUNE).
- Nezapisovat verdikt z jednoho seedu tam, kde rozdíl mezi dialekty je
  menší než rozptyl mezi modely (poučení vlny 4).
