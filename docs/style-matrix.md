# Stylová matice — 10 modelů × 25 stylů × 2 flow

Měření z 2026-08-25 na `comfyui.ol1n.com`: 600 renderů, stejný seed (777),
jedna společná referenční fotka (baletka na špičce, druhá noha u hlavy,
832×1216, juggernaut-xl). Prompt = subjekt + blok stylu z `kStylePresets`.
Prohlížecí stránka se všemi obrázky:
<https://claude.ai/code/artifact/212a2997-0722-473a-8a0f-dd1c4cee9025>

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
<https://claude.ai/code/artifact/ff39d9f9-21a3-4152-9a4d-295331357638>

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
CLIP i T5 — věta nic nepřidala (měřeno na flux-manga; NIM modely lab
nespouští), takže pole `prose` nevzniklo. `booru` (tagy bez jména) dostanou
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
| **přepsáno** | artnouveau ← text `mucha-poster` | na juggernautu byl dosavadní blok bledá tapeta (reakce 0.458), Muchův plakát se svatozáří (0.934); na ostatních modelech stejné. Id zůstává — persistuje se na uzlech |
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
