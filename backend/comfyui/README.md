# ComfyUI backend for Image Studio

Image Studio can target two image backends, switchable from the app's
top-bar picker:

| Backend            | Endpoint               | Engine                                   |
| ------------------ | ---------------------- | ---------------------------------------- |
| **Diffusers (FLUX)** *(default)* | `https://llm.ol1n.com` | FastAPI job API in `backend/image-api` (FLUX.1-dev + Qwen-Image-Edit) |
| **ComfyUI**        | `https://comfyui.ol1n.com` | A real ComfyUI instance, native API |

Both go through the **same Cloudflare Access service token** (`CF_ACCESS_CLIENT_ID`
/ `CF_ACCESS_CLIENT_SECRET`, passed via `--dart-define`). Nothing app-side
changes between them except the host.

The ComfyUI path uses ComfyUI's **native API** as-is — no custom server code:

| Concern              | ComfyUI API used                                  |
| -------------------- | ------------------------------------------------- |
| Async job queue      | `POST /prompt` → `prompt_id` (enqueue & return)   |
| Live per-step progress | `WS /ws?clientId=…` (`progress`, `executing`, `execution_error`) |
| Progress fallback    | `GET /history/{id}` + `GET /queue` polling         |
| Download result      | `GET /view?filename=…&subfolder=…&type=output`     |
| img2img input        | `POST /upload/image`                               |
| Cancel               | `POST /interrupt`                                  |
| Free VRAM (nicety)   | `POST /free`                                       |

The Dart client lives in `lib/services/comfyui_service.dart`
(`ComfyUIService implements ImageBackend`). It prefers the websocket for true
per-step progress and **falls back to polling** automatically if the WS
upgrade is refused (e.g. on web, or if CF Access blocks the upgrade).

---

## 1. Run ComfyUI on the backend

ComfyUI listens on `:8188` by default. Run it however you like; the simplest
is the maintained Docker image. Example (GPU host, joins the existing `ai`
Docker network so cloudflared can reach it by name):

```bash
docker run -d --name comfyui --restart unless-stopped \
  --gpus all --network ai \
  -v /home/ol1n/comfyui/models:/app/models \
  -v /home/ol1n/comfyui/input:/app/input \
  -v /home/ol1n/comfyui/output:/app/output \
  -p 127.0.0.1:8188:8188 \
  ghcr.io/yanwk/comfyui-boot:cu124-slim
```

(or run bare-metal: `python main.py --listen 127.0.0.1 --port 8188`).

Then expose it at `comfyui.ol1n.com` through cloudflared — see
[`cloudflared.md`](./cloudflared.md) for the full plan, and
[`docker-compose.comfyui.yml`](./docker-compose.comfyui.yml) for a ready compose.

> Do **not** publish ComfyUI to the public internet directly — it has no auth.
> Cloudflare Access (service token) is what protects it.

---

## 2. Models the workflows expect

The shipped workflows (`assets/comfyui/flux_manga_*.api.json`) reference these
**filenames**. Drop the files into your ComfyUI `models/` tree:

```
models/
├── unet/   flux1-dev.safetensors          # FLUX.1-dev transformer
├── clip/   t5xxl_fp16.safetensors         # T5-XXL text encoder
│           clip_l.safetensors             # CLIP-L text encoder
├── vae/    ae.safetensors                 # FLUX VAE
└── loras/  manga_flux_lora.safetensors    # ← the manga style LoRA (you pick)
```

- FLUX.1-dev + the CLIP/VAE files: `black-forest-labs/FLUX.1-dev` and
  `comfyanonymous/flux_text_encoders` on Hugging Face.
- If your machine is short on VRAM, swap `unet/flux1-dev.safetensors` for an
  fp8 build and keep `weight_dtype: fp8_e4m3fn` (already set in the workflow).

### The manga LoRA (placeholder)

The workflow ships with a **placeholder** LoRA filename
`manga_flux_lora.safetensors`. Pick any FLUX-compatible manga/anime line-art
LoRA (Civitai / Hugging Face have several), then either:

- **rename your file** to `manga_flux_lora.safetensors` and drop it in
  `models/loras/`, **or**
- **edit the workflow** — change `"lora_name"` in node `13` of both
  `flux_manga_txt2img.api.json` and `flux_manga_img2img.api.json` to your
  actual filename, and tune `strength_model` / `strength_clip` (0.6–1.0 is a
  good manga range).

After adding files, refresh ComfyUI (the **R** key, or reload the page) so the
loaders see them.

---

## 3. Get the workflow into the ComfyUI web UI

You only need this if you want to **tweak the graph visually**; the app embeds
the API-format JSON and doesn't need anything imported.

1. Open `https://comfyui.ol1n.com` in a browser (you'll pass Cloudflare Access
   — log in with your CF identity, or use a browser the token grants).
2. **Settings → enable “Dev mode”** (adds *Save (API Format)* and lets you load
   API-format JSON).
3. **Menu → Load** (or just **drag-and-drop** the file onto the canvas) and
   pick `assets/comfyui/flux_manga_txt2img.api.json`.
   - Recent ComfyUI frontends import API-format JSON directly. If yours can't,
     rebuild the graph from the node list (it's small) and **Save (API Format)**
     back over the asset.
4. Make sure every loader resolves to a real file (no red nodes). Fix
   filenames if a model is missing — see §2.
5. **Queue Prompt** once to confirm it renders. Then the app will produce the
   same images via the API.

> Keep the API JSON in `assets/comfyui/` as the source of truth — that's what
> the app sends to `POST /prompt`.

---

## 4. How the app patches the workflow

`ComfyUIService._prepare` deep-copies the template and substitutes per request,
**by sentinel / `class_type`** (not by node id), so you can rearrange the graph
freely as long as you keep:

| What                | Marker in the workflow                                  |
| ------------------- | ------------------------------------------------------- |
| Prompt text         | the string `__PROMPT__` in the positive `CLIPTextEncode` |
| Input image (img2img) | the string `__IMAGE__` in `LoadImage.image`            |
| Variant count       | `batch_size` on `EmptySD3LatentImage` / `amount` on `RepeatLatentBatch` |
| Seed                | any node with a `seed` / `noise_seed` input (randomised each run) |

So adding upscalers, face-fixers, ControlNet, extra LoRAs, etc. is just normal
ComfyUI editing — keep those four markers intact and the app keeps working.

---

## 5. ComfyUI niceties wired into the app

- **Real progress bar** — per-step % straight from the WS `progress` events.
- **Queue position** — shown while the job waits (`status` / `/queue`).
- **Cancel** — the ⏹ button calls `POST /interrupt`.
- **Result download** — finished images are fetched once via `/view` (the
  large bytes are *not* re-sent on every poll, dodging Cloudflare's 100 s cap).
- **`freeMemory()`** — `ComfyUIService.freeMemory()` calls `POST /free` to drop
  VRAM / unload models when you want to hand the GPU back.
