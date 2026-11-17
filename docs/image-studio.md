# Image Studio

Přesunuto z `CLAUDE.md`.

## Image Studio — Job Queue implementace

### Společný interface (`ImageBackend`)

Každý backend implementuje:
- `generate(prompt, n, seed)` → `Stream<GenEvent>` — txt2img
- `edit(image, prompt, n, seed)` → `Stream<GenEvent>` — img2img
- `follow(jobId)` → `Stream<GenEvent>` — resume přerušeného jobu
- `interrupt()` — zrušení

`seed` vlastní provider (`_newSeed()`), ne backendy — losuje se před voláním a
ukládá na `GenNode`, takže výsledky jsou atribuovatelné/reprodukovatelné.
ComfyUI batch sdílí jeden seed (varianty = batch index); NIM posílá `seed + i`
pro i-tý sekvenční request.

**Prompt chaining (img2img)**: efektivní prompt pro `edit()` skládá provider
(`_chainedPrompt()` v `refine()`/`retry()`): **vlastní text první**, pak
prompty předků parent→root (od nejnovějšího k nejstaršímu) — dřívější tokeny
mají větší CLIP váhu, takže nová instrukce může overridnout starší kola.
Řetězí se **jen nody se stejným `modelId`** jako aktuální model (jiný styl
promptů by byl nekompatibilní). Prázdné prompty (foto rooty) a přesné
duplicity se přeskočí (duplicita drží novější pozici), join `', '`.
`GenNode.prompt` drží **jen vlastní text** — chain se přepočítává při
requestu (a je deterministicky odvoditelný ze stromu, žádné nové persistované
pole). Backendy prompt jen propouštějí, takže chaining funguje shodně pro
ComfyUI i flux-kontext.

`GenEvent` je sealed class: `GenSubmitted(jobId)` → `GenQueued(pos)` → `GenRunning(step, total)` → `GenDownloading(done, total)` → `GenComplete(images)` | `GenFailed(msg)`.

`GenInterrupted(jobId)` je **neterminální** událost: signalizuje přechodný výpadek (iOS suspend / síťový blip), kdy job na serveru dál žije. Provider nechá node ve stavu `generating`, zachová `jobId` (a uloží ho do Hive) a po krátkém backoffu se znovu napojí přes `follow()`. Viz „Resume po iOS suspenzi".

### ComfyUI (`comfyui.ol1n.com`)

**Async queue s WebSocket live progress:**

```
POST /prompt  →  prompt_id                           (sync enqueue, vrátí okamžitě)
WS   /ws?clientId=<uuid>  →  per-step events         (primary progress path)
GET  /history/{id}        →  výsledek                (polling fallback + download refs)
GET  /queue               →  pozice ve frontě         (fallback status)
GET  /view?filename=...   →  stáhnutí PNG souboru    (jeden soubor = jeden obrázek)
POST /interrupt           →  zrušení
```

Progress events z WS: `status` (queue depth), `execution_start`, `progress` (step/max = reálný krok difuse), `executing` (node=null → hotovo), `execution_error`, `execution_interrupted`.

Pokud WS selže (CF Access blokuje upgrade): fallback na HTTP polling `/history` + `/queue`.

