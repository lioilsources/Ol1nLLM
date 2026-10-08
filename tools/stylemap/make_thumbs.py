"""Step 3 of the StyleMap pipeline: the pictures the widget shows (plan §4.3).

    python make_thumbs.py --set build/stylemap/<set>

Writes `atlas.webp` — the whole map as one image, one small cell per picture,
which the widget draws as the mosaic and crops as an instant placeholder — and
`t/<i>.webp`, the preview shown for the cell under the finger. Then refreshes
`index.json` one level up, the list of packs a server offers.
"""

from __future__ import annotations

import argparse
import json
from multiprocessing import Pool
from pathlib import Path

from PIL import Image

CELL_W = 32
THUMB_W = 384


def _one(job: tuple[str, str, tuple[int, int], tuple[int, int]]) -> tuple[bytes, tuple[int, int]]:
    src, dst, cell, thumb = job
    im = Image.open(src).convert("RGB")
    im.resize(thumb, Image.LANCZOS).save(dst, "WEBP", quality=80, method=4)
    small = im.resize(cell, Image.LANCZOS)
    return small.tobytes(), small.size


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", type=Path, required=True)
    ap.add_argument("--jobs", type=int, default=6)
    args = ap.parse_args()

    man_path = args.set / "map.json"
    man = json.loads(man_path.read_text())
    paths = {it["id"]: it["path"] for it in json.loads((args.set / "items.json").read_text())["items"]}

    # Every picture of a set has the same shape (one motif, one latent), so
    # the first one decides the cell.
    w, h = Image.open(paths[man["images"][0]["id"]]).size
    cell = (CELL_W, round(CELL_W * h / w))
    # Never larger than the source: a set read from the gallery's thumbnails
    # is ~260 px wide, and upscaling it would only make the files bigger.
    tw = min(THUMB_W, w)
    thumb = (tw, round(tw * h / w))
    cols, rows = man["grid"]

    (args.set / "t").mkdir(exist_ok=True)
    jobs = [
        (paths[im["id"]], str(args.set / "t" / f"{im['i']}.webp"), cell, thumb)
        for im in man["images"]
    ]
    atlas = Image.new("RGB", (cols * cell[0], rows * cell[1]), (18, 18, 20))
    with Pool(args.jobs) as pool:
        for k, (raw, size) in enumerate(pool.imap(_one, jobs, chunksize=16)):
            cx, cy = man["images"][k]["cell"]
            atlas.paste(Image.frombytes("RGB", size, raw), (cx * cell[0], cy * cell[1]))
            if k % 500 == 0:
                print(f"  náhledy {k}/{len(jobs)}", flush=True)
    atlas.save(args.set / "atlas.webp", "WEBP", quality=88, method=4)

    man["cell"] = list(cell)
    man["aspect"] = round(w / h, 4)
    man["atlas"] = "atlas.webp"
    man["thumbs"] = "t/{i}.webp"
    man["thumbSize"] = list(thumb)
    man_path.write_text(json.dumps(man, ensure_ascii=False, separators=(",", ":")))

    packs = []
    for p in sorted(args.set.parent.glob("*/map.json")):
        m = json.loads(p.read_text())
        if "atlas" not in m or p.parent.name.startswith("_"):
            continue  # built but not rendered yet, or a scratch set
        packs.append({
            "id": m["id"], "title": m["title"], "n": m["n"],
            "aspect": m["aspect"], "atlas": f"{m['id']}/{m['atlas']}",
        })
    (args.set.parent / "index.json").write_text(json.dumps({"packs": packs}, ensure_ascii=False))
    size = sum(f.stat().st_size for f in (args.set / "t").iterdir()) / 1e6
    print(f"hotovo → atlas {atlas.size[0]}×{atlas.size[1]}, náhledy {size:.0f} MB, "
          f"index: {len(packs)} sad")


if __name__ == "__main__":
    main()
