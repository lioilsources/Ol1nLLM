# Stylová matice — 10 modelů × 25 stylů × 2 flow

Měření z 2026-08-25 na `comfyui.ol1n.com`: 600 renderů, stejný seed (777),
jedna společná referenční fotka (baletka na špičce, druhá noha u hlavy,
832×1216, juggernaut-xl). Prompt = subjekt + blok stylu z `kStylePresets`.
Prohlížecí stránka se všemi obrázky:
<https://claude.ai/code/artifact/212a2997-0722-473a-8a0f-dd1c4cee9025>

## Archy v repu

Kontaktní kopie běhů, na kterých verdikty níž stojí, jsou uložené přímo tady:
**[`docs/sheets/index.html`](sheets/index.html)**. Rámečky jsou v souborech
zapečené (WebP data URI), takže archy fungují i po smazání `build/lab/`, bez
sítě a bez klientů — na rozdíl od odkazů na artifacty výš, které přežijí jen
dokud je účet dostupný. Sestavuje je `tools/lab/sheets.py` z doběhlého běhu;
seznam vln je v něm konstanta `WAVES`.

Pokryté jsou běhy, které tenhle dokument jmenuje adresářem — vlny 3, 4 a 5.
Vlny 1–2 se skládaly z víc běhů (600 renderů je nad stropem 400 buněk na běh)
a text je adresářem nejmenuje, takže je archy nepokrývají.

Vlna 6 je výjimka z `tools/lab/sheets.py` — kombinuje výstup tsumiki-bench
(`flux-dev` restyle, na SPARKu) s výstupem Ol1nLLM labu (`flux-schnell`,
img2img, repose), tedy dva různé formáty běhu, které `WAVES` konstanta
nezvládne. Archy jsou postavené ad-hoc skripty (`merge_sheet.py`,
`lab_sheet.py` v `tools/lab/`, po ruce, ne v `WAVES`), ale platí pro ně totéž:
zapečené rámečky, fungují bez sítě a bez `build/lab/`.

## Metriky

- **refSim** — korelace šedotónového náhledu s referencí. V img2img měří únik
  zdroje, v repose spíš *kompoziční invenci* (vysoká = model nic nevymyslel
  a vykreslil tutéž postavu na prázdném pozadí).
- **rozptyl stylů** — průměrná kosinová vzdálenost barevných histogramů mezi
  25 výstupy jednoho modelu. Nízká = model blok stylu ignoruje.

| model | refSim repose | refSim img2img | rozptyl repose | rozptyl img2img |
|---|---|---|---|---|
| pony | 0.813 | 0.956 | 0.607 | **0.011** |
| noobai-xl | 0.383 | 0.926 | 0.581 | 0.056 |
| animagine-xl | 0.454 | 0.904 | 0.710 | 0.098 |
| illustrious-xl | 0.508 | 0.919 | 0.665 | 0.106 |
| wai-illustrious | 0.165 | 0.834 | 0.415 | 0.175 |
| juggernaut-xl | 0.526 | 0.932 | 0.696 | 0.230 |
| atomix-pony-anime | 0.319 | 0.835 | 0.593 | 0.279 |
| juggernaut-xl-lightning | 0.526 | 0.921 | 0.674 | 0.421 |
| flux-manga | — | 0.421 | — | 0.596 |
| sd15 | — | 0.941 | — | **0.005** |

## Závěry, které se promítly do kódu

1. **img2img při presetovém denoise (~0.72) styl skoro nepustí** — rozptyl je
   5–50× nižší než v repose. Proto `_EditStrengthChip` a
   `ComfyUIService.setEditDenoise()`: „silná" = `kStyleEditDenoise` 0.9, kde
   styl projde a pózu dál drží auto-depth ControlNet (ověřeno end-to-end).
2. **Každý model má „výchozí scénu"**, do které stáhne všechno, co neumí —
   pony přemalovanou fotku, illustrious dekorativní rám, animagine zlaté
   protisvětlo, juggernaut fotku před tematickou stěnou. To je pro výběr
   podstatnější než výčet schopností, proto `ImageModelSpec.styleNote`.