**`clientId` je per-job, ne per-instance.** ComfyUI drží sockety ve slovníku
podle `clientId` a při druhém připojení se stejným id to staré **vyhodí**
(„reusing existing session, remove old"). Když tedy dva joby sdílely jedno id
služby, druhý job umlčel socket prvního: progress zamrzl a protože socket
zůstal otevřený bez chyby, nespadlo to ani do pollingu — node visel.
Ověřeno proti serveru (sdílené id: první socket po připojení druhého dostane
0 zpráv; různá id: dostane všech 91) i přes reálný `generate()` ×2 nad jednou
instancí služby (před opravou A zamrzlo na 9/30 kroků, po ní 30/30).
`follow()` proto WS **vůbec neotvírá** — běžící job je zaregistrovaný pod
starým id a nová socket by mlčela navždy; jde rovnou do pollingu. Navíc má
smyčka `_wsSilenceTimeout` (90 s bez jakékoli zprávy ⇒ polling), aby ticho na
socketu nikdy nezmrazilo node natrvalo.

`n > 1` řeší ComfyUI nativně přes `batch_size` / `RepeatLatentBatch` — jediný request, server vygeneruje n obrázků najednou.

**`follow(promptId)`**: přeskočí enqueue, jde rovnou do polling fallbacku (WS je ztracený po suspenzi). Výsledky na serveru přežívají restart ComfyUI? Ne — history se resetuje. TTL: neomezené do restartu serveru.

Po **3 po sobě jdoucích** chybách pollu (typicky uspání / síťový výpadek) `_pollUntilDone` vrátí `GenInterrupted(promptId)` místo tichého opakování až do 10min deadlinu — provider se pak znovu napojí.

Workflow jsou JSON assety v `assets/comfyui/`, patchované před odesláním (`__PROMPT__`, `__IMAGE__`, batch_size, seed, LoRA inject).

**Registr modelů (`lib/models/image_model.dart`)**: UI má jeden model picker
(`_ModelChip` bottom sheet); `ImageModelSpec.id` (persistuje se v session jako
`modelId`) určuje backend (`ImageBackendKind`) i ComfyUI preset. SDXL-rodina
(pony, juggernaut-xl, juggernaut-xl-lightning, illustrious-xl,
atomix-pony-anime, sd15) jede na generických template
`sdxl_txt2img/sdxl_img2img.api.json` se sentinely
`__CKPT__` / `__NEGATIVE__`; sampler/steps/cfg/rozměry patchuje `_prepare()`
z `ComfyPreset`. Flux-manga má dedikované JSONy (UNETLoader graf, hodnoty
baked-in, `ckptName == null` ⇒ sampler se nepatchuje). Positive prefix (score
tagy) se skládá v Dartu. `_LoraChip` v input baru ukazuje sílu i mimo picker
(hodnota + divergentní proužek `_LoraStrengthBar` od nuly, oranžově pro
záporné); řada chipů je horizontálně scrollovatelná, protože model + LoRA se
sílou + póza se na 375 pt nevejdou. Chip platí i pro „zachovej pózu“.
Pořadí v řadě je záměrné: model → styl → síla úpravy → póza → **LoRA
jako poslední** (používá se nejmíň, a řada scrolluje, takže co je vpravo,
je z palce nejdál).
ComfyUI URL jde přepnout přes `--dart-define=COMFYUI_URL=...`
(např. LAN `http://SPARK_HOST:8188` pro testování bez CF).

**Chipy sledují node**: `navigateTo()` po přesunu na node zavolá
`_adoptNodeSettings()` — čistá funkce `adoptableSettings()` (testovatelná bez
Hive) spočítá z metadat nodu model/LoRA/sílu/pózu a provider je nastaví, takže
překlikáním ve stromu se vrátíš do kontextu, ve kterém obrázek vznikl (a
následný refine/retry jede se stejným setupem). Vrací null = „chipy nech být"
(foto root a staré sessions nemají `modelId`, nebo model už na serveru není);
LoRA se zahodí, když ji server nemá nebo nesedí do linie modelu, póza u
modelu bez `supportsPose`. Chybějící `loraStrength` (nody před v1.5.1) padá na
`kDefaultLoraStrength`.

**Strom nodů**: děti se kreslí **nejnovější vlevo** (`kids.reversed`
v `_TreeLayout.assignPos`) — `InteractiveViewer` startuje v počátku plátna,
takže poslední kolo je vidět bez scrollování; opačné pořadí tlačilo čerstvou
větev mimo obrazovku.

**Klávesnice**: `_dismissKeyboard()` (přes `FocusManager.instance.primaryFocus`)
se volá u všeho, co zjevně není psaní — otevření kteréhokoli bottom sheetu,
klepnutí na dlaždici či node ve stromu, spuštění inpaintu/3D/repose, odeslání
promptu; mřížka i chat list mají `keyboardDismissBehavior: onDrag`. Klepnutí
mimo pole řeší `GestureDetector` kolem těla obrazovky, ale ten se k dotykům na
potomky nedostane, proto ta explicitní volání. Repose režim klávesnici
**neotevírá** sám.

**Styly (`lib/models/style_preset.dart`)**: 310 výtvarných bloků (97 kultur
a epoch, 103 podle konkrétních umělců, 110 médií a technik) ověřených
měřením (`docs/style-matrix.md`, vlna 7 v `docs/plan-styles-wave7.md`) — každý
prošel testem, že na něj aspoň jeden model skutečně reaguje, a že nedubluje
jiný styl v seznamu, vybírané `_StyleChip` v input baru. Blok se
připojuje **za** prompt (`applyStyle()`) — vlastní zadání má přednost; prázdný
prompt (foto root) zůstane prázdný, aby se styl nestal jediným obsahem. Na uzlu
se persistuje jen `GenNode.styleId`, text je z něj odvoditelný (stejný princip
jako u póz). Platí pro generate/refine/repose, **ne pro inpaint** (ten popisuje
jen zamalovanou oblast, celoobrazový styl by se s ním pral). **Repose je
výjimka** (styl vpředu, prefix podle `restyleKeepsPrefix()`, repose uzly před
v1.39 mají styl na konci): `tools/lab/README.md`, „Restyl z fotky“.

**Dialekty stylu (`PromptDialect`)**: styl má dva texty — `block` (volná
fráze, čte ji CLIP i T5) a volitelně `booru` (danbooru tagy **bez jména
umělce**). Který se pošle, rozhoduje `ImageModelSpec.promptDialect` přes
`StylePreset.blockFor()`; pole je výslovné, ne odvozené z `loraFamily`
(animagine-xl je LoRA-rodina `sdxl`, ale čte tagy). V provideru o tom
rozhoduje jediné místo, `_styled()`, vždy podle modelu, na kterém požadavek
běží. Text je tak odvozený z `(styleId, modelId)` — obojí na uzlu je, takže
retry i export zůstávají deterministické bez nového pole. Styl bez `booru`
posílá `block` všem, kulturní styly se tím nezměnily. Proč dva texty a ne tři
(věta pro FLUX nepřidala nic, tag umělce nepomohl, u NoobAI škodil): ablace
třetí vlny v `docs/style-matrix.md`.

**Picker stylů**: jedna zploštělá lista se sekcemi „Kultury a epochy" /
„Umělci" (podle `StylePreset.artist`; `artist` a `period` jsou jen pro UI,
do promptu nejdou) a hledáním podle labelu a autora bez ohledu na diakritiku
(`styleMatchesQuery`). Pořadí v sekcích dává `kStylePresetsSorted`: kultury podle
přibližného začátku, umělci podle roku narození (`StylePreset.year`), média
podle české abecedy; registr sám zůstává v pořadí měření. Řádek pickeru
a mapa stylů ukazují `labelWithYear` („Vermeer (1632)“), chip v input baru
kvůli šířce jen `label`. Vyhledávací pole se samo nefokusuje a seznam schovává
klávesnici při tažení. Podtitulek je vždy `block`, i u anime modelu — tagy by
se četly hůř.

