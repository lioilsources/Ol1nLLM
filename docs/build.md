# Build a konfigurace

Přesunuto z `CLAUDE.md`.

## Build & Run

```bash
flutter run --dart-define=CF_ACCESS_CLIENT_ID=... \
            --dart-define=CF_ACCESS_CLIENT_SECRET=... \
            --dart-define=FLUX_NIM_URL=https://llm.ol1n.com \
            --dart-define=FLUX_KONTEXT_NIM_URL=https://llm.ol1n.com

# nebo zkratka přes Makefile:
make run
```

Volitelné URL overrides (`.env.local`, Makefile je propouští jen když jsou
neprázdné): `COMFYUI_URL`, `FINETUNE_URL`, `FLUX_NIM_URL`, `VLLM_URL`,
`LIBRARY_CHAT_URL`, `LAW_CHAT_URL`, `LEADS_CHAT_URL`, `UGC_FC_URL`, `AUDIO_URL`,
`STYLEMAP_URL`. Pro vývoj knihovny proti SPARKu na LAN:
`LIBRARY_CHAT_URL=http://SPARK_HOST:8090` (Právník: `LAW_CHAT_URL=http://SPARK_HOST:8098`; Leads: `LEADS_CHAT_URL=http://SPARK_HOST:8099`,
to je zároveň výchozí hodnota, tunel zatím není) — pak ale **jen `make debug`**
(release Android manifest nemá `usesCleartextTraffic` a iOS nemá výjimku
v `Info.plist`, takže čistý HTTP tam neprojde).

Pokud flutter run selže s „developer disk image could not be mounted":
```bash
open -a Xcode ios/Runner.xcworkspace   # počkat ~20s, DDI se namountuje automaticky
xcrun devicectl device info details --device <uuid> | grep ddiServices  # ověření
```
