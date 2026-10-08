"""Step 2 of the StyleMap pipeline: place every image on a grid (plan §3).

    python build_map.py --set build/stylemap/<set> --title "NoobAI — umělci"

Reads `features.npz` + `items.json`, writes `map.json`: one grid cell per
image, laid out so that neighbours on the grid are neighbours in style, plus a
1D route over the grid for scrubbing and the normalised features per image.
"""

from __future__ import annotations

import argparse
import colorsys
import json
import time
from pathlib import Path

import numpy as np
from scipy.optimize import linear_sum_assignment
from scipy.spatial.distance import cdist
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA

from common import CHEAP_KEYS, MEDIA, ZS_AXES

# What the widget prints on an axis: low end ↔ high end.
AXIS_LABELS = {
    "lum": "tmavý ↔ světlý",
    "contrast": "plochý ↔ kontrastní",
    "sat": "šedý ↔ sytý",
    "hue": "odstín",
    "hue_conc": "pestrý ↔ jednobarevný",
    "warm": "studený ↔ teplý",
    "tint": "do zelena ↔ do červena",
    "edge": "malba ↔ linka",
    "sharp": "měkký ↔ ostrý",
    "colors": "plošné barvy ↔ přechody",
    "colorful": "tlumený ↔ barevný",
    "entropy": "jednoduchý tón ↔ bohatý tón",
    "grain": "hladký ↔ zrnitý",
    "photo": "kresba ↔ fotka",
    "real": "stylizace ↔ realismus",
    "anime": "západní komiks ↔ anime",
    "paint": "grafika ↔ malba",
    "render3d": "2D ↔ 3D",
    "sketch": "dotažené ↔ skica",
    "vintage": "moderní ↔ retro",
    "dark": "veselý ↔ temný",
    "minimal": "detailní ↔ minimální",
}


def unit(x: np.ndarray) -> np.ndarray:
    """Columns squeezed to 0–1 between their 2nd and 98th percentile.

    Zero-shot scores are only meaningful relative to the set, and one outlier
    must not flatten everyone else into a corner.
    """
    lo, hi = np.percentile(x, [2, 98], axis=0)
    return np.clip((x - lo) / np.maximum(hi - lo, 1e-9), 0, 1)


def gilbert(w: int, h: int) -> list[tuple[int, int]]:
    """A Hilbert-like curve through every cell of a w×h grid, any size.

    Consecutive cells always share an edge, which is the point: scrubbing
    along it never jumps across the map. (Generalised Hilbert curve, J. Červený.)
    """
    out: list[tuple[int, int]] = []

    def sgn(v: int) -> int:
        return (v > 0) - (v < 0)

    def go(x: int, y: int, ax: int, ay: int, bx: int, by: int) -> None:
        w_, h_ = abs(ax + ay), abs(bx + by)
        dax, day, dbx, dby = sgn(ax), sgn(ay), sgn(bx), sgn(by)
        if h_ == 1:
            for _ in range(w_):
                out.append((x, y))
                x, y = x + dax, y + day
            return
        if w_ == 1:
            for _ in range(h_):
                out.append((x, y))
                x, y = x + dbx, y + dby
            return
        ax2, ay2, bx2, by2 = ax // 2, ay // 2, bx // 2, by // 2
        w2, h2 = abs(ax2 + ay2), abs(bx2 + by2)
        if 2 * w_ > 3 * h_:
            if w2 % 2 and w_ > 2:
                ax2, ay2 = ax2 + dax, ay2 + day
            go(x, y, ax2, ay2, bx, by)
            go(x + ax2, y + ay2, ax - ax2, ay - ay2, bx, by)
        else:
            if h2 % 2 and h_ > 2:
                bx2, by2 = bx2 + dbx, by2 + dby
            go(x, y, bx2, by2, ax2, ay2)
            go(x + bx2, y + by2, ax, ay, bx - bx2, by - by2)
            go(x + (ax - dax) + (bx2 - dbx), y + (ay - day) + (by2 - dby),
               -bx2, -by2, -(ax - ax2), -(ay - ay2))

    if w >= h:
        go(0, 0, w, 0, 0, h)
    else:
        go(0, 0, 0, h, w, 0)
    return out