3. **„img2img" jsou tři různé mechanismy**: SDXL (VAEEncode + 0.72 +
   auto-depth), sd15 (bez depth) a flux-manga (**FLUX Kontext, denoise 1.0**)
   — poslední jako jediný pustí styl, ale pózu si přeskládá.
4. **Snížení `_reposeDepthStrength` na 0.5 je kompromis, ne vylepšení**:
   u illustrious se rozdýchají ploché styly (ukiyo-e), ale sytým vyblednou
   palety; juggernaut nereaguje, pony jde opačně. Hodnota **zůstává 0.75**.

## Co projde napříč modely

Spolehlivě styly s jasným médiem a plochou — čínská tuš, ukiyo-e, Art Nouveau,
egyptská stěna, indická a perská miniatura, aboriginal. Nejhůř popisy, které
znamenají hlavně „kamenný reliéf v zemitých tónech" (asyrský, mezopotámský,
hebrejský, předislámský arabský) — u většiny modelů z nich je jen béžová stěna.

## Druhá vlna stylů (2026-08-25)

24 kandidátů, 3 modely s nejširším rozsahem (juggernaut-xl, illustrious-xl,
animagine-xl), repose, stejný seed i reference — plus **nezastylovaný baseline**
pro každý model. Kritérium „reaguje na to aspoň jeden model" = vzdálenost
barevného histogramu od baseline téhož modelu; laťku určil **nejslabší
z 25 stávajících stylů** (chineseink, 0.302), ne odhad.

Laťku překonalo všech 24, ale metrika měří barvu, ne převzetí stylu — proto
rozhodl ještě pohled na výsledky:

| verdikt | styly | důvod |
|---|---|---|
| **přidáno (15)** | byzantine, illumination, stainedglass, impressionist, woodcut, artdeco, constructivist, secession, minoan, thangka, rinpa, dunhuang, minhwa, papercut, huichol | model styl skutečně převzal |
| zahozeno — jen barevný posun (4) | ethiopian, wayang, amate, suprematism | vysoké číslo, ale výsledkem je výchozí scéna modelu s jiným nádechem; suprematismus se navíc pere s figurou drženou depth mapou |
| zahozeno — duplicita (5) | sumie (= chineseink), mughal (= persian), prerafael (≈ greek), adire (≈ assyrian), inuit (≈ ukiyoe) | přidalo by synonymum |

Poznámka k metrice duplicit: je barevná, takže u plochých černobílých stylů
falešně poplašila — `illumination`, `woodcut` a `huichol` vyšly „blízko"
ukiyo-e resp. čínské tuši, ale vizuálně jsou zřetelně jiné, a proto zůstaly.

## Třetí vlna — umělci (2026-09-10)

Kandidáti v `tools/lab/candidates/artists.json` (54 stylů od 42 autorů), plán
v `docs/plan-artist-styles.md`. Reference, seed 777 i subjekt jsou tytéž jako
ve vlnách 1–2, flow repose. Prohlížecí stránka s ablací i všemi kandidáty:
<https://claude.ai/code/artifact/ff39d9f9-21a3-4152-9a4d-295331357638>.
Archy v repu: [ablace CLIP+T5](sheets/wave3-ablace-clip-t5.html),
[ablace booru](sheets/wave3-ablace-booru.html),
[kandidáti](sheets/wave3-kandidati-umelci.html),
[Degas na druhém námětu](sheets/wave3-degas-druhy-namet.html).

### Ablace: jméno, nebo popis?

Šest autorů napříč známostí (`vangogh-arles`, `mucha-poster`, `picasso-cubist`,
`warhol`, `zrzavy`, `kubista`), text stylu v šesti variantách: `@name` jen
„artwork by Jméno", `@desc` blok bez jména, `@both` celý blok, `@booru`
danbooru tagy bez jména, `@tag` tagy + danbooru `(style)` tag umělce (existuje
jen u Van Gogha se 103 posty a u Picassa s 12), `@prose` věta pro T5. Každá
rodina modelů dostala jen varianty, které pro ni dávají smysl — 131 buněk
v `build/lab/20260910-104000` (clip + t5) a `-104001` (booru).

