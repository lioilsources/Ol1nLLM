# Style map (`lib/stylemap/`, `tools/stylemap/`)

Přesunuto z `CLAUDE.md`.


Picker, ve kterém prst jezdí po mozaice tisíců obrázků téhož námětu v různých
stylech a nad ní se ukazuje obrázek pod prstem. Sousední buňky si jsou
stylově blízké, takže přejíždění působí jako plynulá animace. Plán je
`docs/STYLEMAP_PLAN.md`; hotové jsou milníky M1 (pipeline), M2 (režim Map),
M3 (plynulost: LPIPS, trasa, přehrávání), M4 (režimy Osy a Kolo) a M5 (VLM
tagy, fasety, hledání), zbytek — dogenerování děr, StyleSpec — je vypsaný
v `tools/stylemap/README.md`, i s tím, které kroky pipeline se po jaké změně
pouštějí znovu.

- **Pack je statický**: `map.json` (mřížka, osy, clustery, obrázky),
  `atlas.webp` (celá mapa jako jeden obrázek, buňka 32 px) a `t/<i>.webp`
  (náhled 384 px). Staví ho Python pipeline (`tools/stylemap`): levné
  vlastnosti + CLIP → UMAP → přiřazení na mřížku → vyhlazení podle LPIPS.
  Žádný backend za běhu, appka jen čte.
- **Z čeho se staví**: z jedné nebo víc sessions FINETUNE gallery
  (`make stylemap SET=… SESSIONS="<id> <id>"`, volitelně `WHERE="score=1"` —
  filtry `/api/images`), nebo z běhu labu na disku (`RUN=…`). Z galerie se
  stahují její 384px náhledy, ne originály (`FULL=1` je vynutí). Python
  `urllib` musí poslat vlastní `User-Agent` — na výchozí odpoví Cloudflare 403
  dřív, než se Access podívá na token.
- **Odkud se čte**: `STYLEMAP_URL` (výchozí
  `https://finetune.ol1n.com/stylemaps`). Galerie packy servíruje staticky
  z `<data>/stylemaps` (repo FineTuneGallery, `server/stylemaps.go`); na NAS je
  kopíruje `make stylemap-publish`. Pro vývoj `make stylemap-serve` na Macu
  a `STYLEMAP_URL=http://<ip>:8770` s `make debug`.
- **Okamžitá odezva**: pod prstem se hned kreslí výřez z atlasu (je v paměti),
  ostrý náhled se stáhne až po 90 ms klidu na buňce a přednačtou se čtyři
  sousedi. Rychlý tah přes desítky buněk tak nepustí desítky requestů.
- **Gesta**: dotyk vybírá hned (`Listener.onPointerDown` — scale gesto by
  začalo až po slopu a tap by nevybral nic), dva prsty zoomují a posouvají.
  Po pinchi se 250 ms nevybírá, jinak by poslední zvednutý prst skočil jinam.
  Geometrie zoomu je čistá třída `StyleMapView` (testy bez gest).
- **Přehrávání**: lišta mezi náhledem a mozaikou (play/pause, posuvník,
  rychlost 3/6/12 obrázků za vteřinu) jede po `StyleMapPack.route` — pořadí
  `tour` z packu (nejmenší kroky v LPIPS), u packu bez něj po Hilbertově
  křivce. Přehrávání **čeká na náhled** dalšího snímku (nejdéle 800 ms)
  a přednačítá osm snímků dopředu: na pomalé síti film zpomalí, místo aby
  ukazoval rozmazané výřezy z atlasu. Dotyk na mozaiku i posuvník přehrávání
  zastaví. Trasa po LPIPS skáče po mozaice, značka skáče s ní.
- **Na celou obrazovku** (`fullscreen.dart`, ikona na konci lišty): film
  přes celý displej, ovládání nad obrázkem (klepnutí ho schová) a **posuvník
  rychlosti** 1–24 obrázků za vteřinu. Hraje to, co je zrovna na mapě — tedy
  i výsledek filtru — a po zavření mapa pokračuje tam, kde film skončil, stejnou
  rychlostí. Mapa i přehrávač jedou na jedné třídě `StyleMapPlayback`
  (`playback.dart`), která o widgetech neví: čekání na náhled a přednačítání
  (aspoň osm snímků, při vyšší rychlosti třetinu vteřiny) jsou tak jen jednou.
- **Video**: totéž přehrávání do MP4 na výšku (TikTok/Reels) dělá
  `make stylemap-video` na Macu — rychlost, prolínačka, filtr jako v appce,
  s filtrem trasa přeplánovaná jen přes vybrané obrázky; z běhu labu i bez
  mapy styl po stylu přes všechny modely (`ORDER=style`, popisky `LABEL=1`)
  (`tools/stylemap/README.md`, „Video na výšku“). Appka video nerenderuje.
- **Režimy** (`StyleMapMode`, ikony v rohu náhledu): tytéž obrázky jinak
  rozložené. *Mapa* je mozaika. *Osy* (`pad.dart`) je bodový graf dvou
  měřených vlastností (osy se vybírají z `axes[]` packu) a prst dostane
  nejbližší obrázek — hrubou silou, pro tisíce bodů to stačí. *Barvy*
  a *Skupiny* (`wheel.dart`) jsou prstenec sektorů (převládající odstín, resp.
  cluster; šířka podle počtu, nejmíň 4 % kruhu, aby šel trefit) a uvnitř mřížka
  obrázků sektoru, ve kterém je výběr — dva kroky místo hledání šestibodové
  buňky mezi tisíci. Režim se nabídne, jen když pack má, co kreslí.
- **Filtr** (`filter.dart`, ikona pod režimy): hledání bez diakritiky a fasety
  z packu (`facets[]` — model, médium, po otagování paleta, nálada, linka,
  pozadí). Uvnitř fasety platí kterákoli hodnota, mezi fasetami všechny.
  Filtr widgetu nepřidává žádnou logiku navíc: `StyleMapPack.where()` vrátí
  tutéž mapu jen s vyhovujícími obrázky (ostatní buňky jsou díry), takže
  mozaika, trasa, přehrávání, osy i kolo se zúží samy. Vyřazené buňky se
  v mozaice ztmaví. Id modelu dostane jméno až v appce (`valueLabel`).
- **Co pick znamená, určuje volající**: widget hlásí jen výběr. V Image Studiu
  chip „Mapa“ otevře `StyleMapScreen(pick: true)` a dostane `StyleMapPick`:
  obrázek vzniklý se stylem z registru (`style` v `map.json`) nastaví chip
  stylu, fragment promptu (`tag`, např. `artist:…`) se připojí **za** text
  v poli. Model se nepřepíná, jen se ukazuje v popisku, když jich sada míchá
  víc. Pack nese id z registrů, jména jim dává až appka
  (`StyleMapScreen._label`); id, které registr už nemá, zůstane, jak je.
- `test/fixtures/stylemap_map.json` je manifest, který pipeline opravdu
  zapsala (16 obrázků, jedna buňka vyjmutá kvůli díře).
