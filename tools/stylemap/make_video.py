"""Slideshow of a style map pack or a lab run as a vertical MP4 (TikTok, Reels, Shorts).

    python make_video.py --set build/stylemap/<set> --out video.mp4 \
        --where model=noobai-xl --rate 4 --fade 0.5
    python make_video.py --run build/lab/<run> --out video.mp4 --order style --label

Writes 1080×1920 H.264 through ffmpeg. Two sources, two orders:

- `--set` (a style map pack): the order the app's player uses — the LPIPS
  `tour`, so neighbouring frames differ as little as possible. With a filter
  and `lpips.npy` in the set, the route is planned again over just those
  pictures: the global tour skips across the others, so a subset played in
  its order jumps.
- `--run` (a lab run directory, no pack needed): its finished cells.
- `--order style`: one style at a time across all models — prompt, then
  style (the app's picker order when the run's manifest has it, baseline
  first), then flow, then model in a fixed order (`--model-order`). The
  comparison “what does each model make of Bauhaus”. Default for `--run`.

- `--where key=value` keeps only matching pictures (repeatable; values of one
  key are alternatives, different keys all have to hold — the app's filter).
  Keys: `model`, `style`, `flow`, and for packs the picture's other fields
  and VLM tags (`medium`, …).
- `--rate` is pictures per second, `--fade` the share of each picture's time
  spent crossfading into the next (0 = hard cut). `--label` burns in
  “style · model” so a viewer knows what they are looking at.
- Frames come from the originals (lab images, `items.json` paths), else from
  the pack's 384 px thumbnails, which are soft at 1080 px.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field as dfield
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

BASELINE = "__baseline"


@dataclass
class Pic:
    id: str
    path: Path
    model: str
    style: str
    flow: str
    prompt: int = 0
    label: str = ""  # style as a person reads it
    model_label: str = ""
    extra: dict = dfield(default_factory=dict)  # pack fields and tags, for --where
    thumb: bool = False

    def get(self, key: str) -> str | None:
        if key in ("model", "style", "flow"):
            return getattr(self, key)
        v = self.extra.get(key)
        if v is None:
            v = (self.extra.get("tags") or {}).get(key)
        return None if v is None or isinstance(v, (list, dict)) else str(v)


def parse_where(items: list[str]) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for w in items:
        if "=" not in w:
            sys.exit(f"--where čeká key=value, ne {w!r}")
        k, v = w.split("=", 1)
        out.setdefault(k.strip(), set()).add(v.strip())
    return out


def from_pack(set_dir: Path) -> tuple[list[Pic], list[str], list[dict]]:
    pack = json.loads((set_dir / "map.json").read_text())
    items_path = set_dir / "items.json"
    items = json.loads(items_path.read_text())["items"] if items_path.exists() else []
    originals = {it["id"]: Path(it["path"]) for it in items if it.get("path")}
    pics = []
    for im in pack["images"]:
        path = originals.get(im["id"])
        thumb = path is None or not path.exists()
        if thumb:
            path = set_dir / pack["thumbs"].replace("{i}", str(im["i"]))
        parts = im["id"].split("__")
        pics.append(Pic(
            id=im["id"], path=path, model=im.get("model") or "",
            style=im.get("style") or (BASELINE if "____baseline" in im["id"] else
                                      (parts[2] if len(parts) > 2 else "")),
            flow=parts[0], label=im.get("label") or "", model_label=im.get("model") or "",
            extra=im, thumb=thumb,
        ))
    return pics, [], items


def from_run(run: Path) -> tuple[list[Pic], list[str], list[str]]:
    """Finished cells of a lab run, plus its style order (the app's picker
    order, as the lab writes it) and model order."""
    man = json.loads((run / "wf" / "manifest.json").read_text())
    pics = []
    for c in man["cells"]:
        path = run / "img" / f"{c['id']}.png"
        if not path.exists():
            continue
        style = c.get("style") or BASELINE
        pics.append(Pic(
            id=c["id"], path=path, model=c["model"], style=style, flow=c.get("flow", ""),
            prompt=int(c.get("promptIndex") or 0),
            label="bez stylu" if style == BASELINE else (c.get("styleLabel") or style),
            model_label=c.get("modelLabel") or c["model"],
        ))
    styles = [s["id"] if isinstance(s, dict) else s for s in man.get("styles") or []]
    models = [m["id"] if isinstance(m, dict) else m for m in man.get("models") or []]
    return pics, styles, models


def tour_order(pics: list[Pic], set_dir: Path, items: list[dict], replan: bool) -> list[Pic]:
    """The pack's tour (the app's order), or Hilbert for a pack without one;
    re-planned over the subset when asked and LPIPS distances are there."""
    lp = set_dir / "lpips.npy"
    if replan and lp.exists() and len(pics) > 3:
        sys.path.insert(0, str(Path(__file__).parent))
        from build_map import tour  # same planner as the pack's own route

        index = {it["id"]: i for i, it in enumerate(items)}
        idx = [index[p.id] for p in pics]
        d = np.load(lp, mmap_mode="r")[np.ix_(idx, idx)].astype(np.float64)
        return [pics[i] for i in tour(d)]
    key = "tour" if all("tour" in p.extra for p in pics) else "hilbert"
    return sorted(pics, key=lambda p: p.extra[key])


def style_order(pics: list[Pic], styles: list[str], models: list[str]) -> list[Pic]:
    """Prompt → style → flow → model. Styles the order list does not know
    (candidates from a file) follow in the order they first appear."""
    rank: dict[str, int] = {BASELINE: -1}
    for s in styles:
        rank.setdefault(s, len(rank))
    for p in pics:
        rank.setdefault(p.style, len(rank))
    mrank: dict[str, int] = {}
    for m in models:
        mrank.setdefault(m, len(mrank))
    for p in pics:
        mrank.setdefault(p.model, len(mrank))
    frank: dict[str, int] = {}
    for p in pics:
        frank.setdefault(p.flow, len(frank))
    return sorted(pics, key=lambda p: (p.prompt, rank[p.style], frank[p.flow], mrank[p.model]))


def font(size: int) -> ImageFont.ImageFont:
    for f in ("/System/Library/Fonts/Helvetica.ttc",
              "/System/Library/Fonts/Supplemental/Arial.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def wrap(d: ImageDraw.ImageDraw, text: str, f, max_w: int) -> list[str]:
    lines: list[str] = []
    for word in text.split():
        if lines and d.textlength(lines[-1] + " " + word, font=f) <= max_w:
            lines[-1] += " " + word
        else:
            lines.append(word)
    return lines


def burn_label(canvas: Image.Image, label: tuple[str, str]) -> Image.Image:
    """Style (wrapped, larger) over model (smaller) on a dark rounded box in
    the upper part, below where TikTok and Shorts draw their tabs."""
    w, h = canvas.size
    style, model = label
    pad = round(w * 0.025)
    big, small = font(round(w * 0.042)), font(round(w * 0.03))
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rows = [(t, big) for t in wrap(d, style, big, w - 6 * pad)] if style else []
    if model:
        rows.append((model, small))
    sizes = [(d.textlength(t, font=f), f.getbbox("ÁÝgjy")[3]) for t, f in rows]
    gap = round(pad * 0.4)
    bw = max(s[0] for s in sizes) + 2 * pad
    bh = sum(s[1] for s in sizes) + gap * (len(rows) - 1) + 2 * pad
    x0, y0 = (w - bw) / 2, round(h * 0.12)
    d.rounded_rectangle((x0, y0, x0 + bw, y0 + bh), radius=pad, fill=(0, 0, 0, 150))
    y = y0 + pad
    for (t, f), (tw, th) in zip(rows, sizes):
        d.text(((w - tw) / 2, y), t, font=f,
               fill=(255, 255, 255, 255) if f is big else (220, 220, 220, 255))
        y += th + gap
    return Image.alpha_composite(canvas.convert("RGBA"), layer).convert("RGB")


def frame_of(p: Pic, w: int, h: int, fit: str, label: tuple[str, str] | None) -> np.ndarray:
    """One picture on a w×h canvas. `contain` keeps all of it over a blurred,
    darkened copy of itself (no black bars); `cover` crops to fill."""
    im = Image.open(p.path).convert("RGB")
    s_cover = max(w / im.width, h / im.height)
    if fit == "cover":
        big = im.resize((round(im.width * s_cover), round(im.height * s_cover)), Image.LANCZOS)
        x, y = (big.width - w) // 2, (big.height - h) // 2
        canvas = big.crop((x, y, x + w, y + h))
    else:
        bg = im.resize((max(1, round(im.width * s_cover / 8)), max(1, round(im.height * s_cover / 8))),
                       Image.BILINEAR).filter(ImageFilter.GaussianBlur(6))
        bg = bg.resize((round(im.width * s_cover), round(im.height * s_cover)), Image.BILINEAR)
        x, y = (bg.width - w) // 2, (bg.height - h) // 2
        canvas = Image.eval(bg.crop((x, y, x + w, y + h)), lambda v: int(v * 0.45))
        s = min(w / im.width, h / im.height)
        fg = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
        canvas.paste(fg, ((w - fg.width) // 2, (h - fg.height) // 2))
    if label:
        canvas = burn_label(canvas, label)
    return np.asarray(canvas)


def grid_layout(n: int, aspect: float, rw: int, rh: int, caption: int) -> tuple[int, int]:
    """Columns × rows for n pictures of width/height `aspect` in an rw×rh
    region, each tile losing `caption` px to its model name: the split that
    makes every picture the largest."""
    best, best_area = (1, n), -1.0
    for cols in range(1, n + 1):
        rows = -(-n // cols)
        tw, th = rw / cols, rh / rows - caption
        if th <= 0:
            continue
        pw = min(tw, th * aspect)
        if pw * pw / aspect > best_area:
            best, best_area = (cols, rows), pw * pw / aspect
    return best


def grid_frame(slide: list[Pic | None], slots: list[str], w: int, h: int,
               title: str, names: bool, layout: tuple[int, int], aspect: float) -> np.ndarray:
    """All models of one style on one frame. A model keeps its tile for the
    whole video (an empty tile where its picture is missing), so the eye
    compares styles, not positions. Title in a box below the TikTok/Shorts
    tabs; the grid stops above where they put the caption."""
    canvas = Image.new("RGB", (w, h), (16, 16, 18))
    d = ImageDraw.Draw(canvas)
    pad = round(w * 0.02)
    top = round(h * 0.085)
    if title:
        # The band is two lines tall on every slide, so the grid below it
        # never moves when a long style name wraps.
        f = font(round(w * 0.042))
        lines = wrap(d, title, f, w - 6 * pad)
        if len(lines) > 2:
            lines = [lines[0], " ".join(lines[1:])]
            while d.textlength(lines[1] + "…", font=f) > w - 6 * pad and " " in lines[1]:
                lines[1] = lines[1].rsplit(" ", 1)[0]
            lines[1] += "…"
        lh, gap = f.getbbox("ÁÝgjy")[3], round(pad * 0.4)
        band = 2 * lh + gap + 2 * pad
        bh = lh * len(lines) + gap * (len(lines) - 1) + 2 * pad
        y0 = top + (band - bh) // 2
        d.rounded_rectangle((pad, y0, w - pad, y0 + bh), radius=pad, fill=(40, 40, 44))
        y = y0 + pad
        for line in lines:
            d.text(((w - d.textlength(line, font=f)) / 2, y), line, font=f, fill=(255, 255, 255))
            y += lh + gap
        top += band + pad
    bottom = round(h * 0.88)
    cols, rows = layout
    small = font(round(w * 0.026))
    cap = small.getbbox("ÁÝgjy")[3] + pad // 2 if names else 0
    tw, th = (w - pad) / cols, (bottom - top) / rows
    # Every picture gets the same box (the run's aspect), the name right
    # under it, and the whole grid is centred in the free region.
    pw = min(tw - pad, (th - pad - cap) * aspect)
    ph = pw / aspect
    cell_h = ph + cap + pad
    y_start = top + ((bottom - top) - rows * cell_h) / 2
    for k, model in enumerate(slots):
        r, c = divmod(k, cols)
        x = pad / 2 + c * tw + (tw - pw) / 2
        y = y_start + r * cell_h + pad / 2
        p = slide[k]
        if p is not None:
            im = Image.open(p.path).convert("RGB")
            s_ = min(pw / im.width, ph / im.height)
            im = im.resize((max(1, round(im.width * s_)), max(1, round(im.height * s_))), Image.LANCZOS)
            canvas.paste(im, (round(x + (pw - im.width) / 2), round(y + (ph - im.height) / 2)))
        else:
            d.rectangle((x, y, x + pw, y + ph), outline=(60, 60, 64), width=2)
        if names:
            name = p.model_label if p is not None else model
            f, size = small, round(w * 0.026)
            while d.textlength(name, font=f) > tw - pad / 2 and size > 12:
                size -= 1
                f = font(size)
            d.text((pad / 2 + c * tw + (tw - d.textlength(name, font=f)) / 2, y + ph + pad / 4),
                   name, font=f, fill=(210, 210, 210) if p is not None else (110, 110, 110))
    return np.asarray(canvas)


def render(args, w: int, h: int, total: int, hold: float, n: int, frame) -> None:
    """Pipe the slides to ffmpeg: each holds `hold` video frames, the last
    `fade` share of them crossfading into the next."""
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
        i = min(int(k / hold), n - 1)
        if k == 0 or int((k - 1) / hold) != i:  # a new picture starts
            cur = nxt if nxt is not None else frame(i)
            nxt = frame(i + 1) if i + 1 < n else None
        out = cur
        phase = (k - i * hold) / hold  # 0..1 within this picture
        if nxt is not None and args.fade > 0 and phase > 1 - args.fade:
            a = (phase - (1 - args.fade)) / args.fade
            out = (cur * (1 - a) + nxt * a).astype(np.uint8)
        ff.stdin.write(np.ascontiguousarray(out).tobytes())
        if k and k % (args.fps * 10) == 0:
            print(f"  {k / total:4.0%}  ({time.time() - t0:.0f} s)", flush=True)
    ff.stdin.close()
    if ff.wait() != 0:
        sys.exit("ffmpeg skončil chybou")
    print(f"hotovo → {args.out}  ({time.time() - t0:.0f} s)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--set", type=Path, help="adresář packu (map.json)")
    src.add_argument("--run", type=Path, help="adresář běhu labu (build/lab/<id>)")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--where", action="append", default=[], help="key=value, opakovatelné")
    ap.add_argument("--order", choices=["tour", "style"],
                    help="tour = trasa mapy (výchozí u --set), style = styl po stylu přes "
                         "všechny modely (výchozí u --run)")
    ap.add_argument("--model-order", default="",
                    help="pořadí modelů uvnitř stylu, čárkami (jinak pořadí běhu)")
    ap.add_argument("--label", action="store_true", help="vypálit popisek „styl · model“")
    ap.add_argument("--grid", action="store_true",
                    help="jeden snímek na styl: obrázky všech modelů v mřížce (--rate = stylů/s)")
    ap.add_argument("--cols", type=int, default=0,
                    help="sloupců mřížky (řádky se dopočítají); 0 = vybrat podle velikosti obrázků")
    ap.add_argument("--rate", type=float, default=4, help="obrázků za vteřinu (výchozí 4)")
    ap.add_argument("--fade", type=float, default=0.4,
                    help="podíl času obrázku na prolínačku do dalšího, 0 = střih (výchozí 0.4)")
    ap.add_argument("--fps", type=int, default=30, help="snímků videa za vteřinu")
    ap.add_argument("--size", default="1080x1920")
    ap.add_argument("--fit", choices=["contain", "cover"], default="contain",
                    help="contain = celý obrázek na rozmazaném pozadí, cover = ořez na výšku")
    ap.add_argument("--max-seconds", type=float, default=0,
                    help="zkrátit na tuto délku rovnoměrným výběrem (0 = vše); u --order style "
                         "se vybírají celé styly, aby každý dostal všechny modely")
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
    order = args.order or ("style" if args.run or args.grid else "tour")
    if args.grid and order != "style":
        sys.exit("--grid skládá modely jednoho stylu, jde jen s --order style")
    if order == "tour" and args.run:
        sys.exit("--order tour potřebuje pack mapy (--set); z běhu labu jde jen --order style")

    if args.run:
        pics, styles, models = from_run(args.run)
        items: list = []
    else:
        pics, styles, items = from_pack(args.set)
        models = []
    where = parse_where(args.where)
    pics = [p for p in pics if all(p.get(k) in v for k, v in where.items())]
    if not pics:
        sys.exit("filtru neodpovídá žádný obrázek")

    if order == "style":
        if args.set:
            # A pack knows no picker order; its tour orders the styles, so the
            # step from one style to the next is a small one too.
            styles = list(dict.fromkeys(p.style for p in tour_order(pics, args.set, items, False)))
        models = [m for m in args.model_order.split(",") if m] + models
        pics = style_order(pics, styles, models)
    else:
        pics = tour_order(pics, args.set, items, replan=bool(where) and not args.no_replan)

    # A slide is what one stretch of the video shows: one picture, or with
    # --grid one style with every model.
    if args.grid:
        slots = list(dict.fromkeys(p.model for p in pics))
        groups: dict[tuple, dict[str, Pic]] = {}
        for p in pics:
            groups.setdefault((p.prompt, p.style, p.flow), {})[p.model] = p
        flows = {p.flow for p in pics}
        slides = [[g.get(m) for m in slots] for g in groups.values()]
        if args.max_seconds and len(slides) / args.rate > args.max_seconds:
            keep = max(1, int(args.max_seconds * args.rate))
            slides = [slides[round(i * (len(slides) - 1) / max(1, keep - 1))] for i in range(keep)]
        first = next(p for p in pics)
        with Image.open(first.path) as im0:
            aspect = im0.width / im0.height
        pad = round(w * 0.02)
        cap = (font(round(w * 0.026)).getbbox("ÁÝgjy")[3] + pad // 2) if args.label else 0
        title_h = (2 * font(round(w * 0.042)).getbbox("ÁÝgjy")[3] + round(pad * 0.4) + 3 * pad
                   if args.label else 0)
        if args.cols > 0:
            cols = min(args.cols, len(slots))
            layout = (cols, -(-len(slots) // cols))
        else:
            layout = grid_layout(len(slots), aspect, w - pad,
                                 round(h * 0.88) - round(h * 0.085) - title_h, cap + pad)

        def slide_title(sl: list[Pic | None]) -> str:
            p = next(x for x in sl if x is not None)
            return f"{p.label} · {p.flow}" if len(flows) > 1 else p.label

        def frame(i: int) -> np.ndarray:
            return grid_frame(slides[i], slots, w, h,
                              slide_title(slides[i]) if args.label else "", args.label, layout, aspect)

        hold = args.fps / args.rate
        total = round(hold * len(slides))
        print(f"{len(slides)} stylů × {len(slots)} modelů ({layout[0]}×{layout[1]}) · "
              f"{args.rate:g}/s · prolínačka {args.fade:g} · {total / args.fps:.1f} s · {w}×{h}",
              flush=True)
        render(args, w, h, total, hold, len(slides), frame)
        return

    if args.max_seconds and len(pics) / args.rate > args.max_seconds:
        keep = max(1, int(args.max_seconds * args.rate))
        if order == "style":
            groups: dict[tuple, list[Pic]] = {}
            for p in pics:
                groups.setdefault((p.prompt, p.style), []).append(p)
            gl = list(groups.values())
            per = max(len(g) for g in gl)
            ng = max(1, min(len(gl), keep // per))
            pics = [p for i in range(ng) for p in gl[round(i * (len(gl) - 1) / max(1, ng - 1))]]
        else:
            pics = [pics[round(i * (len(pics) - 1) / max(1, keep - 1))] for i in range(keep)]

    def label_of(p: Pic) -> tuple[str, str] | None:
        return (p.label, p.model_label) if args.label else None

    soft = sum(1 for p in pics if p.thumb)
    hold = args.fps / args.rate  # video frames per picture
    total = round(hold * len(pics))
    print(f"{len(pics)} obrázků · {order} · {args.rate:g}/s · prolínačka {args.fade:g} · "
          f"{total / args.fps:.1f} s · {w}×{h}"
          + (f" · {soft} jen z 384px náhledů" if soft else ""), flush=True)

    def frame(i: int) -> np.ndarray:
        return frame_of(pics[i], w, h, args.fit, label_of(pics[i]))

    render(args, w, h, total, hold, len(pics), frame)


if __name__ == "__main__":
    main()