**Ticho podle modelu (`lib/models/style_quiet.dart`, generuje
`tools/lab/reactions.py` z běhů vlny 7)**: dvojice (model, styl), u kterých
model namaloval s blokem totéž co bez něj (barevná vzdálenost od vlastního
baseline pod 0.15). Řádek pickeru se na vybraném modelu ztlumí a řekne, kde
styl reagoval (`styleAlternativeModel`: sdxl-base → juggernaut → lightning →
schnell, první dostupný a sám netichý); chip ukáže výstrahu. **Nikdy se
neskrývá**: metrika vidí jen barvu — Illustrious má u médií reakci 0.85 tím,
že postavu rozpustí v čmáranice, Pony u malířů 0.49 kostýmem — takže „změnilo
se“ neznamená „styl prošel“ a nezměřená dvojice se ukazuje normálně.

**Síla úpravy (`_EditStrengthChip`)**: `ComfyUIService.setEditDenoise()`
přebíjí presetový `img2imgDenoise`. Měření ukázalo, že při presetových ~0.72 je
img2img stylově skoro slepý (rozptyl 5–50× nižší než repose, u pony 0.011),
zatímco při `kStyleEditDenoise` 0.9 styl projde a pózu dál drží auto-depth.
Nabídka: jemná 0.5 / **automaticky** (null) / silná 0.9. „Automaticky" je
preset bez stylu a `kStyleEditDenoise` se stylem (`effectiveEditDenoise()`),
protože slabší úprava styl nepustí — ověřeno znovu na NoobAI a WAI přes 24
kulturních stylů (reakce img2img 0.16–0.18 proti 0.64–0.71 v repose). Rozhoduje
se až při odeslání (`_armEditDenoise()` v refine/retry) a stejnou funkcí se
zapisuje `GenNode.denoise`, takže snapshot odpovídá tomu, co běželo. Dřívější
volba „běžná" byla taky null, staré session tedy dostanou automatiku. Šablona
pózy si drží `kPoseEditDenoise` bez ohledu na volbu a inpaint jede vždy na 1.0.
Chip se ukazuje jen u ComfyUI img2img kola (NIM backendy denoise nemají);
se stylem ukazuje „auto · silná".

**Popisky modelů (`ImageModelSpec.styleNote`)**: jedna věta o tom, co model
udělá se stylovým promptem, ukazuje se v pickeru pod schopnostmi. Není odhad —
plyne z matice; „výchozí scéna" modelu je při výběru podstatnější než výčet
schopností.

**Rodiny LoRA (`lib/models/lora_family.dart`)**: `LoraFamily` rozlišuje
**linii**, ne jen architekturu — `flux / sdxl / pony / illustrious / sd15 /
wan / zimage / unknown`. `loraFit(lora, model)` vrací `native` (stejná linie),
`weak` (stejná architektura, jiná linie — Illustrious LoRA na Juggernautu se
načte, ale táhne slaběji), `unknown` (nezjištěno) nebo `incompatible` (jiná
architektura). `lorasForFamily()` vrací nabídku seřazenou native → weak →
unknown a **incompatible zahazuje**; picker sekce popisuje a u každé položky
píše rodinu.

