# FINETUNE gallery export

Přesunuto z `CLAUDE.md`.


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

**Překlad promptu na Danbooru tagy** (`finetune_translate_service.dart`).
Booru modely (`promptDialect == PromptDialect.booru`) čtou tagy a prózu
špatně; text uživatele proto před každým kolem projde `_outgoing()` v
provideru — jediné místo, odkud prompt odchází do backendu. Na booru modelu
se přeloží přes `POST {FINETUNE_URL}/api/translate` (galerie: jeden systémový
prompt, filtr proti slovníku WD14, cache podle hashe, žádný fallback model).
Blok stylu se přidává **až po překladu** přes `_styled()` — má vlastní
`booru` variantu, do překladače nejde; `positivePrefix` předřazuje backend
ještě později. Tři pravidla:
- **Fail open.** Galerie, gateway nebo model dole, timeout 12 s, chybějící
  CF credentials → próza jde ven, jak byla napsaná. Kolo nikdy nečeká déle
  ani nespadne kvůli překladači.
- **Node nese, co odešlo.** `GenNode.promptSent` (finální text po řetězu,
  stylu a překladu) a `translator` (`alias@verze`, null = jak napsáno) jdou
  exportem do galerie; Eval podle `translator` měří, jestli překlad pomáhá.
  Retry, které spadne do fail-open, `translator` maže (`clearTranslator`).
- **Hair inpaint se nepřekládá** — běží vlastní workflow, ne nutně aktivní
  checkpoint. Maskovaná úprava se překládá, ale styl nedostává (stávající
  pravidlo inpaintu).

Model za překladem je doplněk `prompt-tags` profilu comfy na SPARKu
(AiStack); bez něj appka funguje beze změny, jen posílá prózu.
