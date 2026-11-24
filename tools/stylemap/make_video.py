"""Slideshow of a style map pack as a vertical MP4 (TikTok, Reels, Shorts).

    python make_video.py --set build/stylemap/<set> --out video.mp4 \
        --where model=noobai-xl --rate 4 --fade 0.5

Plays the pictures in the order the app's player uses — the LPIPS `tour` of
the pack, so neighbouring frames differ as little as possible — and writes
1080×1920 H.264 through ffmpeg.

- `--where key=value` keeps only matching pictures (repeatable; values of one
  key are alternatives, different keys all have to hold — the app's filter).
  Keys are the picture's fields (`model`, `medium`, `style`, …), its VLM tags,
  and `flow` (the lab flow, from the cell id).
- With a filter and `lpips.npy` in the set, the route is planned again over
  just those pictures: the global tour skips across the others, so a subset
  played in its order jumps.
- `--rate` is pictures per second, `--fade` the share of each picture's time
  spent crossfading into the next (0 = hard cut).
- Frames come from the originals (`items.json` paths — a lab run or `FULL=1`),
  else from the pack's 384 px thumbnails, which are soft at 1080 px.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def parse_where(items: list[str]) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for w in items:
        if "=" not in w:
            sys.exit(f"--where čeká key=value, ne {w!r}")
        k, v = w.split("=", 1)
        out.setdefault(k.strip(), set()).add(v.strip())
    return out


def field(img: dict, key: str) -> str | None:
    if key == "flow":
        return img["id"].split("__", 1)[0]
    if key in img and not isinstance(img[key], (list, dict)):
        return str(img[key])
    v = (img.get("tags") or {}).get(key)
    return None if v is None else str(v)


def matches(img: dict, where: dict[str, set[str]]) -> bool:
    return all(field(img, k) in vals for k, vals in where.items())


def route(images: list[dict], set_dir: Path, items: list[dict], replan: bool) -> list[dict]:
    """The pack's tour (the app's order), or Hilbert for a pack without one;
    re-planned over the subset when asked and LPIPS distances are there."""
    lp = set_dir / "lpips.npy"
    if replan and lp.exists() and len(images) > 3:
        sys.path.insert(0, str(Path(__file__).parent))
        from build_map import tour  # same planner as the pack's own route

        index = {it["id"]: i for i, it in enumerate(items)}
        idx = [index[im["id"]] for im in images]
        d = np.load(lp, mmap_mode="r")[np.ix_(idx, idx)].astype(np.float64)
        return [images[i] for i in tour(d)]
    key = "tour" if all("tour" in im for im in images) else "hilbert"
    return sorted(images, key=lambda im: im[key])


def frame_of(path: Path, w: int, h: int, fit: str) -> np.ndarray:
    """One picture on a w×h canvas. `contain` keeps all of it over a blurred,
    darkened copy of itself (no black bars); `cover` crops to fill."""
    im = Image.open(path).convert("RGB")
    s_cover = max(w / im.width, h / im.height)
    if fit == "cover":
        big = im.resize((round(im.width * s_cover), round(im.height * s_cover)), Image.LANCZOS)
        x, y = (big.width - w) // 2, (big.height - h) // 2
        return np.asarray(big.crop((x, y, x + w, y + h)))
    bg = im.resize((max(1, round(im.width * s_cover / 8)), max(1, round(im.height * s_cover / 8))),
                   Image.BILINEAR).filter(ImageFilter.GaussianBlur(6))
    bg = bg.resize((round(im.width * s_cover), round(im.height * s_cover)), Image.BILINEAR)
    x, y = (bg.width - w) // 2, (bg.height - h) // 2
    canvas = Image.eval(bg.crop((x, y, x + w, y + h)), lambda v: int(v * 0.45))
    s = min(w / im.width, h / im.height)
    fg = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    canvas.paste(fg, ((w - fg.width) // 2, (h - fg.height) // 2))
    return np.asarray(canvas)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--set", type=Path, required=True, help="adresář packu (map.json)")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--where", action="append", default=[], help="key=value, opakovatelné")
    ap.add_argument("--rate", type=float, default=4, help="obrázků za vteřinu (výchozí 4)")
    ap.add_argument("--fade", type=float, default=0.4,
                    help="podíl času obrázku na prolínačku do dalšího, 0 = střih (výchozí 0.4)")
    ap.add_argument("--fps", type=int, default=30, help="snímků videa za vteřinu")
    ap.add_argument("--size", default="1080x1920")
    ap.add_argument("--fit", choices=["contain", "cover"], default="contain",
                    help="contain = celý obrázek na rozmazaném pozadí, cover = ořez na výšku")
    ap.add_argument("--max-seconds", type=float, default=0,
                    help="zkrátit na tuto délku rovnoměrným výběrem po trase (0 = vše)")
    ap.add_argument("--no-replan", action="store_true",
                    help="i s filtrem hrát v pořadí celé mapy (jako appka)")
    ap.add_argument("--audio", type=Path, help="zvuková stopa, ořízne se na délku videa")
    ap.add_argument("--crf", type=int, default=18)
    args = ap.parse_args()

    if not shutil.which("ffmpeg"):
        sys.exit("chybí ffmpeg (brew install ffmpeg)")
    if not 0 < args.rate <= args.fps or not 0 <= args.fade < 1:
        sys.exit(f"--rate musí být v rozsahu (0, {args.fps}] a --fade v rozsahu 0–0.99")
    w, h = (int(v) for v in args.size.lower().split("x"))
    pack = json.loads((args.set / "map.json").read_text())
    items_path = args.set / "items.json"
    items = json.loads(items_path.read_text())["items"] if items_path.exists() else []
    originals = {it["id"]: Path(it["path"]) for it in items if it.get("path")}

    where = parse_where(args.where)
    images = [im for im in pack["images"] if matches(im, where)]
    if not images:
        sys.exit("filtru neodpovídá žádný obrázek")
    images = route(images, args.set, items, replan=bool(where) and not args.no_replan)
    if args.max_seconds and len(images) / args.rate > args.max_seconds:
        keep = max(1, int(args.max_seconds * args.rate))
        images = [images[round(i * (len(images) - 1) / max(1, keep - 1))] for i in range(keep)]

    def source(im: dict) -> Path:
        p = originals.get(im["id"])
        if p is not None and p.exists():
            return p
        return args.set / pack["thumbs"].replace("{i}", str(im["i"]))

    soft = sum(1 for im in images if source(im).parent.name == "t")
    hold = args.fps / args.rate  # video frames per picture
    total = round(hold * len(images))
    print(f"{len(images)} obrázků · {args.rate:g}/s · prolínačka {args.fade:g} · "
          f"{total / args.fps:.1f} s · {w}×{h}"
          + (f" · {soft} jen z 384px náhledů" if soft else ""), flush=True)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{w}x{h}", "-r", str(args.fps), "-i", "-"]
    if args.audio:
        cmd += ["-i", str(args.audio), "-map", "0:v", "-map", "1:a", "-c:a", "aac",
                "-b:a", "192k", "-shortest"]
    cmd += ["-c:v", "libx264", "-preset", "medium", "-crf", str(args.crf),
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(args.out)]
    ff = subprocess.Popen(cmd, stdin=subprocess.PIPE)

    t0 = time.time()
    cur = nxt = None
    for k in range(total):
        i = min(int(k / hold), len(images) - 1)
        if k == 0 or int((k - 1) / hold) != i:  # a new picture starts
            cur = nxt if nxt is not None else frame_of(source(images[i]), w, h, args.fit)
            nxt = (frame_of(source(images[i + 1]), w, h, args.fit)
                   if i + 1 < len(images) else None)
        frame = cur
        phase = (k - i * hold) / hold  # 0..1 within this picture
        if nxt is not None and args.fade > 0 and phase > 1 - args.fade:
            a = (phase - (1 - args.fade)) / args.fade
            frame = (cur * (1 - a) + nxt * a).astype(np.uint8)
        ff.stdin.write(np.ascontiguousarray(frame).tobytes())
        if k and k % (args.fps * 10) == 0:
            print(f"  {k / total:4.0%}  ({time.time() - t0:.0f} s)", flush=True)
    ff.stdin.close()
    if ff.wait() != 0:
        sys.exit("ffmpeg skončil chybou")
    print(f"hotovo → {args.out}  ({time.time() - t0:.0f} s)")


if __name__ == "__main__":
    main()