Rodiny jsou **kurátorské podle metadat souboru** (`ss_base_model_version` /
`ss_sd_model_name`, čitelné přes ComfyUI `GET /view_metadata/loras?filename=`),
ne podle názvu — z názvu to spolehlivě nejde: `sexy_attire.safetensors` zní
jako každá druhá SDXL character LoRA, ale je trénovaná na
`runwayml/stable-diffusion-v1-5`. **SD 1.5 LoRA na SDXL není no-op** — UNet
klíče nesedí, ale sdílený CLIP-L text encoder ano, takže rozhodí prompt, aniž
by aplikovala natrénovaný koncept (ověřeno na serveru: mean 7.3/255 driftu,
nic z toho není subjekt LoRA). Z 36 LoRA na serveru takhle vypadlo 13
(8× SD 1.5, 4× WAN video, 1× Z-Image). Neznámá rodina se **nikdy neskrývá**,
jen označí — jinak by nová LoRA na serveru byla neviditelná do ruční editace
registru. Heuristika z názvu je až fallback pro soubory mimo registr.

**Katalog ze serveru** (`_loadServerCatalog()` v provideru, jednou při startu):
`ComfyUiService.fetchLoras()` / `fetchCheckpoints()` čtou
`GET /object_info/{LoraLoader,CheckpointLoaderSimple}` a berou options
combo-widgetu. LoRA seznam je tím pádem plně dynamický; checkpointy jen
**prořezávají** kurátorský `kImageModels` — `imageModelsFor()` zahodí ComfyUI
model, jehož `ckptName` na serveru není, takže picker nenabídne něco, co spadne
až při enqueue. Prázdný seznam = „neznámo" (offline / chyba fetche) ⇒ ukáže se
vše jako dřív; aktivní model (`keepId`) se nefiltruje nikdy, aby session
s odinstalovaným checkpointem měla koherentní výběr.

**Nový model na serveru se v appce neobjeví sám** — musí dostat
`ImageModelSpec` v `kImageModels`, protože ze jména `.safetensors` nejde
odvodit sampler/steps/cfg/negativ ani rodinu LoRA. Např.
juggernaut-xl-lightning (distilovaný 4-step ckpt) potřebuje 6 kroků a cfg 2.0
(`dpmpp_sde`/`karras`) — s generickými 30/6.0 by dal smetí.

**Negativní prompty (`lib/models/prompt_negatives.dart`)**: UI má jediné
vstupní pole — tagy/slova psané celé VELKÝMI písmeny (≥2 velká písmena, žádné
malé; `8K`/`I` zůstávají pozitivní) se přesunou do negativního promptu
(lowercase), po sobě jdoucí velká slova tvoří jeden tag (`BAD HANDS` → `bad
hands`). Split dělá `splitPromptNegatives()` v provideru
(generate/refine/retry); `node.prompt` ukládá původní text, takže retry split
zopakuje. Negativ jde do backendů přes `negativePrompt` parametr
`generate()`/`edit()`: ComfyUI generic template ho spojí s preset negativem do
`__NEGATIVE__`, flux-manga (cfg 1, bez sentinelu) a NIM backendy ho ignorují
(velká písmena se z pozitivního promptu odstraní i tam). Snapshot
`GenNode.negativePrompt` ukládá efektivní (preset + user) negativ jen tam, kde
se skutečně aplikuje.

**ControlNet pózy (`lib/models/pose_template.dart`)**: 8 OpenPose skeleton
šablon v `assets/poses/` (512×768). Výběr přes `_PoseChip` (grid bottom
sheet), viditelný jen pro modely s `supportsPose: true` (SDXL rodina — sd15
ne, openpose-xinsir ControlNet je SDXL-only). Aplikuje se na **txt2img i
img2img** — při `edit()` s aktivní pózou se denoise zvedne z presetového
`img2imgDenoise` (~0.72) na `kPoseEditDenoise` (0.9), jinak by struktura
zdrojového obrázku pózu přebila. Šablona se při generování nahraje přes
`/upload/image` (deterministické jméno `ol1n_pose_*.png`, overwrite, cache
per běh) a `_injectPoseControlNet()` v `_prepare()` vloží do grafu
`LoadImage → ControlNetLoader → ControlNetApplyAdvanced` mezi CLIPTextEncode
a KSampler (synthetic klíče `__pose_*__`, stejný princip jako LoRA injekce —
ortogonální hrany, komponují bez konfliktu). Při aktivní póze se txt2img
latent přepne na 832×1216 (portrét bucket, šablony jsou 2:3); img2img latent
zůstává odvozený ze zdrojového obrázku (VAEEncode). Strength 1.0 /
end_percent 1.0 — slabší hodnoty prohrávaly s promptem (ověřeno).
`selectedPoseId` se persistuje v session jako `selectedLora`.