def neighbour_distance(grid: np.ndarray, emb: np.ndarray) -> float:
    """Mean cosine distance between images in edge-adjacent cells."""
    d: list[np.ndarray] = []
    for a, b in ((grid[:, :-1], grid[:, 1:]), (grid[:-1, :], grid[1:, :])):
        ok = (a >= 0) & (b >= 0)
        d.append(1 - np.einsum("ij,ij->i", emb[a[ok]], emb[b[ok]]))
    return float(np.concatenate(d).mean())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", type=Path, required=True, help="directory with features.npz")
    ap.add_argument("--title", default=None)
    ap.add_argument("--clusters", type=int, default=0, help="0 = podle velikosti sady")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    f = np.load(args.set / "features.npz")
    meta = json.loads((args.set / "items.json").read_text())
    items = meta["items"]
    emb = f["clip"].astype(np.float64)
    n = len(items)

    pca = PCA(n_components=min(50, n - 1), random_state=args.seed).fit(emb)
    red = pca.transform(emb)
    cum = np.cumsum(pca.explained_variance_ratio_)
    # How many dimensions the style space really has — the reason a 2D map
    # can only ever show neighbourhood, not axes.
    def dims(p: float) -> str:
        return str(int(np.searchsorted(cum, p) + 1)) if cum[-1] >= p else f"víc než {len(cum)}"

    print(f"PCA: 50 % rozptylu v {dims(0.5)} dimenzích, 80 % v {dims(0.8)} "
          f"(prvních {len(cum)} drží {cum[-1]:.0%})")

    import umap  # slow import, after the cheap checks

    t0 = time.time()
    xy = umap.UMAP(
        n_neighbors=min(20, n - 1), min_dist=0.05, metric="cosine",
        random_state=args.seed,
    ).fit_transform(red)
    xy = (xy - xy.min(0)) / np.maximum(xy.max(0) - xy.min(0), 1e-9)
    print(f"UMAP: {time.time() - t0:.0f} s")

    k = args.clusters or int(np.clip(round((n / 8) ** 0.5), 2, 30))
    cluster = KMeans(n_clusters=min(k, n), n_init=4, random_state=args.seed).fit_predict(red)

    # One cell per image, every image as close to its UMAP position as the
    # grid allows. Spare cells stay empty and fall where the map is sparse.
    g = int(np.ceil(np.sqrt(n)))
    cx, cy = np.meshgrid((np.arange(g) + 0.5) / g, (np.arange(g) + 0.5) / g)
    cells = np.stack([cx.ravel(), cy.ravel()], axis=1)
    t0 = time.time()
    rows, cols = linear_sum_assignment(cdist(xy, cells, "sqeuclidean"))
    cell_of = np.empty(n, dtype=int)
    cell_of[rows] = cols
    grid = np.full(g * g, -1, dtype=int)
    grid[cell_of] = np.arange(n)
    grid = grid.reshape(g, g)
    print(f"mřížka {g}×{g}: {time.time() - t0:.0f} s, prázdných buněk {g * g - n}")

    rng = np.random.default_rng(args.seed)
    shuffled = np.full(g * g, -1, dtype=int)
    shuffled[rng.permutation(g * g)[:n]] = np.arange(n)
    smooth, rand = neighbour_distance(grid, emb), neighbour_distance(shuffled.reshape(g, g), emb)
    print(f"vzdálenost sousedů: {smooth:.4f} (náhodné rozmístění {rand:.4f}, "
          f"poměr {smooth / rand:.2f})")

    route = {c: i for i, c in enumerate(gilbert(g, g))}
    order = sorted(range(n), key=lambda i: route[(cell_of[i] % g, cell_of[i] // g)])
    hilbert = np.empty(n, dtype=int)
    hilbert[order] = np.arange(n)

    feats = np.concatenate([unit(f["cheap"]), unit(f["axes"])], axis=1)
    keys = CHEAP_KEYS + [k_ for k_, _, _ in ZS_AXES]
    hue_col = keys.index("hue")
    feats[:, hue_col] = f["cheap"][:, CHEAP_KEYS.index("hue")]  # an angle, not a range

    medium = f["media"].argmax(1)
    clusters = []
    for c in range(cluster.max() + 1):
        idx = np.flatnonzero(cluster == c)
        centre = red[idx].mean(0)
        medoid = idx[np.argmin(((red[idx] - centre) ** 2).sum(1))]
        top = np.bincount(medium[idx], minlength=len(MEDIA)).argmax()
        r, gr, b = colorsys.hsv_to_rgb((c * 0.618034) % 1.0, 0.55, 0.95)
        clusters.append({
            "id": c, "size": int(len(idx)), "medoid": int(medoid),
            "label": f"{MEDIA[top]} · {items[medoid]['label']}",
            "color": f"#{round(r * 255):02x}{round(gr * 255):02x}{round(b * 255):02x}",
        })

    out = {
        "version": 1,
        "id": args.set.name,
        "title": args.title or args.set.name,
        "source": meta.get("source") or meta.get("run", ""),
        "n": n,
        "grid": [g, g],
        "axes": [{"key": k_, "label": AXIS_LABELS[k_]} for k_ in keys],
        "clusters": clusters,
        "stats": {"neighbourDistance": round(smooth, 4), "randomDistance": round(rand, 4)},
        "images": [
            {
                "i": i, "id": it["id"], "label": it["label"], "tag": it["tag"],
                **{k: it[k] for k in ("style", "model") if it.get(k)},
                "cell": [int(cell_of[i] % g), int(cell_of[i] // g)],
                "umap": [round(float(v), 4) for v in xy[i]],
                "cluster": int(cluster[i]),
                "hilbert": int(hilbert[i]),
                "medium": MEDIA[medium[i]],
                "f": [round(float(v), 3) for v in feats[i]],
            }
            for i, it in enumerate(items)
        ],
    }
    (args.set / "map.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    print(f"hotovo → {args.set}/map.json")


if __name__ == "__main__":
    main()
