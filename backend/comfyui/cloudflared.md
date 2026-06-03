# Plan: expose ComfyUI at `comfyui.ol1n.com` via cloudflared

Goal: reach the local ComfyUI (`:8188`) from the app over
`https://comfyui.ol1n.com`, protected by the **same Cloudflare Access service
token** already used for `llm.ol1n.com`. ComfyUI itself stays bound to
localhost / the internal Docker network and is never exposed publicly.

```
Flutter app ──HTTPS + CF-Access-Client-Id/Secret──▶ Cloudflare edge
   │                                                     │ (Access policy: service token)
   │                                                     ▼
   │                                        cloudflared (named tunnel)
   │                                                     │ ingress
   └─────────────── wss /ws (progress) ──────────────────┘──▶ http://comfyui:8188
```

There are two ways to wire this. **Option A** (extend the existing tunnel) is
recommended if `llm.ol1n.com` already runs through one cloudflared tunnel — add
a hostname instead of standing up a second tunnel.

---

## Prerequisites (one-time, in the Cloudflare dashboard)

1. `ol1n.com` is on Cloudflare (you already have `llm.ol1n.com`).
2. A **named tunnel** exists (e.g. `ai-stack`) and runs via cloudflared on the
   backend. If not: `cloudflared tunnel login` then
   `cloudflared tunnel create ai-stack` (writes `<TUNNEL_ID>.json` creds).
3. **Zero Trust → Access → Service Auth → Service Tokens**: reuse the existing
   token whose Client ID/Secret you already build the app with (the `CF_` pair).

---

## Option A — add a hostname to the existing tunnel  ✅ recommended

### 1. DNS route

Point a CNAME for the new hostname at the tunnel:

```bash
cloudflared tunnel route dns ai-stack comfyui.ol1n.com
```

(or in the dashboard: a `CNAME comfyui → <TUNNEL_ID>.cfargotunnel.com`, proxied).

### 2. Add an ingress rule

In the tunnel's `config.yml` (see `cloudflared.config.example.yml`), add a
hostname **above** the catch-all 404:

```yaml
ingress:
  - hostname: llm.ol1n.com          # existing
    service: http://llm:8000
  - hostname: comfyui.ol1n.com      # NEW
    service: http://comfyui:8188     # container name on the 'ai' network,
                                     # or http://localhost:8188 if bare-metal
  - service: http_status:404
```

Restart cloudflared (`systemctl restart cloudflared` or recreate the container).
WebSockets (`/ws`) pass through automatically — no extra config.

### 3. Cloudflare Access policy

Zero Trust → **Access → Applications → Add application → Self-hosted**:

- **Application domain:** `comfyui.ol1n.com`
- **Policy:** Action **Service Auth**, Include → **Service Token** → *your
  existing token*. This makes the `CF-Access-Client-Id` / `-Secret` headers the
  only accepted credential — exactly what the app sends.
- (Optional) add a second **Allow** policy for your own email/identity so you
  can open the ComfyUI web UI in a browser to edit workflows.

That's it — the app's existing `CF_` headers now authenticate to ComfyUI too.

---

## Option B — standalone cloudflared for ComfyUI

If you'd rather keep it separate, run a dedicated cloudflared next to ComfyUI.
See `docker-compose.comfyui.yml` (ships ComfyUI + cloudflared) and point
`config.yml` `ingress` at `http://comfyui:8188`. Steps 1 and 3 above are
identical (DNS route + Access policy for `comfyui.ol1n.com`).

---

## Why no Cloudflare 100 s timeout problem here

ComfyUI generation can run minutes — longer than Cloudflare's ~100 s proxy
limit (which would 524). The app avoids that the same way the diffusers backend
does: `POST /prompt` returns a `prompt_id` **immediately**, then progress comes
over the websocket (long-lived, not subject to the request timeout) or via
short polling requests, and the final image is fetched in a single `/view`
call. No single HTTP request stays open across the whole generation.

---

## Verify

From a machine with the service token:

```bash
# Health / queue — should return JSON, not a login page
curl -s https://comfyui.ol1n.com/system_stats \
  -H "CF-Access-Client-Id:  $CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" | head

# WebSocket upgrade (needs a recent curl) — expect HTTP/1.1 101 Switching Protocols
curl -s -i -N \
  -H "CF-Access-Client-Id:  $CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGVzdA==" \
  "https://comfyui.ol1n.com/ws?clientId=test" | head -1
```

If `system_stats` returns JSON and the WS line shows `101`, the app's
WebSocket-progress path will work; otherwise it transparently falls back to
HTTP polling.