**Auto póza ze zdroje (img2img)**: když u pose-capable modelu (SDXL,
`supportsPose`) běží `edit()` **bez** vybrané šablony, `_prepare()` protáhne
zdrojový obrázek přes `_injectSourceDepthControlNet()` — `LoadImage(zdroj) →
DepthAnythingV2Preprocessor → ControlNetLoader(union-promax-xinsir) →
SetUnionControlNetType(depth) → ControlNetApplyAdvanced` (synthetic klíče
`__depth_*__`, sdílený splice tail `_spliceControlNet()` s template-pose
cestou). Uživatel tak nemusí opisovat pózu — drží se ze zdroje sama. **Depth,
ne OpenPose záměrně**: skeleton zahazuje směr pohledu (čelní foto se otočí
zády), depth mapa udrží orientaci i proporce (ověřeno end-to-end na serveru).
Strength 0.7 (drží postoj, ale prompt pořád přebarví). Precedence:
**ruční šablona z pickeru > auto depth > nic** — šablona je override
(`poseImageName != null` vyhraje větev). Denoise zůstává na presetovém
`img2imgDenoise` (zdroj pózu nese sám, na rozdíl od šablony). Gate:
`_autoPose` (= `spec.supportsPose`, nastavuje provider v
`_applyModelToServices`) + `_preset.ckptName != null`. Auto stav se
nepersistuje — je deterministicky odvoditelný (img2img + SDXL model + bez
poseId).

**„Zachovej pózu“ (v kódu `repose`)**: ikona chodce na dlaždici
(`_ImageTile.onRepose`, pravý horní roh) přepne input bar do režimu Repose
(`ImageStudioState.reposeSourceImageId`, pill s miniaturou reference + ✕).
Název v UI je záměrně jiný než v kódu: „repose“ pochází z MangaPrompts, kde
šlo o opak — obličej se dával do **nové** pózy ze šablony. Tady se póza ze
zdroje naopak drží, takže by původní název sliboval pravý opak. Vnitřní název
(`GenNode.isRepose`, `ComfyUIService.repose()`) zůstává kvůli persistovanému
Hive klíči `isRepose`;
odeslaný text jde do `repose()` v provideru → `ComfyUIService.repose()`.
Běží nad **txt2img šablonou** (`sdxl_txt2img.api.json`, EmptyLatentImage,
denoise 1.0) a `_prepare()` dostane `depthImageName` = nahraná reference —
tatáž `_injectSourceDepthControlNet()` jako u auto pózy, ale se **strength
0.75 / end_percent 0.9** (`_reposeDepthStrength`, `_reposeDepthEndPercent`;
hodnoty ověřené v MangaPrompts pro depth → txt2img). Proč ne 1.0: při plné
síle přes celý schedule se zapeče objem těla/vlasů/oblečení z reference a
pere se s novou postavou; posledních 10 % kroků bez hintu nechá dosednout
detaily. Postava a styl jdou **celé z promptu** — přenos identity je
volitelný (viz „Zachovat tvář“ níž) — v telefonu chip „Tvář“.
Precedence injekce v `_prepare()`: **`depthImageName` > šablona
pózy > auto depth** — v repose se vybraná šablona ignoruje (reference *je*
póza), `_PoseChip` se v režimu skryje a `poseId` na nodu je null. Latent se
nebere z presetu: `lib/models/latent_bucket.dart` přečte rozměry reference
jen z hlavičky (PNG **i** JPEG — foto rooty jsou JPEG pod `.png` jménem) a
snapne na nejbližší SDXL bucket (`snapToSdxlBucket`, porovnání v log
prostoru). **Bucket sám ale ořezu nezabrání** — ComfyUI přizpůsobuje hint
latentu přes `common_upscale(…, "center")`, tj. škáluje na pokrytí a přebytek
ořízne. Fotka z telefonu 1:2 (434×884, 0.49) v nejbližším bucketu 768×1344
(0.57) tak přišla o ~110 px nahoře i dole: hlavu a chodidla, a InstantID
o klíčové body obličeje u horního okraje (tvář vyjížděla z rámu). Proto
`_injectSourceDepthControlNet(fitTo:)` vloží `__depth_fit__`
(`ImageResizeKJv2`, `keep_proportion: pad`, černé pruhy) mezi `__depth_src__`
a **všechno, co z předlohy čte** — hloubku i tvář (`_referenceImage()`).
Černá: DepthAnything ji čte jako daleké pozadí, InsightFace ji ignoruje.
Fituje se jen na txt2img cestě (`imageName == null`) — u img2img latent *je*
zdroj i s poměrem, takže není co fitovat; cílový rozměr je `latentSize`, jinak
preset, jinak baked-in latent dedikované šablony (`_txt2imgLatent`). Gate na
identitu zůstává `__depth_src__`, fit je jen mezikrok.
Prompt se **neřetězí** s předky (stejné pravidlo jako inpaint — staré tokeny
by tahaly starou postavu zpět); positivePrefix + preset negativ + ALL-CAPS
negativy platí, LoRA injekce taky. `GenNode.isRepose` (vzor `is3D`; width/
height = bucket, denoise 1.0) řídí vlastní větev v `retry()` (jinak by spadl
do generické img2img cesty) a resume přes `_comfyui.follow()` bez ohledu na
aktuálně vybraný model (ModelChip není při běhu zamčený). Jen SDXL modely
(`supportsPose`): `startRepose()` při ne-SDXL modelu přepne na naposledy
použitý SDXL v session (jinak první dostupný) a oznámí to přes `info`;
`_ModelChip(needsPose)` šedí ne-SDXL. Režim je transientní (nepersistuje
se, `selectImage`/`navigateTo`/přepnutí session ho ruší).

