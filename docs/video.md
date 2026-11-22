# Video (`video-stack/serve.py`, `llm.ol1n.com/v1/video/*`)

Přesunuto z `CLAUDE.md`.


Jeden job server na SPARKu pro dvě věci: krátký klip z obrázku („Rozhýbat“
v Image Studiu) a minutový příběh (StoryStudio). Render trvá minuty až
hodinu, server drží frontu a stav jobů v `jobs/<id>.json`, appka jen polluje
a stahuje mp4 (kontrola `mp4LooksComplete`). `VIDEO_URL` přepne server
(výchozí `https://llm.ol1n.com`, jen `StoryService`; `VideoService` má URL
pevnou). Kontrakt API je v README video-stacku.

## Rozhýbat (Image Studio)

Akce na dlaždici otevře `_AnimateSheet`: nahoře **vlastní pohyb** (text
+ délka 5/10/15 s), pod ním scény ze serveru (`scenes/*.json`). Vlastní
pohyb jde jako `POST /jobs {prompt, beats}` místo `{scene}`: server text
přes LLM gateway (alias `shop`, few-shot) přepíše do anglického promptu
pohybu ve tvaru, který Wan drží (oblouk s koncovou pózou, bez kamery),
a když LLM neběží nebo odpoví česky, pošle text tak, jak je — umT5 ve Wanu
je vícejazyčný. Nabídka se ukáže, jen když katalog `GET /scenes` vrátí
`custom` (meze: max beatů, délka promptu, s a min na beat) — starší server
ho nemá a appka pak ukáže jen scény. Stav `ImageStudioState.videoCustom` je
app-scoped jako `availableScenes`, přenáší se při každé přestavbě stavu.
Uzel: `isVideo`, `sceneId` null, `prompt` = text uživatele,
`videoBeats` = délka; retry pošle totéž znovu.

## StoryStudio

Ikona klapky v Chatu. Katalog příběhů `GET /stories` (scénář, role s českým
popisem vzhledu, odhad minut), uživatel obsadí role vlastními obrázky
(Fotky/Soubory, 1536 px) — co nepošle, doplní server z výchozích postav
(`default` u role). Jeden projekt = jeden job:

- **Review** (výchozí zapnuto): job se po nakreslení 12 keyframů zastaví ve
  stavu `review`. Appka ukáže mřížku keyframů (JPEG přes
  `…/keyframes/NN`, cache v provideru podle `keyframesVersion`), klepnutí
  označí záběr k překreslení (nový seed), tužka upraví jeho anglický popis.
  `POST /approve {}` = animovat, `{redo, keyframe}` = překreslit a znovu
  review. Bez review jede job rovnou do konce.
- **Průběh** `phase`: keyframes → compile → render (beat/beats) → assemble
  → rife → voice → music → mix; `storyProgressFraction` váží render nejvíc.
- **Výsledek**: hlavní mp4 s vypravěčem a hudbou se stáhne hned, varianty
  `sub` (vypálené titulky) a `16x9` až na klepnutí.
- **Chyba**: `serverFailed` rozhoduje o „Zkusit znovu“ — selhal-li job na
  serveru (nebo se neodeslal), jde nový job se stejným obsazením; selhalo-li
  stažení nebo síť, appka se jen znovu napojí.
- **Persistence**: Hive box `story_projects`, klíč `all`; obrázky postav
  a videa v `applicationSupport/story_studio/` (relativní jména,
  `StoryFiles.baseDir`). Resume při startu, návratu do popředí a 5 s po
  výpadku sítě, i pro projekty v review (jeden poll ověří, že pořád čekají).
- Smazání projektu v telefonu job na serveru nezastaví — server cancel nemá.
