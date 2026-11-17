# Ol1nLLM — Flutter AI Chat + Image Studio

## Účel
Flutter app (iOS/Android, desktop jen ověřovací build): chat s LLM a RAG personami,
Image Studio, MusicStudio, Voice Studio, video a StoryStudio. Vše za Cloudflare
Access (service token ve `--dart-define`).

## Build a test
```bash
make run          # release, dart-define z .env.local (CF_ACCESS_*, volitelné *_URL)
make debug        # nutné pro LAN HTTP URL ($SPARK_HOST…), release cleartext nepustí
flutter analyze --no-fatal-infos            # gate (jako CI)
flutter test --exclude-tags screenshots     # gate (jako CI)
make lab | lab-dry | stylemap …             # nástroje, viz docs/lab.md, docs/style-map.md
```
URL overrides, DDI potíže na iOS: `docs/build.md`.

## Mapa
- `lib/` — `providers/` (Riverpod, Image Studio + Chat), `models/` (registry modelů,
  stylů, póz, LoRA rodin), `services/` (backendy ComfyUI, gen-queue, vLLM, RAG, audio,
  video), `screens/`, `widgets/`, `stylemap/`. Podrobný strom: `docs/architecture.md`.
- `assets/comfyui/` — workflow JSONy patchované před odesláním; `assets/personas/` — persony chatu.
- `backend/` — pomocné serverové věci (ComfyUI, image-api, nim-kontext-proxy, ocr-api).
- `tools/lab/` (Go + Dart dump), `tools/stylemap/` (Python pipeline), `tools/facebench/`.
- `test/` + `test/fixtures/` — zachycené skutečné odpovědi serverů.
- `.github/workflows/` — CI a release (odvozené z Distribution).

## Invarianty
- Release build nese CF Access token a repo je veřejné: binárky nikam veřejně
  (TestFlight, Firebase App Distribution; GitHub Release bez souborů). Viz README.
- `seed` losuje provider, ne backend; ukládá se na `GenNode`.
- ComfyUI `clientId` je per job, ne per instance; `follow()` WS neotevírá.
- `GenInterrupted` je neterminální: node zůstává `generating`, resume přes `follow()`.
- Nový model na serveru se v appce neobjeví sám: potřebuje `ImageModelSpec` v `kImageModels`.
- Prompt odchází jen přes `_outgoing()`, styl jen přes `_styled()`; překladač na booru
  tagy je fail open.
- Lab měří to, co appka opravdu posílá: workflow staví `tools/lab/dump.dart` z kódu appky,
  Dart registry jsou jediný zdroj pravdy.
- U stylů v labu nic nevyřazovat sám: změřit vše, ukázat, verdikt je návrh, do registru
  jde jen schválené.
- Klávesnici schovat u všeho, co není psaní (`_dismissKeyboard()`), žádný auto-focus.
- Chat: míchané vlákno vLLM/RAG je zakázané, routing jen v `_backendFor()`; serverová
  session se recykluje jen při `remoteLeafId == activeLeafId`.
- Hive drží jen cesty k PNG (`image_sessions_v2`), ne base64.
- Knihovna drží originály, ne překlady; překládá se až výstup.
- Screenshot goldeny mají tag `screenshots`, běží jen na macOS a běžný test je vynechává.

## Odchylky
Žádné.

## Kam dál
- `docs/build.md` — build, URL overrides, iOS DDI
- `docs/architecture.md` — strom `lib/`, persistence (Hive)
- `docs/image-studio.md` — ImageBackend, ComfyUI (modely, styly, LoRA, pózy, tvář), gen-queue, resume
- `docs/image-studio-inpaint.md` — face inpaint, Kadeřník, Tančící figurka, identita ve videu
- `docs/music-studio.md`, `docs/voice-studio.md`, `docs/video.md` (Rozhýbat, StoryStudio)
- `docs/style-map.md`, `docs/lab.md`, `docs/screenshots.md`, `docs/finetune-export.md`
- `docs/chat.md` — vLLM, Knihovna, Právník, Leads, agent smluv, knihovní RAG server
- Plány: `PLAN-inpainting.md`, `docs/plan-*.md`, `docs/STYLEMAP_PLAN.md`, `docs/vram-plan.md`
