# Ol1nLLM — Flutter AI Chat + Image Studio

Flutter iOS/Android app. Chat s LLM modely a Image Studio pro generování obrázků.
Vše za Cloudflare Access (service token ve `--dart-define`).

## Build & Run

```bash
flutter run --dart-define=CF_ACCESS_CLIENT_ID=... \
            --dart-define=CF_ACCESS_CLIENT_SECRET=... \
            --dart-define=FLUX_NIM_URL=https://llm.ol1n.com \
            --dart-define=FLUX_KONTEXT_NIM_URL=https://llm.ol1n.com

# nebo zkratka přes Makefile:
make run
```

Pokud flutter run selže s „developer disk image could not be mounted":
```bash
open -a Xcode ios/Runner.xcworkspace   # počkat ~20s, DDI se namountuje automaticky
xcrun devicectl device info details --device <uuid> | grep ddiServices  # ověření
```

## Struktura

```
lib/
  main.dart                    # Hive.initFlutter(), ProviderScope
  providers/
    image_studio_provider.dart # StateNotifier + WidgetsBindingObserver (resume)
    chat_provider.dart
  models/
    gen_node.dart              # GenImage (filePath), GenNode (jobId), GenStatus
    image_model.dart           # registr modelů: ImageModelSpec + ComfyPreset + kImageModels
    image_session.dart         # ImageSession persistence (modelId; legacy backendId/workflow mapping)
  services/
    comfyui_service.dart       # ComfyUI WebSocket + HTTP polling backend
    finetune_export_service.dart   # export session → FINETUNE gallery (NAS)
    flux_kontext_nim_service.dart  # gen-queue async job queue — flux-kontext (img2img)
    flux_nim_service.dart      # gen-queue async job queue — flux-schnell (txt2img)
    image_backend.dart         # ImageBackend interface + GenEvent sealed class
  screens/
    image_studio_screen.dart
    chat_screen.dart
```

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
(např. LAN `http://192.168.88.66:8188` pro testování bez CF).

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

**Styly (`lib/models/style_preset.dart`)**: 40 výtvarných bloků ověřených
měřením (`docs/style-matrix.md`) — každý prošel testem, že na něj aspoň jeden
model skutečně reaguje, a že nedubluje jiný styl v seznamu, vybírané `_StyleChip` v input baru. Blok se
připojuje **za** prompt (`applyStyle()`) — vlastní zadání má přednost; prázdný
prompt (foto root) zůstane prázdný, aby se styl nestal jediným obsahem. Na uzlu
se persistuje jen `GenNode.styleId`, text je z něj odvoditelný (stejný princip
jako u póz). Platí pro generate/refine/repose, **ne pro inpaint** (ten popisuje
jen zamalovanou oblast, celoobrazový styl by se s ním pral).

**Síla úpravy (`_EditStrengthChip`)**: `ComfyUIService.setEditDenoise()`
přebíjí presetový `img2imgDenoise`. Měření ukázalo, že při presetových ~0.72 je
img2img stylově skoro slepý (rozptyl 5–50× nižší než repose, u pony 0.011),
zatímco při `kStyleEditDenoise` 0.9 styl projde a pózu dál drží auto-depth.
Nabídka: jemná 0.5 / běžná (preset) / silná 0.9. Šablona pózy si drží
`kPoseEditDenoise` bez ohledu na volbu a inpaint jede vždy na 1.0. Chip se
ukazuje jen u ComfyUI img2img kola (NIM backendy denoise nemají).

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
detaily. Postava a styl jdou **celé z promptu** — žádný přenos identity
(IPAdapter/InstantID), žádný hi-res/FaceDetailer; tvář lze doplnit face
inpaintem. Precedence injekce v `_prepare()`: **`depthImageName` > šablona
pózy > auto depth** — v repose se vybraná šablona ignoruje (reference *je*
póza), `_PoseChip` se v režimu skryje a `poseId` na nodu je null. Latent se
nebere z presetu: `lib/models/latent_bucket.dart` přečte rozměry reference
jen z hlavičky (PNG **i** JPEG — foto rooty jsou JPEG pod `.png` jménem) a
snapne na nejbližší SDXL bucket (`snapToSdxlBucket`, porovnání v log
prostoru), jinak by `ControlNetApplyAdvanced` depth hint center-cropnul.
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

### gen-queue — NIM async job queue (`llm.ol1n.com/nim/*`)

