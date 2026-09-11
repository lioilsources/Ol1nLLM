# Plán: umělecké styly podle konkrétních umělců (třetí vlna)

Cíl: rozšířit `kStylePresets` o **figurální** styly konkrétních malířů
(Da Vinci, Picasso, Basquiat, Hockney, Monet, Kahlo, Goya, Kandinskij,
Modigliani, Van Gogh, Toulouse-Lautrec, Mucha, Zrzavý, Kubišta + doplněné
autory), u autorů s více epochami jako samostatné styly `autor-období`, a
naučit appku i lab **popisovat styl jinak pro každou rodinu modelů** — protože
jméno malíře u některých rodin nefunguje vůbec.

Kandidáti s texty pro všechny tři rodiny jsou připravené v
`tools/lab/candidates/artists.json` (54 stylů; formát je rozšířený tvar
`--styles-file`, dnešní `dump.dart` z něj čte jen `id/label/block`, takže
soubor jde pustit už teď pro CLIP variantu).

Zásada z předchozích vln zůstává: **nic se do registru nedostane bez měření**
(`docs/style-matrix.md`). Tento plán proto má napřed experiment, který
rozhodne o datovém modelu, a teprve pak kód.

> **Stav po ablaci 3a (2026-09-10):** datový model má **dvě pole, ne tři** —
> `block` (čte ho CLIP i T5; věta pro FLUX na flux-manga nic nepřidala, pole
> `prose` nevzniklo) a `booru` (tagy bez jména; všechny tři anime modely z nich
> převzaly styl lépe nebo stejně jako z popisu). `booruArtist` nevzniklo: tag
> umělce nepomohl nikde, u NoobAI jednou škodil, a na Danbooru má `(style)` tag
> jen Van Gogh (103 postů) a Picasso (12). `PromptDialect` má proto hodnoty
> `natural` a `booru`, ne `clip/booru/t5`. Tabulka v §1 a náčrt v §4.1 níže
> jsou původní odhad; naměřené výsledky jsou v `docs/style-matrix.md`.

---

## 1. Proč jeden `block` nestačí