**„Zachovat tvář“ (`FaceIdentity`)**: repose drží pózu a
postavu zahodí; tohle ji vrací. Tvář se čte z **téhož** uploadu jako
hloubková mapa — uzel `__depth_src__`, který depth injekce už do grafu dala,
takže žádný druhý upload a žádná možnost, aby si póza a tvář myslely jinou
fotku. Gate je právě existence toho uzlu — tedy **kdekoli se injektuje
hloubka**: repose vždy, `POSE_MODE=depth` na img2img i txt2img, a taky
img2img u SDXL modelu bez vybrané pózy (tam auto-depth vzniká sám). Šablona
kostry ne, ta není fotka a obličej v ní není. Jinde je to no-op, což zároveň
drží hranu `['__depth_src__', 0]` bez visících konců.

V telefonu: chip `_FaceChip` („Tvář: nová / InstantID / FaceID / obojí“)
v input baru, viditelný jen tam, kde má odkud tvář číst — SDXL img2img bez
šablony pózy, nebo repose. `ImageStudioNotifier.setFaceIdentity()` →
`ComfyUIService.setFaceIdentity()` (vzor `setEditDenoise`); `edit()` ho
předá do `_prepare()`, `repose()` ho použije, když volající nepředá vlastní
(lab předává per buňku). Je to **session nastavení** jako styl a síla úpravy
(`ImageSession.faceIdentity`, jméno enum hodnoty, null = vypnuto), nepřebírá
se z nodu při navigaci. Na nodu se snapshotuje `GenNode.faceIdentity` **jen
když opravdu běželo** (`faceRan` v `_createNodeWithMeta` zrcadlí gate
služby: patched + `supportsPose` + repose, nebo img2img bez šablony a bez
masky) — stejně jako `loraStrength` jen s LoRA. Dotažení tváře
(`FaceDetailer`) v telefonu není, zůstává v labu.

| | SDXL (`ckptName != null`) | flux-manga |
|---|---|---|
| `instantid` | `ApplyInstantIDAdvanced` (embedding + vlastní keypoint CN, zvlášť síly) | PuLID |
| `faceid` | `IPAdapterFaceID` PlusV2 (jen model hrana) | PuLID |
| `both` | obě, InstantID první na model hraně | PuLID |

Rodina se pozná z grafu (`_isFluxGraph` = obsahuje `UNETLoader`), ne z
presetu — patchuje se graf. FLUX má jediný mechanismus, takže se na něj
mapuje každý režim; lab si proto **skutečnou** metodu čte zpátky z grafu
(`_effectiveFaceIdentity`), ne z toho, co se objednalo.

Model hrana se řetězí `loader → [__lora__] → [__face_apply__] →
[__faceid_apply__] → KSampler`. **Pořadí není kosmetické**: oba uzly patchují
attention přes sdílený `Attn2Replace` a druhý v řadě volá `.add()` na objekt
z předchozího uzlu, místo aby ho zkopíroval. Dřív byl FaceID první — jeho
výstup ComfyUI cachuje (na promptu nezávisí), InstantID se přepočítá s každým
promptem, takže každý další prompt přidal do cachovaného modelu další
InstantID patch. Restyle řada jedné fotky se tím buňku po buňce rozpouštěla
do šumu (běh `20261111-144619`: stddev obrázku 105 → 48 za 60 stylů, reset
u další fotky; běhy `none`/`instantid` rovné). V telefonu totéž při
opakovaném generování se stejnou předlohou. InstantID navíc vrací podmínění, takže sedí
**před** `__cn_apply__` (`__cn_apply__.positive == ['__face_apply__', 1]`) a
oba ControlNety se skládají — klíčové body obličeje uvnitř hloubkové siluety.
`end_at` **1.0**: hloubka se pouští na 90 %, aby dosedly textury,
ale tvář nemá do čeho dosedat a pustit ji dřív znamená nechat prompt rysy
zase odvést.

