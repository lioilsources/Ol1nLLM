"""Step 2 of the StyleMap pipeline: how different two pictures look (plan §2.3).

    python perceptual.py --set build/stylemap/<set>

Writes `lpips.npy`, the LPIPS (AlexNet) distance between every two pictures of
the set. CLIP says which styles are related; this says how hard the cut between
two pictures is on the eye, which is what build_map.py smooths the grid and
plans the scrub route by.

LPIPS is a squared Euclidean distance in disguise — per layer, the unit-
normalised activations weighted by a learned non-negative weight per channel
and averaged over the picture. So every picture is embedded once and the whole
matrix is one Gram product, instead of N²/2 passes through the network.
"""

from __future__ import annotations

import argparse
import json
import time
import warnings
from pathlib import Path

import numpy as np
import torch
from PIL import Image


def load(path: str, size: tuple[int, int]) -> torch.Tensor:
    im = Image.open(path).convert("RGB").resize(size, Image.LANCZOS)
    return torch.from_numpy(np.asarray(im).copy()).permute(2, 0, 1).float() / 127.5 - 1


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", type=Path, required=True, help="directory with items.json")
    ap.add_argument("--size", type=int, default=160, help="longer side the pictures are compared at")
    ap.add_argument("--batch", type=int, default=64)
    ap.add_argument("--check", type=int, default=16,
                    help="pairs to verify against the reference implementation")
    args = ap.parse_args()

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")  # torchvision's `pretrained` deprecation
        import lpips

        net = lpips.LPIPS(net="alex", verbose=False).eval()
    dev = "mps" if torch.backends.mps.is_available() else "cuda" if torch.cuda.is_available() else "cpu"
    net = net.to(dev)

    paths = [it["path"] for it in json.loads((args.set / "items.json").read_text())["items"]]
    n = len(paths)
    # One shape for the whole set (one motif, one latent) — make_thumbs.py
    # makes the same assumption.
    w, h = Image.open(paths[0]).size
    s = args.size / max(w, h)
    size = (round(w * s), round(h * s))

    weights = [lin.model[-1].weight.detach().flatten().sqrt() for lin in net.lins]

    @torch.no_grad()
    def embed(x: torch.Tensor) -> torch.Tensor:
        outs = net.net.forward(net.scaling_layer(x))
        parts = []
        for f, wgt in zip(outs, weights):
            f = lpips.normalize_tensor(f) * wgt[None, :, None, None]
            parts.append(f.flatten(1) / (f.shape[2] * f.shape[3]) ** 0.5)
        return torch.cat(parts, dim=1)

    t0 = time.time()
    vecs: np.ndarray | None = None
    for i in range(0, n, args.batch):
        x = torch.stack([load(p, size) for p in paths[i:i + args.batch]]).to(dev)
        v = embed(x).cpu().numpy()
        if vecs is None:
            # Half precision: a few thousand pictures × ~150k dimensions.
            vecs = np.empty((n, v.shape[1]), dtype=np.float16)
        vecs[i:i + len(v)] = v
        if (i // args.batch) % 10 == 0:
            print(f"  LPIPS vlastnosti {i}/{n}", flush=True)
    assert vecs is not None
    print(f"vlastnosti: {time.time() - t0:.0f} s, {vecs.shape[1]} dimenzí při {size[0]}×{size[1]}")

    t0 = time.time()
    chunk = 256
    sq = np.array([float((vecs[i].astype(np.float32) ** 2).sum()) for i in range(n)], dtype=np.float32)
    d = np.empty((n, n), dtype=np.float32)
    for i in range(0, n, chunk):
        a = torch.from_numpy(vecs[i:i + chunk]).to(dev).float()
        for j in range(0, n, chunk):
            b = torch.from_numpy(vecs[j:j + chunk]).to(dev).float()
            d[i:i + chunk, j:j + chunk] = (a @ b.T).cpu().numpy()
    d = np.maximum(sq[:, None] + sq[None, :] - 2 * d, 0)
    d = (d + d.T) / 2
    np.fill_diagonal(d, 0)
    print(f"matice {n}×{n}: {time.time() - t0:.0f} s, průměr {d[np.triu_indices(n, 1)].mean():.4f}")

    if args.check and n > 1:
        rng = np.random.default_rng(0)
        worst = 0.0
        with torch.no_grad():
            for _ in range(args.check):
                i, j = rng.choice(n, 2, replace=False)
                ref = float(net(load(paths[i], size)[None].to(dev), load(paths[j], size)[None].to(dev)))
                worst = max(worst, abs(ref - float(d[i, j])))
        print(f"kontrola proti lpips na {args.check} párech: největší odchylka {worst:.5f}")

    np.save(args.set / "lpips.npy", d)
    print(f"hotovo → {args.set}/lpips.npy")


if __name__ == "__main__":
    main()