Dnešní `StylePreset.block` je jeden text pro všechny modely. U kulturních
stylů to fungovalo, protože popis („bold black outlines, flat colour") je
vizuální. U umělců je nejsilnější token **jméno**, a to čte každá rodina
jinak:

| rodina (dialekt) | modely | jak čte prompt | jméno umělce |
|---|---|---|---|
| **clip** — SDXL base finetune / SD 1.5 | juggernaut-xl, juggernaut-xl-lightning, sd15 | CLIP, volná fráze + tagy, LAION captiony | **funguje** (LAION je plný „painting by Van Gogh") — u světových jmen nejsilnější signál, který máme |
| **booru** — Pony linie | pony, atomix-pony-anime | Danbooru tagy + score tagy | **nefunguje záměrně** — Pony V6 měl jména umělců v captionech zahashovaná; jméno je šum |
| **booru** — Illustrious / anime SDXL | illustrious-xl, noobai-xl, wai-illustrious, animagine-xl | Danbooru tagy; NoobAI/Illustrious mají artist tagy natrénované | jméno ve větné podobě slabé; může fungovat jen jako **Danbooru `(style)` tag** (parodie „fine art parody"), a jen pro umělce, které Danbooru zná (Mucha, Van Gogh, Klimt…) |
| **t5** — FLUX | flux-schnell, flux-kontext, flux-manga, (flux-fill jen inpaint, styl se neaplikuje) | T5 přirozený jazyk, věty | FLUX.1 má jména umělců známě „rozředěná" — u Van Gogha ještě něco, u Zrzavého nic; nese to **popis techniky ve větě** |

Čeští autoři (Zrzavý, Kubišta, Lada, Josef Čapek) nejsou v žádném datasetu
v takovém počtu, aby jméno něco udělalo — u nich musí popis nést styl celý,
jméno je tam jen pro člověka a pro CLIP „cheap shot" (nic nezkazí).

### Recept na tři varianty textu

Každý styl má tři texty (viz JSON), psané podle jedné šablony, aby byly
srovnatelné:

- **`block` (clip)** — ≤ 35 slov. Pořadí: *médium/období + „by Jméno"* první
  (nejvyšší CLIP váha uvnitř bloku), pak 4–6 vizuálních znaků (linie, paleta,
  typická rekvizita/scéna), nakonec povrch/textura. Stejný registr jako
  dnešních 40 bloků, takže se s nimi dá srovnávat.
- **`booru`** — jen Danbooru slovník, mezery místo podtržítek (jako dnešní
  bloky a `positivePrefix`): médium (`oil painting (medium)`, `traditional
  media`, `tempera (medium)`, `pastel (medium)`), hnutí (`impressionism`,
  `cubism`, `art nouveau`, `pop art`, `pointillism`, `surreal`), paleta jako
  `<barva> theme`, rekvizity jako běžné tagy (`parasol`, `tutu`, `bowler
  hat`), obličejové znaky (`no pupils`, `thick eyebrows`, `long neck`).
  **Bez jména.** Volitelně `booruArtist` (např. `alphonse mucha (style)`) —
  zapojí se jen u Illustrious linie a jen pokud experiment 2a ukáže, že tag
  něco dělá; před použitím ověřit existenci tagu a počet postů na Danbooru
  wiki (tag pod ~200 posty model nezná).
- **`prose`** — jedna věta 30–45 slov začínající příčestím (`rendered as`,
  `painted in the manner of`, `drawn as`), aby po `, ` za promptem četla
  přirozeně; jméno uvnitř věty, technika popsaná slovy, žádný výčet tagů.
  Pro flux-kontext dává instrukční čtení („painted in the manner of…") smysl
  i jako editační pokyn.

Dva příklady, ať je rozdíl vidět (celé v JSON):

**vangogh-arles**
- clip: `portrait painting by Vincent van Gogh in Arles, thick impasto brushstrokes, vivid complementary colours, yellow and blue, green shadows on the face, flat patterned background, directional hatched strokes following the form, visible paint ridges`
- booru: `oil painting (medium), traditional media, impasto, post-impressionism, thick brushstrokes, yellow theme, blue theme, complementary colors, painterly, textured, flat background, visible brushstrokes`
- prose: `painted in the manner of Vincent van Gogh's Arles portraits, thick impasto strokes with visible paint ridges, vivid complementary yellows and blues, green shadows on the face, hatched brushwork that follows the form, and a flat patterned background`

**zrzavy** (jméno nikdo nezná, nese to popis)
- clip: `Czech symbolist painting by Jan Zrzavy, dreamlike melancholic figure with pale round face and large closed eyes, simplified doll-like body, soft glowing blue-green and pink haze, blurred contours, quiet mystical stillness, thin smooth tempera`
- booru: `symbolism, tempera (medium), traditional media, pale skin, round face, closed eyes, doll-like, soft focus, blue theme, pink theme, dreamy, melancholy, simplified, glowing, smooth shading`
- prose: `painted in the manner of the Czech symbolist Jan Zrzavý, a dreamlike melancholic figure with a pale round face and large closed eyes, a simplified doll-like body, contours softened into a glowing blue-green and pink haze, thin smooth tempera and mystical stillness`

---

## 2. Seznam stylů

Vodítko výběru: **figurální díla**, u kterých jde styl uplatnit na postavu
(pózu drží depth ControlNet, styl má dodat rukopis, paletu, rekvizity).
Abstraktní fáze jsou vynechané záměrně — druhá vlna už ukázala, že
suprematismus se s figurou drženou hloubkovou mapou pere.

### 2a. Zadaní autoři (25 stylů)

| id | autor / období | co se má chytit | pozn. |
|---|---|---|---|
| `davinci` | Leonardo, sfumato c. 1490–1510 | měkké kouřové stíny, olivová/umbra, mlžná krajina | |
| `davinci-chalk` | Leonardo, studie křídou | sangvina na tónovaném papíře, šrafura, zrcadlové písmo | monochrom — barevná metrika falešně poplaší (viz vlna 2) |
| `picasso-blue` | modré období 1901–04 | monochromní modrá, vyhublá figura, dlouhé ruce | |
| `picasso-rose` | růžové období 1904–06 | růžová/okr, harlekýn, cirkus | |
| `picasso-cubist` | figurální kubismus 1937–40 (Dora Maar) | profil + en face zároveň, černé obrysy, ploché barvy | figurální; analytický kubismus 1909–12 vynechán (skoro abstrakce) |
| `picasso-neoclassical` | neoklasicismus 1917–25 | monumentální těžké údy, pláž | |
| `basquiat` | 1981–83 | lebkovitá hlava, koruna, škrtaný text, olejová křída | |
| `hockney-pool` | LA akryly 1964–72 | ploché barevné plochy, bazén, ostré stíny | |
| `hockney-joiner` | polaroidové koláže 1982–86 | překryté polaroidy s bílým rámem, posunuté pohledy | „fotokoláž", ne malba — model může vrátit fotku; sledovat |
| `monet` | figury v plenéru 1870s | slunečník, roztřepené tahy, levandulové stíny | riziko duplicity s `impressionist` |
| `kahlo` | autoportréty 1930–50 | srostlé obočí, květiny ve vlasech, tehuana, opice, retablo | |
| `goya-tapestry` | rokokové kartony 1775–92 | pastel, majos a majas, piknik | |
| `goya-black` | černé malby 1819–23 | černá/hnědá/okr, groteska, divoké tahy | |
| `goya-caprichos` | lepty 1797–99 | sépiový tisk, akvatinta, sovy a netopýři, popisek | monochrom |
| `kandinsky-early` | pohádkové tempery 1903–09 | jezdec v ruském kroji, klenotové tečky na tmavém podkladu | jediná figurální fáze; pozdější abstrakce vynechána (v zadání „Kardinsky" = Kandinskij) |
| `modigliani` | 1915–19 | labutí krk, oválná maska, prázdné mandlové oči | akty se od portrétů liší jen paletou — jeden styl |
| `vangogh-nuenen` | Nuenen 1883–85 | kalná hnědozelená, lampa, hrubé impasto | |
| `vangogh-arles` | Arles 1888–89 | impasto, komplementární žlutá/modrá, šrafované tahy | |
| `vangogh-saintremy` | Saint-Rémy 1889–90 | vířivé spirály kolem figury | riziko duplicity s `vangogh-arles` — nechat jen, když se liší i vizuálně |
| `lautrec-poster` | litografie 1891–96 | ploché plochy, silueta, crachis, nápis | |
| `lautrec-cabaret` | kabaret na kartonu 1888–95 | ředěný olej, prosvítající karton, zelené světlo na tváři | |
| `mucha-poster` | pařížské plakáty 1895–1905 | kruhová svatozář, mozaikový rám, vlasy | riziko duplicity s `artnouveau` |
| `mucha-slav-epic` | Slovanská epopej 1910–28 | bledá modrobílá tempera, dav v lněných krojích, zjevení | |
| `zrzavy` | symbolismus 1910–25 | bledá kulatá tvář, zavřené oči, modrozelený opar | jméno modely neznají |
| `kubista` | kuboexpresionismus 1910–12 | krystalické fasety, studená modrozelená/okr, ostré světlo | jméno modely neznají |

### 2b. Doplnění (29 stylů)

Světoznámí, originální, figurální. Vybíráno tak, aby každý přinesl jiný
mechanismus (linie / plocha / impasto / tisk / koláž), ne další „olej
s chiaroscurem".

| id | autor / období | pozn. |
|---|---|---|
| `schiele` | Egon Schiele 1910–18 | nervózní linie, bílé pozadí — velmi odlišný |
| `klimt-golden` | Klimt, zlaté období | **riziko duplicity se `secession`** (ten blok je prakticky Klimt); test rozhodne |
| `vermeer` | Vermeer | okenní světlo, ultramarín/žlutá |
| `rembrandt` | pozdní portréty | **riziko duplicity s `baroque`**; Caravaggio a Rubens z téhož důvodu vůbec nezařazeni |
| `botticelli` | 1480s | lineární grácie, tempera; jiné než `greek` |
| `michelangelo` | Sixtinská freska | cangiante, sochařské figury |
| `elgreco` | Toledo | protažené plamenné figury, bouřkové nebe |
| `munch` | 1892–1900 | vlnité tahy, oranžové nebe |
| `matisse-fauve` | fauvismus 1905–10 | zelený pruh na tváři, nemíchané barvy |
| `matisse-cutout` | výstřižky 1943–54 | jediná modrá silueta — hraniční figurálnost, ale postava zůstává |
| `gauguin` | Tahiti | cloisonné plochy s obrysem |
| `cezanne` | 1890s | konstruktivní paralelní tahy |
| `degas` | pastelové baletky | **pozor**: referenční fotka v matici je baletka — styl bude „snadný" a výsledek říká málo o přenosu; měřit i na druhém, netanečním námětu |
| `seurat` | pointilismus | tečky; odlišné od `impressionist` |
| `hopper` | americký realismus | ostré ranní světlo, samota |
| `warhol` | sítotisk | neonové misregistrované plochy, opakování |
| `lichtenstein` | pop art | Ben-Day rastr, bublina |
| `haring` | 1982–89 | piktogram s pohybovými čárami |
| `bacon` | 1949–75 | rozmazaná figura v klecové kresbě |
| `freud` | Lucian Freud | impasto maso, ostré studiové světlo |
| `rockwell` | ilustrace 1920–60 | lesklý olej, přehnaný výraz |
| `rivera` | mexické murály | zaoblené objemy, kaly |
| `chagall` | 1911–50 | vznášející se milenci, kobalt |
| `dali` | surrealismus | poušť, tající formy, berle |
| `magritte` | 1926–66 | buřinka, jablko před tváří |
| `lempicka` | art deco portréty | **riziko duplicity s `artdeco`** (ten je plakátový, Lempicka malířská) |
| `beardsley` | perokresby 1893–98 | černobílé plochy; monochrom |
| `lada` | Josef Lada | česká lidová ilustrace; jméno neznámé |
| `josef-capek` | Josef Čapek, naivní kubismus | jméno neznámé; liší se od Kubišty (naivní, ne dramatický) |

**Zvažováno a nezařazeno**: Hokusai/Utamaro (= `ukiyoe`), Renoir (≈
`impressionist`/`monet`), Caravaggio a Rubens (= `baroque`), Bosch a
Bruegel (spíš scéna než figura), Kusama (nefigurální), Emil Filla (= `kubista`),
Toyen (surrealismus bez stabilního figurálního rukopisu).

---

## 3. Experimenty v labu (před kódem)

Všechno běží stávajícím labem přes `--styles-file`, **bez změny kódu**.
Stejná reference i seed jako vlny 1–2 (baletka, seed 777), flow `repose`
(tam styl prochází nejlíp) + `txt2img` u vybraných. Laťka reakce = nejslabší
z dnešních 40 stylů (chineseink 0.302 v matici; po dumpu s baselinem si ji
lab spočítá znovu — vzít aktuální číslo, ne to z dokumentu).

### 3a. Ablace: jméno vs. popis (rozhoduje datový model)

Otázka: *nese styl jméno, popis, nebo obojí — a v které rodině?*

- 6 umělců napříč spektrem známosti: `vangogh-arles`, `mucha-poster`,
  `picasso-cubist`, `warhol`, `zrzavy`, `kubista`.
- 3 varianty textu jako **tři kandidáti s různým id** (`vangogh-arles@name`
  = jen „portrait painting by Vincent van Gogh", `@desc` = blok bez jména,
  `@both` = plný `block`). Zvláštní JSON `artists-ablation.json` odvozený
  z `artists.json` (skript nebo ručně, 18 položek).
- Modely: jeden za každý dialekt + Pony zvlášť: `juggernaut-xl` (clip),
  `illustrious-xl` a `noobai-xl` (booru s artist tagy), `pony` (booru,
  artist-blind), `flux-manga` (t5). U Illustrious/NoobAI navíc kandidát
  `@tag` = booru blok + Danbooru `(style)` tag, kde tag existuje (Mucha,
  Van Gogh, Klimt, Picasso, Warhol — ověřit na Danbooru wiki).
- Čteme: reakce vůči baselinu a **pohled** (převzal rukopis, nebo jen
  přebarvil?). Očekávání, které se má potvrdit nebo vyvrátit:
  clip → `@name` sám stačí u světových jmen, u Čechů nic;
  pony → `@name` ≈ baseline, `@desc` ≈ `@both`;
  illustrious → `@desc` nese, `@tag` případně přidá;
  flux → `@both`/prose, `@name` slabé.

Výstup rozhodne, zda datový model potřebuje tři pole (`block/booru/prose`),
nebo stačí dvě (clip vs. „bez jména"), a zda má `booruArtist` vůbec vzniknout.
**Neimplementovat dialekty dřív, než tohle proběhne** — jinak se ponese
komplexita, kterou nikdo nezměřil.

### 3b. Kandidátský běh (rozhoduje o zařazení)

- Všech 54 kandidátů, `artists.json`, po implementaci dialektů (krok 4)
  s texty per rodina; do té doby CLIP `block` všude — je to konzervativní
  horní odhad toho, co pak booru/prose zlepší.
- Modely jako ve vlně 2 (`juggernaut-xl`, `illustrious-xl`, `animagine-xl`)
  + `pony` + `flux-manga`, tj. jeden zástupce každé rodiny.
- Kritéria zařazení stejná jako ve vlně 2: (1) reakce nad laťkou aspoň u
  jednoho modelu, (2) pohledem: skutečné převzetí, ne přebarvená výchozí
  scéna, (3) není duplicita existujícího stylu. Pro dvojice s vyznačeným
  rizikem (`monet`×`impressionist`, `mucha-poster`×`artnouveau`,
  `klimt-golden`×`secession`, `rembrandt`×`baroque`, `lempicka`×`artdeco`,
  `vangogh-saintremy`×`vangogh-arles`) postavit dvojice vedle sebe a
  rozhodnout explicitně; když je nový styl lepší verze starého, **starý id
  zůstává** (persistuje se na uzlech), jen se přepíše jeho `block` — jako se
  přepisují `styleNote`.
- Monochromní kandidáti (`davinci-chalk`, `goya-caprichos`, `beardsley`) —
  barevná metrika u nich lže oběma směry (viz vlna 2), rozhoduje jen pohled.
- `degas` a druhý námět: jednou navíc s `--subject "a man reading at a
  table"` (bez tanečnice), ať se ověří, že styl nesedí jen na baletku.

### 3c. Zápis

Doplnit `docs/style-matrix.md` o sekci „Třetí vlna — umělci" ve stejném
formátu: tabulka *přidáno / zahozeno-barevný posun / zahozeno-duplicita*
s důvody, výsledky ablace 3a jako samostatná tabulka (dialekt × varianta),
odkaz na prohlížecí artefakt.

---

## 4. Implementace (po 3a)

### 4.1 Model stylu — `lib/models/style_preset.dart`

```dart
enum PromptDialect { clip, booru, t5 }

class StylePreset {
  const StylePreset({
    required this.id, required this.label, required this.block,
    this.booru, this.prose, this.booruArtist,   // podle výsledku 3a
    this.artist, this.period,                    // jen pro UI/grouping
  });
  /// Text pro daný dialekt; chybějící varianta padá na [block], takže
  /// dnešních 40 kulturních stylů se nemění a chová se jako dřív.
  String blockFor(PromptDialect d) => switch (d) {
    PromptDialect.booru => booru ?? block,
    PromptDialect.t5 => prose ?? block,
    _ => block,
  };
}

String applyStyle(String prompt, String? styleId,
    {PromptDialect dialect = PromptDialect.clip});
String applyStylePreset(String prompt, StylePreset? style,
    {PromptDialect dialect = PromptDialect.clip});
```

- `artist`/`period` jsou volitelné; kulturní styly je nemají. Slouží
  k sekci v pickeru a k labelu, ne k promptu.
- `id` zůstává jediná persistovaná věc (`GenNode.styleId`). Text je nově
  odvozený z **(styleId, modelId)** — obojí na uzlu je, takže `retry()` i
  export do galerie zůstávají deterministické. Žádné nové pole na uzlu.

### 4.2 Dialekt na modelu — `lib/models/image_model.dart`

`ImageModelSpec.promptDialect` jako **explicitní** pole (vzor `supportsPose`,
ne odvozené z `loraFamily`: `animagine-xl` má `loraFamily: sdxl`, ale
prompty čte booru). Mapování:

| dialekt | modely |
|---|---|
| clip | juggernaut-xl, juggernaut-xl-lightning, sd15 |
| booru | pony, atomix-pony-anime, illustrious-xl, noobai-xl, wai-illustrious, animagine-xl |
| t5 | flux-schnell, flux-kontext, flux-manga, flux-fill |

Pokud 3a ukáže, že `booruArtist` má smysl jen u Illustrious linie, gate je
`loraFamily == LoraFamily.illustrious` (Pony ho nesmí dostat).

### 4.3 Provider — `lib/providers/image_studio_provider.dart`

Šest volání `applyStyle(...)` (řádky ~981, 1068, 1248, 1426, 1456, 1506)
dostane `dialect:` z aktuálního specu; u `retry()` z modelu, na kterém retry
běží (tak se to už dělá u zbytku snapshotu). Inpaint styl nadále neaplikuje.

### 4.4 Lab

- `tools/lab/dump.dart`: parser `--styles-file` čte i `booru`/`prose`/
  `booruArtist`/`artist`/`period`; `applyStylePreset` dostává dialekt
  z `m.promptDialect` (styl je teď per buňka, ne per řádek). Do manifestu
  buňky přidat `styleText` (skutečně odeslaný blok), ať tooltip v tabulce
  ukazuje, co model opravdu dostal — jinak se u booru/t5 buněk nedá poznat,
  proč se liší.
- `tools/lab/static/app.js`: tooltip chipu stylu z `styleText` buňky;
  chipy stylů rozdělit do dvou řad („kultury a epochy" / „umělci") — 94 chipů
  v jedné řadě je nepoužitelných.
- Volitelná osa sweepu `param.styleDialect=clip|booru|t5` — zapojí se přes
  existující `param.*` mechanismus v `dump_spec.dart` (znovu volá builder
  s jiným textem). Umožní 3a opakovat kdykoli bez ručně psaných id-variant.

### 4.5 UI — `_StyleChip` v `image_studio_screen.dart`

- Sheet má dnes plochý `ListView.builder` nad `kStylePresets`; s ~90 položkami
  přidat **sekce** (hlavička „Kultury a epochy" / „Umělci") — jedna zploštělá
  lista položek `{header | preset}`, žádný nový widget strom.
- U umělců label ve tvaru `Autor — období` (label z JSON), subtitle místo
  `block` ukázat `period` + zkrácený `block` (u booru modelu by uživatel
  viděl tagovou variantu, což mate; ukazovat vždy clip `block`, je čitelný).
- Vyhledávací pole nahoře (filtr podle labelu/autora) — na 90 položek nutné.
- Text pod nadpisem doplnit: „U anime modelů se styl posílá jako tagy, u FLUX
  jako věta" — jediná věta, ať uživatel ví, proč se stejný styl chová jinak.

### 4.6 Testy

- `test/style_preset_test.dart`: počet 40 → N (po vlně 3), nové id v
  `containsAll`, zahozené v `isNot(contains)` s důvodem; test, že
  `blockFor` padá na `block` u stylu bez variant; test, že žádná `booru`
  varianta neobsahuje ` by ` ani jméno z `artist` (Pony ho nesmí dostat);
  test, že `applyStyle` s `t5` použije `prose`.
- `test/image_model_test.dart`: každý model má `promptDialect`; Pony linie
  nikdy nedostane `booruArtist`.
- `test/dump_spec_test.dart`: sweep `param.styleDialect`, pokud se přidá.
- `tools/lab/lab_test.go`: kandidátský JSON s rozšířenými klíči projde
  plánem (klíče navíc nesmí shodit dump).

### 4.7 Dokumentace

- `CLAUDE.md`, odstavec **Styly**: 40 → N, tři dialekty a kde se rozhoduje
  (`promptDialect` na modelu, `blockFor` na stylu), a že text je odvozený
  z `(styleId, modelId)`.
- `docs/style-matrix.md`: sekce třetí vlny (3c).
- `tools/lab/README.md`: rozšířený formát `--styles-file`, `styleText`
  v manifestu, případná osa `param.styleDialect`.

---

## 5. Pořadí práce a odhad

1. **Ablace 3a** — JSON s 18–24 kandidáty, 5 modelů, repose: ~120 buněk,
   ~1 h GPU. Bez kódu.
2. Rozhodnutí o datovém modelu (tři pole / dvě / `booruArtist` ano-ne).
3. Kód 4.1–4.4 + testy (dialekt v modelu, `blockFor`, provider, lab). Malý
   PR; kulturní styly se nemění, takže bez regrese v chování.
4. **Kandidátský běh 3b** — 54 stylů × 5 modelů × repose + baseline: ~280
   buněk, ~2–3 h GPU; `degas` navíc na druhém námětu. Prohlédnout, rozhodnout
   dvojice s rizikem duplicity.
5. Zápis do `kStylePresets` jen toho, co prošlo; UI 4.5; dokumentace 4.7.
   Druhý PR.

Co je v plánu **odhad, ne měření**, a má se po 3a/3b přepsat: mapování
dialektů na chování jmen (tabulka v §1), užitečnost `booruArtist`, a
všechny konkrétní texty v `artists.json` — jsou to první návrhy, které má
lab zkorigovat, ne finální bloky.