InstantID má **dvě síly**, proto `ApplyInstantIDAdvanced` a ne základní uzel
(ten má jedno `weight` pro obojí): `cn_strength` 0.8 je keypoint ControlNet
(kde tvář je), `ip_weight` 0.6 je IP-Adapter embedding předlohy (čí tvář to
je). Embedding je obrazový embedding *fotografie* vstříknutý do
cross-attention vedle textových tokenů, takže při 0.8 přes celý rozvrh
přebíjí blok stylu (ten je mimo repose na konci promptu, s nejnižší vahou). V img2img se
to skládá se zdrojovým latentem (denoise 0.72) a auto-depth hintem (0.7) —
tři kotvy k fotce proti jednomu stylu — a styl přežil jen na Juggernautu
(fotoreal SDXL-base finetune, doména, na které je adaptér natrénovaný;
booru modely jeho tokeny čtou jako šum a spadnou do výchozí scény). 0.6 je
**odhad podle doporučení InstantID pro stylizaci, ne měření** — ladit sweepem
`__face_apply__.ip_weight`. `noise` 0.35 a `combine_embeds` average jsou
vestavěné defaulty základního uzlu, u advanced jen vypsané, aby se přechodem
nezměnilo nic dalšího. PuLID jede 0.9 (ne 1.0 jako v odeslaném face inpaintu — tam
maska drží všechno mimo obličej, tady se generuje celý obraz a plná síla
začne táhnout i rámování reference).

**Dotažení tváře (`FaceDetailer`, Impact Pack)**: druhý průchod jen přes
nalezený obličej, přilepený na konec (`VAEDecode → __face_detail__ →
SaveImage`). Nezávislý přepínač, ale **jen se zapnutou identitou** — jinak by
tvář jen přelosoval. Jede na modelu ze sampleru (i s identitou), sampler
nastavení kopíruje z hotového KSampleru (proto se injektuje až za patch
smyčkou, aby u SDXL viděl presetové hodnoty a u fluxu ty baked-in), denoise
0.4. Podmínění bere **zpřed** hloubkového ControlNetu: detailer pracuje
s výřezem a celoobrazová hloubková mapa natažená na výřez popisuje něco
jiného. (InstantID svůj keypoint hint v tom podmínění veze taky a je taky
celoobrazový — jestli to na výřezu pomáhá, nebo vadí, ukáže až ostrý běh.)
SAM zůstává nezapojený (`sam_model_opt`) — na serveru žádný SAM model není
a na obličej stačí bbox.

**flux-manga umí repose**: guard `_reposeSupported` už není `ckptName != null`,
ale „generický SDXL template **nebo** flux-manga txt2img“ — flux-fill zůstává
venku, jeho `txt2imgAsset` ukazuje na inpaint workflow jen proto, že typ
hodnotu vyžaduje. Hloubkový ControlNet se u fluxu liší: dedikovaný
`flux-depth-controlnet-v3` (InstantX), **bez** `SetUnionControlNetType`, a
`ControlNetApplyAdvanced` dostane `vae` hranu (čte se z `VAEDecode`, takže
funguje pro `VAELoader` i pro VAE v checkpointu). Síla 0.55 je **odhad**, ne
měření — InstantX táhne silněji než xinsir, ladit sweepem
`__cn_apply__.strength`. `latentSize` se nově propíše i do dedikovaných
šablon (`EmptySD3LatentImage`), jinak by flux renderoval 1:1, zatímco hint je
2:3, a ControlNet by ho zmáčkl. **Telefon zůstává SDXL-only** —
`startRepose()` pořád přepíná na SDXL model; povolení fluxu v UI je
follow-up.

Váhy na serveru jsou všechny: InstantID (`ip-adapter.bin` +
`instantid-controlnet-sdxl`), FaceID PlusV2 (`ip-adapter-faceid-plusv2_sdxl.bin`
v `models/ipadapter/` + stejnojmenná LoRA v `models/loras/` — jména nechat
přesně, `IPAdapterUnifiedLoaderFaceID` je hledá podle názvu), PuLID
(`pulid_flux_v0.9.1`) i detektor (`bbox/face_yolov8m.pt`). Ověřeno proti
`/object_info`: 16 grafů (obě rodiny × 4 režimy × s/bez dotažení, s LoRA) —
třídy, povinné vstupy, enum hodnoty i hrany sedí. **SAM zatím ne** —
`SAMLoader` hlásí prázdný seznam, takže `sam_model_opt` zůstává nezapojený;
až tam model bude, je to malý follow-up (bbox na obličej stačí).

Buňka bez rozpoznatelného obličeje spadne na `execution_error` — per-buňka,
řečeno v hintu.

### gen-queue — NIM async job queue (`llm.ol1n.com/nim/*`)

