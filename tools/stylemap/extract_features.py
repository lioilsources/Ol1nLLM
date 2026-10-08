"""Step 1 of the StyleMap pipeline: per-image features (plan §2.1–2.2).

    python extract_features.py --run build/lab/<id> --out build/stylemap/<set>

Writes `features.npz` (cheap colour/texture statistics, the CLIP embedding,
zero-shot style axes, medium probabilities) and `items.json` (id, label, tag).
Values are raw; build_map.py normalises them against the whole set.
"""

from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path

import cv2
import numpy as np
import torch
from PIL import Image

from common import (
    CHEAP_KEYS, DEFAULT_GALLERY, MEDIA, REPO_ROOT, ZS_AXES, load_gallery, load_run,
)


def cheap_features(path: Path) -> list[float]:
    """Interpretable statistics of one image, in CHEAP_KEYS order."""
    bgr = cv2.imread(str(path), cv2.IMREAD_COLOR)
    h, w = bgr.shape[:2]
    s = 256 / max(h, w)
    bgr = cv2.resize(bgr, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA)

    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    L = lab[..., 0] * (100 / 255)
    a, b = lab[..., 1] - 128, lab[..., 2] - 128
    chroma = np.sqrt(a * a + b * b)

    # Circular mean of hue, weighted by how much colour a pixel actually has;
    # the length of the resultant says whether the palette has one hue at all.
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    theta = hsv[..., 0] * (math.pi / 90)
    wgt = (hsv[..., 1] / 255) * (hsv[..., 2] / 255)
    sx, sy, sw = float((wgt * np.cos(theta)).sum()), float((wgt * np.sin(theta)).sum()), float(wgt.sum()) + 1e-6
    hue = (math.atan2(sy, sx) / (2 * math.pi)) % 1.0
    hue_conc = math.hypot(sx, sy) / sw

    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    edge = float(cv2.Canny(gray, 100, 200).mean() / 255)
    sharp = math.log1p(float(cv2.Laplacian(gray, cv2.CV_32F).var()))

    # Flat cel shading needs few colours to cover the picture, a gradient many:
    # how many 4-bit-per-channel bins hold 90 % of the pixels.
    q = (bgr >> 4).reshape(-1, 3).astype(np.int32)
    counts = np.bincount(q[:, 0] << 8 | q[:, 1] << 4 | q[:, 2], minlength=4096)
    cum = np.cumsum(np.sort(counts)[::-1])
    colors = float(np.searchsorted(cum, 0.9 * cum[-1]) + 1)

    # Hasler–Süsstrunk colourfulness.
    B, G, R = (bgr[..., i].astype(np.float32) for i in range(3))
    rg, yb = R - G, 0.5 * (R + G) - B
    colorful = math.hypot(rg.std(), yb.std()) + 0.3 * math.hypot(rg.mean(), yb.mean())

    hist = np.bincount(gray.reshape(-1), minlength=256).astype(np.float64)
    p = hist[hist > 0] / hist.sum()
    entropy = float(-(p * np.log2(p)).sum())

    # What a small blur removes: film grain, noise, halftone dots.
    g32 = gray.astype(np.float32)
    grain = float(np.abs(g32 - cv2.GaussianBlur(g32, (0, 0), 1.0)).mean())

    vals = dict(
        lum=float(L.mean()), contrast=float(L.std()), sat=float(chroma.mean()),
        hue=hue, hue_conc=hue_conc, warm=float(b.mean()), tint=float(a.mean()),
        edge=edge, sharp=sharp, colors=colors, colorful=colorful,
        entropy=entropy, grain=grain,
    )
    return [vals[k] for k in CHEAP_KEYS]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, help="lab run directory")
    ap.add_argument("--session", action="append", default=[],
                    help="FINETUNE gallery session id; repeat for several")
    ap.add_argument("--where", action="append", default=[], metavar="KEY=VALUE",
                    help="gallery filter, as /api/images takes it (score=1, model=noobai-xl)")
    ap.add_argument("--gallery", default=DEFAULT_GALLERY)
    ap.add_argument("--full", action="store_true",
                    help="download the originals instead of the gallery's 384 px thumbnails")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--tag-regex", default=None,
                    help="pull the prompt fragment out of the prompt text (old runs)")
    ap.add_argument("--model", default="ViT-L-14-quickgelu")
    ap.add_argument("--pretrained", default="openai")
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--limit", type=int, default=None)
    args = ap.parse_args()

    if bool(args.run) == bool(args.session):
        raise SystemExit("zadej právě jeden zdroj: --run DIR, nebo --session ID [--session ID …]")
    if args.run:
        source = str(args.run)
        items = load_run(args.run, args.tag_regex, args.limit)
    else:
        where = dict(w.split("=", 1) for w in args.where)
        source = f"{args.gallery} · sessions {', '.join(args.session)}"
        if where:
            source += " · " + ", ".join(f"{k}={v}" for k, v in where.items())
        # One cache for all sets: blobs are content-addressed, so a picture two
        # sets share is downloaded once.
        items = load_gallery(
            args.gallery, args.session, where, REPO_ROOT / "build" / "stylemap" / "_blobs",
            args.tag_regex, args.full, args.limit,
        )
    if not items:
        raise SystemExit(f"{source}: žádné obrázky")
    args.out.mkdir(parents=True, exist_ok=True)
    print(f"{len(items)} obrázků z {source}", flush=True)

    t0 = time.time()
    cheap = np.array([cheap_features(it.path) for it in items], dtype=np.float32)
    print(f"levné vlastnosti: {time.time() - t0:.0f} s", flush=True)

    import open_clip

    dev = "mps" if torch.backends.mps.is_available() else "cuda" if torch.cuda.is_available() else "cpu"
    model, _, preprocess = open_clip.create_model_and_transforms(args.model, pretrained=args.pretrained)
    model = model.to(dev).eval()
    tok = open_clip.get_tokenizer(args.model)

    def text(prompts: list[str]) -> torch.Tensor:
        with torch.no_grad():
            e = model.encode_text(tok(prompts).to(dev))
        return torch.nn.functional.normalize(e.float(), dim=-1)

    embs = []
    t0 = time.time()
    with torch.no_grad():
        for i in range(0, len(items), args.batch):
            batch = torch.stack([
                preprocess(Image.open(it.path).convert("RGB")) for it in items[i:i + args.batch]
            ]).to(dev)
            e = torch.nn.functional.normalize(model.encode_image(batch).float(), dim=-1)
            embs.append(e.cpu())
            if (i // args.batch) % 10 == 0:
                print(f"  clip {i + len(batch)}/{len(items)}  {time.time() - t0:.0f} s", flush=True)
    emb = torch.cat(embs)

    a = text([p for _, p, _ in ZS_AXES]).cpu()
    b = text([p for _, _, p in ZS_AXES]).cpu()
    axes = (emb @ a.T - emb @ b.T).numpy()
    media = torch.softmax(100 * emb @ text([f"a {m}" for m in MEDIA]).cpu().T, dim=-1).numpy()

    np.savez_compressed(
        args.out / "features.npz",
        cheap=cheap, clip=emb.numpy().astype(np.float32),
        axes=axes.astype(np.float32), media=media.astype(np.float32),
    )
    (args.out / "items.json").write_text(json.dumps({
        "source": source,
        "clip": f"{args.model}/{args.pretrained}",
        "items": [
            {"id": it.id, "path": str(it.path), "label": it.label, "tag": it.tag,
             "style": it.style, "model": it.model}
            for it in items
        ],
    }, ensure_ascii=False))
    print(f"hotovo → {args.out}/features.npz", flush=True)


if __name__ == "__main__":
    main()
