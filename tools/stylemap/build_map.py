"""Step 2 of the StyleMap pipeline: place every image on a grid (plan §3).

    python build_map.py --set build/stylemap/<set> --title "NoobAI — umělci"

Reads `features.npz` + `items.json`, writes `map.json`: one grid cell per
image, laid out so that neighbours on the grid are neighbours in style, plus a
1D route over the grid for scrubbing and the normalised features per image.

With `tags.json` (tag_images.py) every picture also carries what a VLM said
about it, and the pack lists the facets the widget filters by. Without it the
only facets are the model and CLIP's guess at the medium.

With `lpips.npy` next to them (perceptual.py) the grid is also smoothed for
the eye — neighbours swapped while that makes the cuts between them softer —
and the pictures get a second route, `tour`: the order in which playing them
one after another changes the least.
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

from common import CHEAP_KEYS, FACETS, MEDIA, ZS_AXES

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


def neighbour_lpips(grid: np.ndarray, d: np.ndarray) -> float:
    """Mean LPIPS between images in edge-adjacent cells."""
    out: list[np.ndarray] = []
    for a, b in ((grid[:, :-1], grid[:, 1:]), (grid[:-1, :], grid[1:, :])):
        ok = (a >= 0) & (b >= 0)
        out.append(d[a[ok], b[ok]])
    return float(np.concatenate(out).mean())


def refine(grid: np.ndarray, d: np.ndarray, rng: np.random.Generator,
           reach: int, sweeps: int = 200) -> tuple[np.ndarray, int]:
    """Swap nearby pictures while that lowers the LPIPS to their neighbours.

    Only pictures at most `reach` cells apart trade places, so the map keeps
    the shape UMAP gave it and only the order inside a neighbourhood changes.
    Empty cells stay where they are — moved freely they would drift into the
    middle of the map, where a hole saves the most edges.
    """
    g = grid.copy()
    h, w = g.shape

    def local(y: int, x: int, k: int) -> float:
        s = 0.0
        if y > 0 and (m := g[y - 1, x]) >= 0:
            s += d[k, m]
        if y < h - 1 and (m := g[y + 1, x]) >= 0:
            s += d[k, m]
        if x > 0 and (m := g[y, x - 1]) >= 0:
            s += d[k, m]
        if x < w - 1 and (m := g[y, x + 1]) >= 0:
            s += d[k, m]
        return s

    # Each unordered pair of cells once: offsets in the lower half-plane.
    offsets = [(dy, dx) for dy in range(reach + 1) for dx in range(-reach, reach + 1)
               if dy > 0 or dx > 0]
    pairs = [(y, x, y + dy, x + dx)
             for y in range(h) for x in range(w) for dy, dx in offsets
             if y + dy < h and 0 <= x + dx < w]
    swaps = 0
    for _ in range(sweeps):
        done = 0
        for k in rng.permutation(len(pairs)):
            y, x, y2, x2 = pairs[k]
            a, b = g[y, x], g[y2, x2]
            if a < 0 or b < 0:
                continue
            before = local(y, x, a) + local(y2, x2, b)
            g[y, x], g[y2, x2] = b, a
            if local(y, x, b) + local(y2, x2, a) < before - 1e-7:
                done += 1
            else:
                g[y, x], g[y2, x2] = a, b
        swaps += done
        if done == 0:
            break
    return g, swaps


def tour(d: np.ndarray, near: int = 12, passes: int = 60) -> np.ndarray:
    """An order of the pictures with small LPIPS steps: nearest neighbour,
    then 2-opt, as a cycle cut open at its longest step.

    2-opt only tries to reconnect a picture to one of its `near` nearest —
    an edge to anything farther is never an improvement worth the search.
    """
    n = len(d)
    if n < 4:
        return np.arange(n)
    left = np.ones(n, dtype=bool)
    order = np.empty(n, dtype=int)
    cur = int(d.sum(1).argmax())  # start at the outlier, it has to go somewhere
    for i in range(n):
        order[i] = cur
        left[cur] = False
        if i < n - 1:
            cur = int(np.where(left, d[cur], np.inf).argmin())

    close = np.argsort(d, axis=1)[:, 1:near + 1]
    pos = np.empty(n, dtype=int)
    pos[order] = np.arange(n)
    for _ in range(passes):
        improved = False
        for i in range(n):
            a, b = order[i], order[(i + 1) % n]
            dab = d[a, b]
            for c in close[a]:
                dac = d[a, c]
                if dac >= dab:
                    break
                j = pos[c]
                e = order[(j + 1) % n]
                if d[b, e] + dac - dab - d[c, e] < -1e-7:
                    # Drop a–b and c–e, join a–c and b–e: the stretch between
                    # them runs the other way round.
                    lo, hi = (i + 1, j) if i < j else (j + 1, i)
                    order[lo:hi + 1] = order[lo:hi + 1][::-1]
                    pos[order[lo:hi + 1]] = np.arange(lo, hi + 1)
                    improved = True
                    break
        if not improved:
            break
    steps = d[order, np.roll(order, -1)]
    return np.roll(order, -(int(steps.argmax()) + 1))


def step_mean(order: np.ndarray, d: np.ndarray) -> float:
    return float(d[order[:-1], order[1:]].mean())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", type=Path, required=True, help="directory with features.npz")
    ap.add_argument("--reach", type=int, default=2,
                    help="how many cells apart two pictures may trade places (0 = nech mřížku být)")
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

    stats = {"neighbourDistance": round(smooth, 4), "randomDistance": round(rand, 4)}

    lp_path = args.set / "lpips.npy"
    lp = np.load(lp_path) if lp_path.exists() else None
    if lp is not None and lp.shape != (n, n):
        raise SystemExit(f"{lp_path} je pro jinou sadu ({lp.shape[0]} obrázků, tady {n}) — "
                         "pusť znovu perceptual.py")
    if lp is None:
        print("lpips.npy chybí — mřížka zůstává podle CLIP a trasa je jen Hilbertova")
    else:
        before = neighbour_lpips(grid, lp)
        lp_rand = neighbour_lpips(shuffled.reshape(g, g), lp)
        stats |= {"lpipsUnrefined": round(before, 4), "lpipsRandom": round(lp_rand, 4)}
        if args.reach > 0:
            t0 = time.time()
            grid, swaps = refine(grid, lp, rng, args.reach)
            cell_of[grid[grid >= 0]] = np.flatnonzero(grid.ravel() >= 0)
            after, smooth = neighbour_lpips(grid, lp), neighbour_distance(grid, emb)
            stats["neighbourDistance"] = round(smooth, 4)
            print(f"LPIPS sousedů: {before:.4f} → {after:.4f} ({after / before - 1:+.0%}; "
                  f"náhodně {lp_rand:.4f}), {swaps} prohození, {time.time() - t0:.0f} s; "
                  f"CLIP sousedů teď {smooth:.4f} (poměr {smooth / rand:.2f})")
            before = after
        stats["lpipsNeighbour"] = round(before, 4)

    route = {c: i for i, c in enumerate(gilbert(g, g))}
    order = sorted(range(n), key=lambda i: route[(cell_of[i] % g, cell_of[i] // g)])
    hilbert = np.empty(n, dtype=int)
    hilbert[order] = np.arange(n)

    tour_pos = None
    if lp is not None:
        t0 = time.time()
        best = tour(lp)
        tour_pos = np.empty(n, dtype=int)
        tour_pos[best] = np.arange(n)
        steps = {"stepHilbert": step_mean(np.array(order), lp), "stepTour": step_mean(best, lp),
                 "stepRandom": step_mean(rng.permutation(n), lp)}
        stats |= {k_: round(v, 4) for k_, v in steps.items()}
        print(f"krok trasy (LPIPS): Hilbert {steps['stepHilbert']:.4f}, "
              f"TSP {steps['stepTour']:.4f}, náhodně {steps['stepRandom']:.4f} "
              f"({time.time() - t0:.0f} s)")

    feats = np.concatenate([unit(f["cheap"]), unit(f["axes"])], axis=1)
    keys = CHEAP_KEYS + [k_ for k_, _, _ in ZS_AXES]
    hue_col = keys.index("hue")
    feats[:, hue_col] = f["cheap"][:, CHEAP_KEYS.index("hue")]  # an angle, not a range

    medium = f["media"].argmax(1)

    # What the widget filters by. The model and the medium are known for every
    # picture; the rest only where the VLM has answered (a set may be tagged
    # in part — its window is short).
    tags_path = args.set / "tags.json"
    vlm = json.loads(tags_path.read_text()) if tags_path.exists() else {}
    tags: list[dict[str, str]] = []
    words: list[list[str]] = []
    for i, it in enumerate(items):
        got = vlm.get(it["id"]) or {}
        t = {"medium": MEDIA[medium[i]], **{k_: got[k_] for k_ in FACETS if k_ in got}}
        if it.get("model"):
            t["model"] = it["model"]
        tags.append(t)
        words.append(got.get("words") or [])
    facets = []
    # Model ids get their names in the app, which owns that registry.
    for key, (label, names) in {"model": ("Model", {}), **FACETS}.items():
        counts: dict[str, int] = {}
        for t in tags:
            if key in t:
                counts[t[key]] = counts.get(t[key], 0) + 1
        if len(counts) < 2:
            continue  # nothing to choose between
        facets.append({"key": key, "label": label, "values": [
            {"id": v, "label": names.get(v, v), "n": c}
            for v, c in sorted(counts.items(), key=lambda vc: -vc[1])
        ]})
    print(f"tagy z VLM: {len(vlm)}/{n} obrázků; fasety: "
          + ", ".join(f"{fc['label']} ({len(fc['values'])})" for fc in facets))
    clusters = []
    for c in range(cluster.max() + 1):
        idx = np.flatnonzero(cluster == c)
        centre = red[idx].mean(0)
        medoid = idx[np.argmin(((red[idx] - centre) ** 2).sum(1))]
        top = MEDIA.index(max(MEDIA, key=lambda m: sum(tags[j]["medium"] == m for j in idx)))
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
        "facets": facets,
        "stats": stats,
        "images": [
            {
                "i": i, "id": it["id"], "label": it["label"], "tag": it["tag"],
                **{k: it[k] for k in ("style", "model") if it.get(k)},
                "cell": [int(cell_of[i] % g), int(cell_of[i] // g)],
                "umap": [round(float(v), 4) for v in xy[i]],
                "cluster": int(cluster[i]),
                "hilbert": int(hilbert[i]),
                **({} if tour_pos is None else {"tour": int(tour_pos[i])}),
                "medium": MEDIA[medium[i]],
                "tags": tags[i],
                **({"words": words[i]} if words[i] else {}),
                "f": [round(float(v), 3) for v in feats[i]],
            }
            for i, it in enumerate(items)
        ],
    }
    (args.set / "map.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    print(f"hotovo → {args.set}/map.json")


if __name__ == "__main__":
    main()