Go služba `gen-queue` (AiStack, port 8091) obsluhuje **oba** FLUX NIM modely
jednotným async protokolem přes HTTP polling. Cloudflare routuje
`llm.ol1n.com/nim/*` přímo sem — návrh obchází Cloudflare 100s edge timeout
(submit vrátí job_id okamžitě) a job přežije iOS suspenzi (`follow()`).
Nahrazuje původní Python `nim-kontext-proxy`.

```
POST /nim/{model}/v1/infer          →  202 + {id, queue_position}   (vrátí okamžitě)
GET  /nim/{model}/jobs/{id}         →  {status, ...}                (poll každé 3s)
GET  /nim/{model}/jobs/{id}/result  →  obrázek (JPEG)               (po status=done)
```

`{model}` = `flux-schnell` (txt2img) nebo `flux-kontext` (img2img).

Status hodnoty: `queued` (s `queue_position`), `running`, `done`, `error` (s `error`).
gen-queue volá NIM synchronně ve worker poolu, retry na 5xx (3 pokusy: 0/5/10s),
4xx je non-retryable. Chybová těla jsou JSON `{"error":"..."}`.

**`/result` vrací JPEG, ne PNG** (ověřeno `file` na staženém výsledku, 2026-09-17)
— jméno souboru na disku `.png` je jen konvence appky (stejně jako u foto rootů,
viz `latent_bucket.dart`, který kvůli tomu čte hlavičku PNG i JPEG). Kdo ty bajty
dekóduje, musí umět obojí: v labu to drží `imageutil.go`, který registruje oba
dekodéry pro celý balíček, takže i `metrics.go` (importuje jen `image`) projde.

**TTL výsledků: 1 hodina od completion.** Po TTL se evictuje výsledek **i
job-status** současně → `/jobs/{id}` i `/result` pak vrací `404 {"error":"..."}`
(klient to mapuje na „queue restartován, generuj znovu"). Proto po dlouhé
suspenzi (>1 h) job zmizí úplně, ne jen jeho výsledek.

`n > 1` se řeší **n sekvenčními requesty** — backend zpracuje 1 obrázek na call,
`variantCount` u NIM = 1.

**`follow(jobId)`** (oba modely): plně funkční — poll do done, stáhnout result.
Páteř resume po iOS suspenzi.

- **flux-schnell** — txt2img only, `edit()` vrací GenFailed. ~4 kroky, rychlé.
- **flux-kontext** — img2img only, `generate()` vrací GenFailed. Vyžaduje `image`
  pole; klient snapuje rozměry na podporované hodnoty (672–1568) kvůli TRT bufferu.

### Srovnání

| Vlastnost | ComfyUI | gen-queue / flux-kontext | gen-queue / flux-schnell |
|---|---|---|---|
| Job model | async queue | async queue | async queue |
| Progress | WebSocket (per-step) | HTTP poll (3s) | HTTP poll (3s) |
| WS fallback | HTTP poll | — | — |
| n>1 | batch nativně | n × request | n × request |
| Cancel | POST /interrupt | ✗ | ✗ |
| follow() | ✓ (poll fallback) | ✓ | ✓ |
| TTL výsledků | do restartu serveru | 1h (job i result) | 1h (job i result) |
| Mod | txt2img + img2img | img2img only | txt2img only |
| CF timeout | není problém (WS) | gen-queue vrátí job_id hned | gen-queue vrátí job_id hned |
| Suspend/blip | GenInterrupted po 3 chybách | GenInterrupted (Socket/Timeout) | GenInterrupted (Socket/Timeout) |

### Resume po iOS suspenzi

Přechodný výpadek (uspání appky, síťový blip) **není** trvalé selhání. NIM služby
i ComfyUI při něm (Socket/Timeout, příp. 3× chyba pollu) emitují
`GenInterrupted(jobId)` místo `GenFailed`. Provider node nechá ve stavu
`generating`, zachová `jobId`, **uloží do Hive** (paměť = Hive) a strhne mrtvý
stream — bez červené chyby. `GenSubmitted(jobId)` ukládá jobId do `GenNode`.

Znovu-napojení spustí kterýkoli z těchto bodů:
- `AppLifecycleState.resumed` → `_resumeInFlightJob()` (`WidgetsBindingObserver`),
- backoff ~4 s po `GenInterrupted` (pokrývá foreground bliky), strop 5 pokusů,
- start appky: `_load()` obnoví sessions a pro generating node s jobId zavolá
  `_resumeInFlightJob()`.

`_resumeInFlightJob()` najde první node `status == generating && jobId != null`
a zavolá `backend.follow(jobId)`. Čítač pokusů se nuluje při reálném progresu
(`queued`/`running`); po vyčerpání → měkká chyba. Skutečné selhání (`GenFailed`)
i `cancel()` se **persistují**, takže restart už mrtvý/zrušený job neobnovuje.
