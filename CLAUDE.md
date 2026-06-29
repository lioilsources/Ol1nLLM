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
    image_session.dart         # ImageSession persistence
  services/
    comfyui_service.dart       # ComfyUI WebSocket + HTTP polling backend
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
- `generate(prompt, n)` → `Stream<GenEvent>` — txt2img
- `edit(image, prompt, n)` → `Stream<GenEvent>` — img2img
- `follow(jobId)` → `Stream<GenEvent>` — resume přerušeného jobu
- `interrupt()` — zrušení

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

`n > 1` řeší ComfyUI nativně přes `batch_size` / `RepeatLatentBatch` — jediný request, server vygeneruje n obrázků najednou.

**`follow(promptId)`**: přeskočí enqueue, jde rovnou do polling fallbacku (WS je ztracený po suspenzi). Výsledky na serveru přežívají restart ComfyUI? Ne — history se resetuje. TTL: neomezené do restartu serveru.

Po **3 po sobě jdoucích** chybách pollu (typicky uspání / síťový výpadek) `_pollUntilDone` vrátí `GenInterrupted(promptId)` místo tichého opakování až do 10min deadlinu — provider se pak znovu napojí.

Workflow jsou JSON assety v `assets/comfyui/`, patchované před odesláním (`__PROMPT__`, `__IMAGE__`, batch_size, seed, LoRA inject).

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

## Persistence (Hive)

Box `image_sessions_v2` — JSON string se seznamem `ImageSession`.

**Proč v2**: původní box `image_sessions` ukládal obrázky jako base64 string přímo do JSON → desítky MB → OOM při čtení. Nový přístup: `GenImage.filePath` ukazuje na soubor v `applicationSupportDirectory/image_studio/<uuid>.png`. Box obsahuje jen cesty a metadata.

Starý box `image_sessions.hive` je při startu asynchronně smazán přes `_deleteLegacyBox()` (přímé `File.delete()`, bez Hive reads — aby nevyvolal další OOM).

## Chat

`ChatProvider` (Riverpod) → `VllmService` → `POST /v1/chat/completions` (streaming SSE). Persisto v Hive `chat_box`. Viz `lib/services/vllm_service.dart`.
