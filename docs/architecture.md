# Architektura

Přesunuto z `CLAUDE.md`.

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
    chat_backend.dart          # ChatBackend interface + ChatEvent sealed class
    vllm_service.dart          # llm.ol1n.com — OpenAI SSE, stateless
    library_chat_service.dart  # chat.ol1n.com — RAG knihovna, session na serveru
    law_agent_service.dart     # pravnik.ol1n.com/agent/chat — Právník sepisuje smlouvy (JSON krok)
    music_service.dart         # llm.ol1n.com/v1/audio/vibe — MusicStudio (ACE-Step)
    voice_service.dart         # llm.ol1n.com/v1/audio/tts + /voices — Voice Studio (řeč, klony hlasů)
    video_service.dart         # llm.ol1n.com/v1/video — Rozhýbat (scéna nebo vlastní pohyb)
    story_service.dart         # llm.ol1n.com/v1/video/stories — StoryStudio
  screens/
    image_studio_screen.dart
    chat_screen.dart
    music_studio_screen.dart
    voice_studio_screen.dart
    story_studio_screen.dart   # + story_setup_screen.dart (obsazení rolí)
    style_map_screen.dart      # mapy stylů: výběr sady + widget StyleMap
  stylemap/                    # widget StyleMap, model packu, StyleMapService
```

## Persistence (Hive)

Box `image_sessions_v2` — JSON string se seznamem `ImageSession`.

**Proč v2**: původní box `image_sessions` ukládal obrázky jako base64 string přímo do JSON → desítky MB → OOM při čtení. Nový přístup: `GenImage.filePath` ukazuje na soubor v `applicationSupportDirectory/image_studio/<uuid>.png`. Box obsahuje jen cesty a metadata.

Starý box `image_sessions.hive` je při startu asynchronně smazán přes `_deleteLegacyBox()` (přímé `File.delete()`, bez Hive reads — aby nevyvolal další OOM).
