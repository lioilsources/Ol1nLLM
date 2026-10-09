"""Optional step of the StyleMap pipeline: what a VLM says about each picture
(plan §2.4).

    python tag_images.py --set build/stylemap/<set>

Asks a vision model, one picture per request, for the fields in
`common.FACETS` plus a few free keywords, and writes `tags.json` next to the
set. build_map.py turns that into the facets the widget filters by. Tags are
for filtering and search — never for placing a picture on the map.

Answers are cached per picture file in `build/stylemap/_tags/`, so an
interrupted run loses nothing and a picture in two sets is asked once.

The model shares a GPU with other work and only runs in a window; the script
stops by itself at `--until` and after a few failures in a row, and whatever
is cached by then is written out.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from pathlib import Path

from PIL import Image

from common import FACETS, TAG_CACHE, credentials

SYSTEM = (
    "You catalogue the visual style of images. Ignore who or what is depicted; "
    "describe only how the image is rendered. Answer with compact JSON on a "
    "single line."
)
# Left to itself the model fills `words` with the five answers it has just
# given ("warm palette", "soft lines"), which adds nothing to search.
ASK = (
    "Describe the style of this image. `words`: 3 to 6 short lowercase English "
    "keywords for what the other fields do not say — art movement, era, "
    "technique, brushwork or rendering, lighting, an artist or school it "
    "resembles. Do not repeat the other fields and do not name the subject."
)
SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": [*FACETS, "words"],
    "properties": {
        **{k: {"type": "string", "enum": list(v)} for k, (_, v) in FACETS.items()},
        "words": {"type": "array", "minItems": 3, "maxItems": 6, "items": {"type": "string"}},
    },
}
# Bump when the question changes: old answers are then asked again.
VERSION = 2


def data_url(path: str, side: int) -> str:
    im = Image.open(path).convert("RGB")
    im.thumbnail((side, side), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=88)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def ask(url: str, model: str, key: str, path: str, side: int, timeout: float,
        temperature: float = 0) -> dict:
    body = {
        "model": model,
        "temperature": temperature,
        "max_tokens": 200,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": data_url(path, side)}},
                {"type": "text", "text": ASK},
            ]},
        ],
        "response_format": {
            "type": "json_schema",
            "json_schema": {"name": "style", "strict": True, "schema": SCHEMA},
        },
    }
    req = urllib.request.Request(
        f"{url.rstrip('/')}/chat/completions", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}",
                 "User-Agent": "ol1n-stylemap/1", **credentials()},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        out = json.loads(r.read())
    return validate(json.loads(out["choices"][0]["message"]["content"]))


def probe(url: str, model: str, key: str, timeout: float) -> bool:
    """Does the model see pictures at all? Two flat colours, one word each.

    A text model behind a vision-shaped API answers the schema just as
    readily — from nothing — and every picture would get plausible tags.
    """
    ok = True
    for name, rgb in (("red", (220, 30, 30)), ("blue", (30, 60, 220))):
        buf = io.BytesIO()
        Image.new("RGB", (256, 256), rgb).save(buf, "PNG")
        body = {
            "model": model, "temperature": 0, "max_tokens": 20,
            "messages": [{"role": "user", "content": [
                {"type": "image_url", "image_url": {
                    "url": "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()}},
                {"type": "text", "text": "What single colour fills this image? Answer with one word."},
            ]}],
        }
        req = urllib.request.Request(
            f"{url.rstrip('/')}/chat/completions", data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}",
                     "User-Agent": "ol1n-stylemap/1", **credentials()},
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                said = json.loads(r.read())["choices"][0]["message"]["content"] or ""
        except urllib.error.HTTPError as e:
            said = f"HTTP {e.code}: {e.read()[:300].decode(errors='replace')}"
        except (urllib.error.URLError, TimeoutError, KeyError, json.JSONDecodeError) as e:
            said = repr(e)
        hit = name in said.lower()
        ok &= hit
        print(f"  zkouška {name}: {'✓' if hit else '✗'} {said.strip()[:200]!r}", flush=True)
    return ok


def validate(tags: dict) -> dict:
    """Only what was asked for, in the vocabulary it was asked in — a model
    that ignores the schema must not put a new chip into a facet."""
    for k, (_, values) in FACETS.items():
        if tags.get(k) not in values:
            raise ValueError(f"{k}={tags.get(k)!r} není v nabídce")
    words = [w.strip().lower() for w in tags.get("words") or [] if isinstance(w, str) and w.strip()]
    return {**{k: tags[k] for k in FACETS}, "words": words[:6]}


def deadline(until: str) -> datetime:
    """The next time the clock shows `until` (HH:MM)."""
    now = datetime.now()
    h, m = map(int, until.split(":"))
    at = now.replace(hour=h, minute=m, second=0, microsecond=0)
    return at if at > now else at + timedelta(days=1)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", type=Path, help="directory with items.json")
    ap.add_argument("--probe", action="store_true",
                    help="jen ověřit, že model obrázky opravdu vidí (kód 1, když ne)")
    ap.add_argument("--url", default="http://192.168.88.66:8080/v1", help="OpenAI-compatible gateway")
    ap.add_argument("--model", default="openclaw-default")
    ap.add_argument("--key", default="dummy")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--side", type=int, default=384, help="longer side sent to the model")
    ap.add_argument("--until", default="00:50", help="HH:MM, kdy skončit (konec okna modelu)")
    ap.add_argument("--timeout", type=float, default=120)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--collect", action="store_true",
                    help="na model se neptat, jen zapsat tags.json z toho, co je v cache")
    args = ap.parse_args()

    if args.probe:
        raise SystemExit(0 if probe(args.url, args.model, args.key, args.timeout) else 1)
    if not args.set:
        ap.error("--set je povinný")

    items = json.loads((args.set / "items.json").read_text())["items"]
    TAG_CACHE.mkdir(parents=True, exist_ok=True)

    def cache_of(path: str) -> Path:
        sha = hashlib.sha256(Path(path).read_bytes()).hexdigest()
        return TAG_CACHE / f"{sha}.json"

    caches = {it["id"]: cache_of(it["path"]) for it in items}

    def cached(it: dict) -> dict | None:
        c = caches[it["id"]]
        if not c.exists():
            return None
        got = json.loads(c.read_text())
        return got["tags"] if got.get("v") == VERSION and got.get("model") == args.model else None

    todo = [it for it in items if cached(it) is None]
    have = len(items) - len(todo)
    if args.limit:
        todo = todo[:args.limit]
    stop = deadline(args.until)
    print(f"{len(items)} obrázků, {have} v cache, ptám se na {len(todo)} "
          f"({args.model}, souběžnost {args.jobs}, do {stop:%H:%M})", flush=True)

    state = {"done": 0, "failed": 0, "streak": 0, "halt": ""}
    t0 = time.time()

    def work(it: dict) -> None:
        last = ""
        for attempt in range(4):
            if state["halt"]:
                return
            if datetime.now() >= stop:
                state["halt"] = f"je {args.until}, okno modelu končí"
                return
            try:
                # At temperature 0 a bad answer is the same bad answer again
                # (the schema lets the model pad with whitespace until it
                # runs out of tokens), so a repeat is asked a little warmer.
                tags = ask(args.url, args.model, args.key, it["path"], args.side,
                           args.timeout, temperature=0.3 * attempt)
            except (ValueError, KeyError) as e:  # the answer, not the server
                last = repr(e)
                continue
            except (urllib.error.URLError, TimeoutError) as e:
                last = f"HTTP {e.code}: {e.read()[:200].decode(errors='replace')}" \
                    if isinstance(e, urllib.error.HTTPError) else repr(e)
                state["streak"] += 1
                if state["streak"] >= 8:
                    state["halt"] = f"osm chyb serveru po sobě, poslední: {last}"
                    return
                # A pause, not a tight loop: the model may be loading, or busy
                # with whoever it is shared with.
                time.sleep(20 * (attempt + 1))
                continue
            state["streak"] = 0
            tmp = caches[it["id"]].with_suffix(".part")
            tmp.write_text(json.dumps({"v": VERSION, "model": args.model, "tags": tags}, ensure_ascii=False))
            tmp.replace(caches[it["id"]])
            state["done"] += 1
            if state["done"] % 25 == 0:
                rate = state["done"] / (time.time() - t0) * 60
                print(f"  {state['done']}/{len(todo)}  ({rate:.0f}/min)", flush=True)
            return
        state["failed"] += 1
        print(f"  ✗ {it['id']}: {last}", flush=True)

    if todo and not args.collect:
        with ThreadPoolExecutor(args.jobs) as pool:
            list(pool.map(work, todo))

    out = {it["id"]: t for it in items if (t := cached(it)) is not None}
    (args.set / "tags.json").write_text(json.dumps(out, ensure_ascii=False))
    if state["halt"]:
        print(f"zastaveno: {state['halt']}")
    print(f"hotovo → {args.set}/tags.json: {len(out)}/{len(items)} obrázků má tagy"
          + (f", {state['failed']} selhalo" if state["failed"] else ""))


if __name__ == "__main__":
    main()