Go služba `gen-queue` (AiStack, port 8091) obsluhuje **oba** FLUX NIM modely
jednotným async protokolem přes HTTP polling. Cloudflare routuje
`llm.ol1n.com/nim/*` přímo sem — návrh obchází Cloudflare 100s edge timeout
(submit vrátí job_id okamžitě) a job přežije iOS suspenzi (`follow()`).
Nahrazuje původní Python `nim-kontext-proxy`.

```
POST /nim/{model}/v1/infer          →  202 + {id, queue_position}   (vrátí okamžitě)
GET  /nim/{model}/jobs/{id}         →  {status, ...}                (poll každé 3s)
GET  /nim/{model}/jobs/{id}/result  →  PNG bytes                    (po status=done)
```

`{model}` = `flux-schnell` (txt2img) nebo `flux-kontext` (img2img).

Status hodnoty: `queued` (s `queue_position`), `running`, `done`, `error` (s `error`).
gen-queue volá NIM synchronně ve worker poolu, retry na 5xx (3 pokusy: 0/5/10s),
4xx je non-retryable. Chybová těla jsou JSON `{"error":"..."}`.

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

## Stylová matice (`scripts/style_matrix/`)

Nástroj pro otázku „co který model udělá s kterým stylem". Workflow staví
**kód appky** (`prepareForTest` → `_prepare`), takže měří to, co appka
skutečně posílá. `./scripts/style_matrix/run.sh --ref-prompt "…"` projede
reference → dump → generování → skóre → kontaktní archy; přepínači jde zúžit
modely, styly i flow (`--flows repose,img2img,txt2img`, `--edit-denoise 0.9`).
Ke každému modelu se dumpuje i `__baseline` (týž prompt bez bloku stylu), aby
šlo odlišit „model na styl reaguje" od „tohle maluje vždycky". Generování je
resumovatelné. Metriky jsou barevné, tedy jen předvýběr — rozhoduje pohled na
arch. Poslední výsledky a verdikty: `docs/style-matrix.md`.

## FINETUNE gallery export

Tlačítko exportu (AppBar + per-session v draweru) posílá session (strom nodů +
PNG) na Go backend na NAS (`FINETUNE_URL`, default `https://finetune.ol1n.com`,
repo `finetune-gallery`), kde se výstupy hodnotí a staví LoRA datasety.

**Per-node metadata**: `GenNode` od této verze snapshotuje při vzniku modelId,
loraName, loraStrength, poseId, seed, negativePrompt, positivePrefix, width/height,
steps/cfg/denoise, sampler/scheduler, createdAt, origin (`'upload'` pro foto
roots). Sampler pole se ukládají jen pro generic-template ComfyUI modely
(`ckptName != null`) — flux-manga a NIM mají hodnoty baked-in/konstantní,
dohledatelné z modelId. Vše nullable → staré Hive sessions validní bez migrace.
`retry()` přegeneruje snapshot podle aktuálního modelu (běží na aktuálním
backendu) + nový seed.

**Protokol** (`finetune_export_service.dart`) — dvoufázový, content-addressed,
idempotentní (re-export pošle jen nové obrázky):
1. `POST /api/ingest/manifest` — session + ready nody + per-image
   `{id, sha256, size, idx}` → `{"needed": [sha…]}`
2. `PUT /api/ingest/images/{sha256}` — raw PNG, retry vzorem ComfyUI uploadu
   (3 pokusy, lineární backoff, 60 s timeout)
3. `POST /api/ingest/sessions/{id}/finalize` → `{"images": N, "newBlobs": M}`

Session ukládá `exportedAt` + `exportedImageCount`; staleness = počet ready
obrázků ≠ exportovaný počet (ne `updatedAt`, ten se bumpá i navigací). Ikona
v draweru: cloud_upload (neexportováno/stale) / cloud_done (aktuální) /
progress ring. Chyby jdou přes standardní error snackbar, úspěch přes
`state.info`.

## Persistence (Hive)

Box `image_sessions_v2` — JSON string se seznamem `ImageSession`.

**Proč v2**: původní box `image_sessions` ukládal obrázky jako base64 string přímo do JSON → desítky MB → OOM při čtení. Nový přístup: `GenImage.filePath` ukazuje na soubor v `applicationSupportDirectory/image_studio/<uuid>.png`. Box obsahuje jen cesty a metadata.

Starý box `image_sessions.hive` je při startu asynchronně smazán přes `_deleteLegacyBox()` (přímé `File.delete()`, bez Hive reads — aby nevyvolal další OOM).

## Chat

`ChatProvider` (Riverpod) → `VllmService` → `POST /v1/chat/completions` (streaming SSE). Persisto v Hive `chat_box`. Viz `lib/services/vllm_service.dart`.