| model (dialekt) | jen jméno | popis bez / se jménem | tagy | tag umělce | věta |
|---|---|---|---|---|---|
| juggernaut-xl (clip) | z fotky udělá obecnou malbu, konkrétní styl nepřijde (Warhol = černobílá kresba); reakce až 0.995 je jen změna média | nese styl; se jménem stejně nebo silněji (Picasso) | — | — | ≈ blok, Picasso slabší |
| flux-manga (t5) | u všech šesti tatáž malířská zeď | nese (Mucha plakát, Warhol mřížka tváří, Kubišta fasety) | — | — | ≈ blok; Picasso slabší, Warhol o chlup lepší |
| illustrious-xl (booru) | ≈ baseline | Mucha, Warhol; Picasso, Zrzavý, Kubišta ne | **lepší** — Picasso lámané plochy, Zrzavý opar, Kubišta expresivní malba | nic nepřidá | — |
| noobai-xl (booru) | ≈ baseline | slabé, spolehlivě jen Mucha | **jasně lepší** — Warhol pop-art plakát, Van Gogh žlutomodrá malba | nic; u Picassa vrátí obraz k baseline | — |
| pony (booru) | = baseline (jména umělců měl v tréninku zahashovaná) | Mucha; zbytek slabě | stejné nebo lepší (malířštější Picasso, Zrzavý) | ≈ tagy | — |

**Rozhodnutí o datovém modelu: dvě pole, ne tři.** `block` (volná fráze) čte
CLIP i T5 — věta nic nepřidala (měřeno na flux-manga; NIM modely lab tehdy
neuměl spustit, od vlny 5 už ano), takže pole `prose` nevzniklo. `booru` (tagy bez jména) dostanou
modely s `PromptDialect.booru`: všechny tři anime modely z tagů převzaly styl
lépe nebo stejně jako z popisu. `booruArtist` nevzniklo — tag umělce nepomohl
nikde a u NoobAI jednou škodil; laťka plánu „pod ~200 posty model tag nezná"
by navíc vyřadila všechny kandidáty (Muchův tag neexistuje, Warhol má jen
copyright tag s 11 posty). Jméno v `block` zůstává: u CLIPu pomohlo (Picasso)
a jinde neuškodilo.

Čeští autoři: jméno nedělá nic na žádném modelu a popis je přiblíží jen
částečně — Kubištovy fasety převezme FLUX, Zrzavý je na každém modelu
nejslabší ze šesti.

### Kandidátský běh

Všech 54 kandidátů, každý model s textem pro svůj dialekt (tagy pro
illustrious-xl, animagine-xl a pony; blok pro juggernaut-xl a flux-manga), plus
šest stylů z registru jako kontroly — pět, se kterými by kandidát mohl být
duplicitní, a čínská tuš. 305 buněk v `build/lab/20260910-133000`, reference,
seed i subjekt jako výše. Laťka = nejlepší reakce nejslabší kontroly:
**0.747 (secession)**.

Metrika opět propustila skoro všechno, a u stylů na bílém nebo zasněženém
pozadí naopak dala nízká čísla, přestože styl viditelně prošel (Schiele,
Beardsley, Lada, Haring a Lichtenstein na juggernautu). Seurat vyšel pod
laťkou, ale pointilistické tečky jsou na juggernautu i fluxu jednoznačné.
Rozhodoval pohled.

