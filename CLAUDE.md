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
    flux_kontext_nim_service.dart  # NIM async job queue (poll-based)
    flux_nim_service.dart      # NIM synchronní request (flux-schnell)
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

Workflow jsou JSON assety v `assets/comfyui/`, patchované před odesláním (`__PROMPT__`, `__IMAGE__`, batch_size, seed, LoRA inject).

### NIM Kontext Proxy (`llm.ol1n.com/nim/flux-kontext/*`)

**Async job queue přes HTTP polling, navrženo pro obejití Cloudflare 100s edge timeoutu:**

```
POST /nim/flux-kontext/v1/infer     →  202 + {id, queue_position}   (vrátí okamžitě)
GET  /nim/flux-kontext/jobs/{id}    →  {status, step, total}         (poll každé 3s)
GET  /nim/flux-kontext/jobs/{id}/result  →  PNG bytes               (po status=done)
```

Status hodnoty: `queued` (s `queue_position`), `running` (s `step`/`total`), `done`, `error`.

`n > 1` se řeší **n sekvenčními requesty** — backend podporuje jen n=1 na call. kVariantCount=4 → 4× celý cyklus submit→poll→download.

**`follow(jobId)`**: plně funkční — poll do done, stáhnout result. Používá se při iOS suspenzi.

TTL výsledků: **1 hodina od completion**. Po TTL → 404.

**img2img only** — FLUX Kontext je edit model, `generate()` vrací GenFailed.

### FLUX Schnell NIM (`llm.ol1n.com/nim/flux-schnell/*`)

**Synchronní request bez job queue:**

```
POST /nim/flux-schnell/v1/infer  →  200 + {artifacts: [{base64: "..."}]}
```

Timeout 120s — blokující HTTP request, server vrátí obrázek až po dokončení inference.

`n > 1`: n sekvenčních requestů (každý blokuje).

**`follow()`**: nepodporováno (vrací GenFailed) — po suspenzi nelze obnovit.

**txt2img only**, žádný img2img.

### Srovnání

| Vlastnost | ComfyUI | NIM Kontext | FLUX Schnell |
|---|---|---|---|
| Job model | async queue | async queue | synchronní |
| Progress | WebSocket (per-step) | HTTP poll (3s) | žádný |
| WS fallback | HTTP poll | — | — |
| n>1 | batch nativně | n × request | n × request |
| Cancel | POST /interrupt | ✗ | ✗ |
| follow() | ✓ (poll fallback) | ✓ | ✗ |
| TTL výsledků | do restartu serveru | 1h od completion | — |
| Mod | txt2img + img2img | img2img only | txt2img only |
| CF timeout | není problém (WS) | proxy vrátí job_id hned | blokuje 120s |

### Resume po iOS suspenzi

`ImageStudioNotifier` implementuje `WidgetsBindingObserver`. Při `AppLifecycleState.resumed` volá `_resumeInFlightJob()`, která najde generating node s `jobId != null` a zavolá `backend.follow(jobId)`.

`GenSubmitted(jobId)` ukládá jobId do `GenNode` (persistováno v Hive). Na startu `_load()` obnoví sessions a pokud najde generating node s jobId, rovněž zavolá `_resumeInFlightJob()`.

## Persistence (Hive)

Box `image_sessions_v2` — JSON string se seznamem `ImageSession`.

**Proč v2**: původní box `image_sessions` ukládal obrázky jako base64 string přímo do JSON → desítky MB → OOM při čtení. Nový přístup: `GenImage.filePath` ukazuje na soubor v `applicationSupportDirectory/image_studio/<uuid>.png`. Box obsahuje jen cesty a metadata.

Starý box `image_sessions.hive` je při startu asynchronně smazán přes `_deleteLegacyBox()` (přímé `File.delete()`, bez Hive reads — aby nevyvolal další OOM).

## Chat

`ChatProvider` (Riverpod) → `VllmService` → `POST /v1/chat/completions` (streaming SSE). Persisto v Hive `chat_box`. Viz `lib/services/vllm_service.dart`.
