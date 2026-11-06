"""Shared bits of the StyleMap pipeline: reading an image set and its labels.

An image set today is a lab run directory (`build/lab/<id>`): one PNG per cell
in `img/`, and `wf/manifest.json` saying how each one was made. The pipeline
only needs, per image, a stable id, a path, a human label and the prompt
fragment the picker hands back (`tag`) — everything else stays in the manifest,
which is the source of truth for how an image came to be (plan §10).
"""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

# The cheap features, in the order they are stored. Keys are what map.json
# calls them; build_map.py owns the Czech labels.
CHEAP_KEYS = [
    "lum", "contrast", "sat", "hue", "hue_conc", "warm", "tint", "edge",
    "sharp", "colors", "colorful", "entropy", "grain",
]

# Bipolar zero-shot axes: score = sim(image, a) - sim(image, b), so a high
# value means "more like a". Prompts name a medium, never a subject — the
# subject is the same across the set and would only add a constant.
ZS_AXES = [
    ("photo", "a photograph", "a drawing"),
    ("real", "a realistic, lifelike image", "a heavily stylized image"),
    ("anime", "an anime or manga illustration", "a western comic book illustration"),
    ("paint", "a painterly image, oil, watercolor or gouache",
     "a graphic image, vector art, flat colors or pixel art"),
    ("render3d", "a 3D render", "a 2D illustration"),
    ("sketch", "a rough sketch or line art", "a fully rendered, finished illustration"),
    ("vintage", "a vintage, retro image", "a modern, clean image"),
    ("dark", "a dark, moody image", "a bright, cheerful image"),
    ("minimal", "a minimal, simple image", "a detailed, busy image"),
]

MEDIA = [
    "photo", "oil painting", "watercolor", "pencil sketch", "ink drawing",
    "pixel art", "3D render", "anime cel shading", "comic book", "collage",
    "low poly", "paper cutout", "pastel drawing", "digital painting",
]

# What the VLM is asked about every picture (tag_images.py) and what the
# widget filters by: key → (Czech name, {value: Czech label}). The values are
# the model's whole vocabulary — a closed list, so a facet has a handful of
# chips and not one per spelling. `medium` is the CLIP list above on purpose:
# a set without VLM tags gets the same facet from the zero-shot guess.
FACETS: dict[str, tuple[str, dict[str, str]]] = {
    "medium": ("Médium", dict(zip(MEDIA, [
        "fotka", "olejomalba", "akvarel", "kresba tužkou", "kresba tuší",
        "pixel art", "3D render", "anime", "komiks", "koláž", "low poly",
        "papírová vystřihovánka", "pastel", "digitální malba",
    ]))),
    "palette": ("Paleta", {
        "warm": "teplá", "cool": "studená", "pastel": "pastelová", "muted": "tlumená",
        "vivid": "sytá", "monochrome": "jednobarevná", "dark": "tmavá",
        "earthy": "zemitá", "neon": "neonová",
    }),
    "mood": ("Nálada", {
        "calm": "klidná", "joyful": "radostná", "dramatic": "dramatická",
        "melancholic": "melancholická", "dark": "temná", "dreamy": "snová",
        "playful": "hravá", "sensual": "smyslná", "tense": "napjatá",
    }),
    "line": ("Linka", {
        "none": "bez linek", "soft": "měkká", "clean": "čistá", "bold": "silná",
        "sketchy": "skicovitá",
    }),
    "background": ("Pozadí", {
        "plain": "jednolité", "gradient": "přechod", "abstract": "abstraktní",
        "interior": "interiér", "landscape": "krajina", "urban": "město",
        "pattern": "vzor",
    }),
}

@dataclass
class Item:
    id: str
    path: Path
    label: str
    tag: str
    prompt: str
    # Registry ids the picture was made with, when the source knows them: a
    # pick can then set the app's style chip instead of pasting text.
    style: str = ""
    model: str = ""


def load_run(run: Path, tag_regex: str | None, limit: int | None = None) -> list[Item]:
    """The finished cells of a lab run, in manifest order.

    `label` is what the widget prints under the picture and `tag` what it hands
    to the prompt. Runs made with --prompts-yaml carry the prompt's name in
    `promptBody` (the artist, or "character, series"); older runs do not, so
    `tag_regex` pulls the fragment out of the prompt text instead.
    """
    man = json.loads((run / "wf" / "manifest.json").read_text())
    rx = re.compile(tag_regex) if tag_regex else None
    out: list[Item] = []
    for cell in man["cells"]:
        path = run / "img" / f"{cell['id']}.png"
        if not path.exists():
            continue  # failed or not yet generated
        prompt = cell.get("prompt") or ""
        body = cell.get("promptBody") or ""
        tag = ""
        if rx:
            m = rx.search(prompt)
            tag = m.group(0).strip() if m else ""
        elif body and body != "baseline":
            tag = body
        label = body or _unescape(tag.removeprefix("artist:")) or "bez tagu"
        style = cell.get("style") or ""
        out.append(Item(
            cell["id"], path, label, tag, prompt,
            "" if style.startswith("__") else style, cell.get("model") or "",
        ))
        if limit and len(out) >= limit:
            break
    return out


def _unescape(s: str) -> str:
    return s.replace("\\(", "(").replace("\\)", ")").replace("_", " ").strip()