| verdikt | styly | důvod |
|---|---|---|
| **přidáno (42)** | davinci, davinci-chalk, picasso-blue, picasso-rose, picasso-cubist, basquiat, hockney-pool, monet, kahlo, goya-black, goya-caprichos, kandinsky-early, vangogh-arles, vangogh-saintremy, lautrec-poster, lautrec-cabaret, mucha-slav-epic, kubista, schiele, klimt-golden, vermeer, botticelli, elgreco, munch, matisse-fauve, matisse-cutout, gauguin, cezanne, seurat, hopper, warhol, lichtenstein, haring, bacon, rivera, chagall, dali, magritte, lempicka, beardsley, lada, josef-capek | aspoň jeden model styl skutečně převzal |
| **přepsáno** | artnouveau ← text `mucha-poster` | na juggernautu byl dosavadní blok bledá tapeta (reakce 0.458), Muchův plakát se svatozáří (0.934); na ostatních modelech stejné. Id zůstává — persistuje se na uzlech. **S blokem přišla i Muchova `booru` varianta**, takže artnouveau má tagy už od téhle vlny — proto ho vlna 4 neměřila a proto jich je v registru o jeden víc, než kolik jich vlna 4 zapsala |
| zahozeno — jen barva nebo kulisa (9) | hockney-joiner, michelangelo, modigliani, zrzavy, picasso-neoclassical, vangogh-nuenen, freud, rockwell, goya-tapestry | koláž z polaroidů nevznikne; pastelový rám místo fresky; dlouhý krk ani prázdné oči nepřijdou, jen okrová stěna; jen růžovomodrý opar; jen pláž; tmavá tónová malba ≈ baroko; jen ateliér s matrací; jen teplá paleta; těsně pod laťkou a jen pastelová kulisa |
| zahozeno — obsah místo stylu (1) | degas | blok vnutí baletku: na druhém námětu („a man reading at a table", txt2img, `build/lab/20260910-133001`) oblékl čtenáři tutu, nebo ho nahradil baletkami, na všech pěti modelech |
| zahozeno — duplicita (2) | rembrandt, mucha-poster | rembrandt = baroque (na animagine a fluxu prakticky tentýž obraz); mucha-poster přepsal artnouveau |

Dvojice s rizikem duplicity, které zůstaly obě, protože vypadají jinak:
klimt-golden × secession (plátkové zlato vs. geometrické čtvercové rámy),
lempicka × artdeco (mrakodrapy a kovová drapérie vs. zlatočerné pruhy),
monet × impressionist (louka a obloha, na juggernautu slunečník),
vangogh-saintremy × vangogh-arles (víry a cypřiš vs. šrafura).

Čeští autoři: přidáni Kubišta, Lada, Josef Čapek a Muchova Slovanská epopej.
Zrzavý neprošel — na žádném z pěti modelů z něj nezbylo víc než opar.

**Známé omezení:** bloky umělců nesou i rekvizity a vedlejší postavy (Kahlo
opici a květy ve vlasech, Chagall milence nad vesnicí, Kandinskij jezdce,
Muchův plakát „woman framed by a circular halo") a kromě Degase se měřily jen
na baletce v „zachovej pózu", kde postavu drží hloubková mapa a rekvizity
skončí v kostýmu a pozadí. V txt2img na jiném námětu můžou obsah přepsat —
Degas je krajní případ. Až se styly začnou používat mimo repose, ověřit je
druhým námětem.

## Čtvrtá vlna — booru text pro kulturní styly (2026-09-15)

Kulturní styly (39 z registru, tehdy bez tagové varianty) měřeny v labu
proti 4 anime SDXL modelům (NoobAI, WAI, Animagine, Illustrious), `param.styleDialect=natural|booru`,
repose, neutrální předloha (oblečená postava v pokoji, vygenerovaná labem —
dřívější vlny běžely na fotce v plavkách, což mohlo zkreslovat reakci
u stylů, které mění oblečení). Kandidátské tagy: `tools/lab/candidates/cultural-booru.json`,
odvozené z bloku, motivy měnící obsah (vousy, roucha, tygr, „x-ray“,
anatomie) vynechané. Seed 777, jeden běh (320 buněk), verdikt z pohledu na
archy — metrika (barevná reakce vůči baseline) jen řadí a u vzorových stylů
podhodnotila skutečný rozdíl (viz egyptian níž).

| dialekt | NoobAI | WAI | Animagine | Illustrious |
|---|---|---|---|---|
| věta | 0.66 | 0.39 | 0.69 | 0.69 |
| tagy | **0.86** | **0.76** | **0.82** | **0.93** |

Arch: [booru tagy pro kulturní styly](sheets/wave4-booru-kultury.html).

Pozor na součet: tahle vlna zapsala **19**, ale v registru má `booru` **20**
kulturních stylů — dvacátý je `artnouveau`, který tagy dostal už ve vlně 3
s přepsaným blokem, a proto tady mezi měřenými 39 není. Kdo počítá registr
proti tomuhle seznamu, musí ho připočíst (ověřeno v `style_preset.dart`:
42 umělců s tagy, 20 kultur s tagy, 20 kultur bez).

**Do registru (19, `StylePreset.booru`):** aboriginal, polynesian, maasai,
hebrew, indian, secession, aztec, rinpa, mesopotamian, constructivist,
huichol, arabian, artdeco, ashanti, papercut, burmese, himba, byzantine,
stainedglass — tagy prošly na 3–4 modelech ze 4 a arch potvrdil viditelný
rozdíl (patterny, ornament, sytost barev, které věta nedala — aboriginal
tečkovaný vzor, aztec geometrie a červená, secession plátkové zlato,
stainedglass sytá barevná okna). U slabších případů (arabian, himba, hebrew,
huichol) je rozdíl menší, ale směr shodný na všech modelech.

**Neopraveno — chyba je v popisu, ne v dialektu (2):** `dunhuang`, `romanfresco` —
oba dialekty dají prakticky totéž (plochý pastelový oděv), styl nepřijde ani
jednou cestou. Kandidát na přepsání bloku, ne na booru text.

**Smíšené, ponecháno beze změny (18):** assyrian, ledger, maya, inca,
thangka, dogon, minoan, egyptian, minhwa, greek, filipino, baroque, woodcut,
persian, impressionist, chineseink, ukiyoe, illumination — na některém
modelu tagy pomohly, na jiném uškodily nebo nic neudělaly. `egyptian`
je zvláštní případ: metrika vyšla skoro na nule (0.00–0.06) u tří modelů, ale
arch ukazuje jasné hieroglyfické vzory na rukávu a lemu, které věta nedala —
barevná metrika lokální detail podhodnotí, když nezmění celkovou paletu.
Kandidát na ruční přidání při příští revizi, ne na automatický export.
Jeden seed nerozliší efekt od šumu tam, kde je rozptyl mezi modely (viz #0,
`juggernaut-xl-lightning` 0.13–0.27, `illustrious-xl` 0.33–0.40) srovnatelný
s naměřeným rozdílem — než se tahle skupina zapíše, chce to druhý seed.

## Pátá vlna — pony × atomix-pony-anime, flux-schnell (2026-09-17)

Dva běhy nad stejnou dvojicí námětů (baletka na špičce, muž u stolu), seed 777,
txt2img, 82 stylů z registru + baseline.

**`pony` vs `atomix-pony-anime`** (obě Pony linie, oba čtou booru tagy):
rozptyl `pony` 0.646/0.589 (dva náměty), `atomix-pony-anime` 0.555/0.497 —
`pony` má vyšší číslo, ale arch ukazuje proč: u části bloků ztratí i námět
(himba a vangogh-arles dají antropomorfní zvíře, maasai leopardí vzor) a
takový rozpad je barevně nejdál od baseline, takže ho metrika odmění. Ani
jeden model nevyrobí **médium** — styl dorazí jako design postavy a kulisa,
ne jako materiál obrazu. Oba modely mají dno u `baroque`, `inca`,
`romanfresco`. Arch: [pony × atomix](sheets/wave5-pony-vs-atomix.html).

**`flux-schnell`** (první běh mimo ComfyUI, přes gen-queue, první v txt2img):
barevná metrika tenhle běh neseřadila — `inca` 0.276 a `elgreco` 0.167 leží
dole a přitom styl jasně prošel, zatímco 66 z 82 stylů leží nad 0.94 a
navzájem se nerozliší. Řazení proto abecední, rozhoduje pohled na arch.
Arch: [flux-schnell, 82 stylů](sheets/wave5-schnell.html).

## Šestá vlna — schnell × flux-dev, img2img/repose napříč 7 modely (2026-09-19–20)

Cíl: rozšířit srovnání `flux-schnell` (rychlý, distillovaný, jen txt2img) proti
`flux-dev`/`flux-manga` (MangaPrompts tomu říká „flux-dev", je to tentýž
checkpoint co Ol1nLLM `flux-manga`) na 42 malířů (stejný registr, bajtově
ověřeno shodný `block` text s MangaPrompts `painters.json` — davinci, lada,
josef-capek, vangogh-arles, matisse-fauve, mucha-slav-epic beze změny),
a doplnit chybějící osy z otázky „co dál — repose, nebo img2img": obojí.

**Mechanika, ne jen dvě čísla.** `flux-schnell` je čistý txt2img z textu (žádná
fotka, žádná identita/póza), zatímco `flux-dev` běžel přes tsumiki-bench
`restyle` graf — a ten je (ověřeno v `sdxl_restyle.api.json`/`flux_restyle.api.json`)
plný denoise 1.0 z `EmptyLatentImage`, veden depth ControlNetem a
InstantID/PuLID identitou ze zdroje. To je appkově **repose**, ne img2img —
proto vlna 6 vedle toho dodala skutečný img2img (VAEEncode + parciální
denoise), aby byla trojice txt2img/repose/img2img konečně kompletní.
Arch: [schnell × flux-dev](sheets/wave6-schnell-vs-fluxdev.html).

**Nechtěná nahota.** Přes explicitní `fully clothed person` v promptu dal
`flux-dev` u `davinci` a `botticelli` nahou postavu (renesanční/mytologická
konvence přebila instrukci); zbytek ze 42 stylů byl v pořádku. V archu
záměrně ponecháno s poznámkou, ne skryto ani přegenerováno — je to stejný typ
nálezu jako dřívější „degas vnutí baletku", ne důvod běh zahodit.

**Img2img vs repose — 7 modelů** (Illustrious, NoobAI, WAI, Animagine,
Juggernaut, Juggernaut Lightning, flux-manga), 42 malířů, oba náměty, seed
777. Img2img na appkovém „auto/silná" denoise (kde má styl podle dřívějšího
zjištění vůbec šanci projít). Rozptyl (barva vůči baseline, průměr obou
námětů):

| model | repose | img2img | poměr |
|---|---|---|---|
| noobai-xl | 0.838 | 0.383 | 2,2× |
| animagine-xl | 0.805 | 0.385 | 2,1× |
| wai-illustrious | 0.823 | 0.434 | 1,9× |
| illustrious-xl | 0.658 | 0.232 | 2,8× |
| juggernaut-xl | 0.740 | 0.561 | 1,3× |
| juggernaut-xl-lightning | 0.729 | 0.527 | 1,4× |
| flux-manga | 0.528 | 0.475 | 1,1× |

**Repose nechá projít víc stylu než img2img na každém jediném ze 7 modelů** —
i na appkovém „silná" nastavení (0.9), ne jen na starším měřeném presetu
(~0.72). Nejvýraznější rozdíl `illustrious-xl` (2,8×), nejmenší `flux-manga`
(1,1× — jeho vlastní img2img mechanismus je taky Kontext-based, blíž
plnému denoise než SDXL VAEEncode, proto rozdíl skoro mizí). Vizuálně
totéž: `illustrious-xl` × van Gogh v repose dá viditelný impasto a sytou
teplou paletu, v img2img na 0.9 zůstává jemný pastelový filtr nad fotkou.
Archy: [img2img](sheets/wave6-img2img-7models.html),
[repose](sheets/wave6-repose-7models.html).

**Co dál.** Repose i img2img teď mají baseline na tomhle datasetu — chybí
sweep denoise (0.5 vs 0.9) přímo proti sobě na jednom běhu, aby šlo číst
křivku, ne jen dva krajní body z různých vln.