# --- FINETUNE gallery as a source -------------------------------------------

DEFAULT_GALLERY = "https://finetune.ol1n.com"
REPO_ROOT = Path(__file__).resolve().parents[2]
# One answer per picture file, shared by every set the picture is in.
TAG_CACHE = REPO_ROOT / "build" / "stylemap" / "_tags"


def credentials() -> dict[str, str]:
    """CF Access headers from the environment, else from the repo's .env.local
    (the same two places the lab looks). None at all is fine on the LAN."""
    vals: dict[str, str] = {}
    env_file = REPO_ROOT / ".env.local"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            key, sep, val = line.partition("=")
            if sep and not key.lstrip().startswith("#"):
                vals[key.strip()] = val.strip().strip("'\"")
    cid = os.environ.get("CF_ACCESS_CLIENT_ID") or vals.get("CF_ACCESS_CLIENT_ID", "")
    secret = os.environ.get("CF_ACCESS_CLIENT_SECRET") or vals.get("CF_ACCESS_CLIENT_SECRET", "")
    if not (cid and secret):
        return {}
    return {"CF-Access-Client-Id": cid, "CF-Access-Client-Secret": secret}


def _get(url: str, headers: dict[str, str], timeout: float = 60) -> bytes:
    # Cloudflare answers urllib's default User-Agent with a 403 before Access
    # ever sees the token.
    req = urllib.request.Request(url, headers={"User-Agent": "ol1n-stylemap/1", **headers})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        hint = " (CF Access token?)" if e.code in (401, 403) else ""
        raise SystemExit(f"galerie: HTTP {e.code}{hint} — {url}") from None
    except urllib.error.URLError as e:
        raise SystemExit(f"galerie: {e.reason} — {url}") from None


def gallery_rows(base: str, session: str, where: dict[str, str]) -> list[dict]:
    """Every image of one session that passes `where` (the gallery's own
    /api/images filters: score=1, model=…, style=…), oldest first."""
    headers = credentials()
    rows: list[dict] = []
    cursor = None
    while True:
        q = {**where, "session": session, "limit": "200"}
        if cursor:
            q["cursor"] = cursor
        page = json.loads(_get(f"{base}/api/images?{urllib.parse.urlencode(q)}", headers))
        rows += page["items"]
        cursor = page.get("nextCursor")
        if not cursor:
            break
    # The API pages newest first; a stable order keeps `i` (the preview's file
    # name) the same when a set is rebuilt.
    rows.sort(key=lambda r: (r.get("createdAt") or "", r["id"]))
    return rows


def load_gallery(
    base: str, sessions: list[str], where: dict[str, str], cache: Path,
    tag_regex: str | None, full: bool = False, limit: int | None = None,
) -> list[Item]:
    """Images of one or more gallery sessions, downloaded into `cache`.

    By default the gallery's 384 px thumbnails: the features are computed at
    256 px and CLIP sees 224, the previews the widget shows are 384 — the
    originals would be 30× the download for the same pack. `full` fetches them
    anyway (for sharper atlas work later). The uploaded reference a lab run
    hangs its cells under is not a result and is left out.
    """
    base = base.rstrip("/")
    headers = credentials()
    rx = re.compile(tag_regex) if tag_regex else None
    kind, ext = ("img", "png") if full else ("thumb", "jpg")
    cache.mkdir(parents=True, exist_ok=True)

    rows: list[dict] = []
    seen: set[str] = set()
    for sid in sessions:
        got = [r for r in gallery_rows(base, sid, where) if r.get("origin") != "upload"]
        print(f"  session {sid}: {len(got)} obrázků", flush=True)
        for r in got:
            if r["sha256"] not in seen:  # the same picture exported twice
                seen.add(r["sha256"])
                rows.append(r)
    if limit:
        rows = rows[:limit]

    def fetch(r: dict) -> None:
        dst = cache / f"{r['sha256']}.{ext}"
        if dst.exists() and dst.stat().st_size > 0:
            return
        tmp = dst.with_suffix(".part")
        tmp.write_bytes(_get(f"{base}/{kind}/{r['sha256']}", headers, timeout=120))
        tmp.replace(dst)

    with ThreadPoolExecutor(8) as pool:
        for k, _ in enumerate(pool.map(fetch, rows)):
            if k % 500 == 0:
                print(f"  staženo {k}/{len(rows)}", flush=True)

    many_models = len({r.get("modelId") for r in rows}) > 1
    out: list[Item] = []
    for r in rows:
        prompt = r.get("prompt") or ""
        style, model = r.get("styleId") or "", r.get("modelId") or ""
        tag = ""
        if rx and (m := rx.search(prompt)):
            tag = m.group(0).strip()
        # The label names what the set varies: the tag, the style preset, the
        # model when there is more than one. A picture with none of them is the
        # set's baseline — the motif alone.
        parts = [_unescape(tag.removeprefix("artist:")), style, model if many_models else ""]
        label = " · ".join(p for p in parts if p)
        if not tag and not style:
            label = " · ".join(p for p in ("základ", model if many_models else "") if p)
        out.append(Item(
            r["id"], cache / f"{r['sha256']}.{ext}", label, tag, prompt, style, model,
        ))
    return out
