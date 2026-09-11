#!/usr/bin/env python3
"""vidbench — identita dvou lidí ve videu, na stupnici facebenche.

Běží na SPARKu vedle ComfyUI (sync.sh to tam nakopíruje):

    vidbench.py score <klip.mp4> --refs ref_a.png,ref_b.png [--every 2]
    vidbench.py summary <run_dir/frames.csv>

Proč nestačí `bench.py`: ten bere v obrázku **největší** detekovaný obličej
(`bench.py:53-54`). U dvojice by tedy měřil jednoho člověka, a podle velikosti
bboxu nedeterministicky jednou A a jednou B. Tady se doplňují dvě věci, které
`bench.py` neumí — čtení po snímcích a **párování detekcí na osoby** — zatímco
embedding i podobnost se importují z `bench.py`, aby stupnice zůstala jedna
(antelopev2, kosinus znovu normalizovaných embeddingů; 1.0 táž tvář, ~0.6
stejná osoba, < 0.4 cizí).

Párování je **prostorové, ne podle podobnosti**: obličeje se skládají do stop
(tracků) přes IoU se snímkem předtím, a teprve celá stopa se jako celek
přiřadí referenci podle průměrného embeddingu. Kdyby se každý snímek přiřadil
zvlášť „k té referenci, které je podobnější", vybíralo by se maximum z dvojice
a skóre by se samo nafouklo.

Okludované snímky **nerozhodují o pass/fail** (polibek, profil, zavřené oči
srážejí skóre z důvodů, které nejsou selhání identity). Bez masky z preprocesu
se čistota odhaduje z detekce: `det_score`, |yaw| a velikost obličeje. Když
pipeline umí dodat okluzní mapu, dá se předat `--clean-frames` a odhad se
nepoužije.

Gate je **p10 čistých snímků**, ne minimum — a práh patří kalibrovat per akce
(`kiss` má strukturálně nižší skóre než `gaze`). Proto se `--action` zapisuje
do CSV: z naměřených běhů se prahy odvodí, nevymýšlejí se dopředu.
"""
import argparse, csv, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bench import analyser, sim  # noqa: E402  jádro facebenche = společná stupnice

MIN_DET = 0.55       # pod tím je detekce nejistá — nepočítat do gate
MAX_YAW = 45.0       # stupně; extrémní profil není selhání identity
MIN_FACE = 48        # px kratší strany bboxu; menší tvář ArcFace nepřečte
IOU_GAP = 6          # kolik snímků smí stopa vypadnout a pořád pokračovat


# ---------------------------------------------------------------- detekce

def detect(frame):
    """Všechny obličeje ve snímku (ne jen největší) i s tím, co rozhoduje
    o čistotě: skóre detektoru, yaw a velikost."""
    import numpy as np
    out = []
    for f in analyser().get(frame):
        x0, y0, x1, y1 = f.bbox
        e = f.normed_embedding
        out.append({
            "bbox": (float(x0), float(y0), float(x1), float(y1)),
            "emb": e / np.linalg.norm(e),
            "det": float(f.det_score),
            "yaw": float(f.pose[1]) if getattr(f, "pose", None) is not None else 0.0,
            "size": float(min(x1 - x0, y1 - y0)),
        })
    return out


def iou(a, b):
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    ix = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    iy = max(0.0, min(ay1, by1) - max(ay0, by0))
    inter = ix * iy
    union = (ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter
    return inter / union if union > 0 else 0.0


# ---------------------------------------------------------------- stopy

def track(per_frame, iou_min=0.3):
    """Detekce → stopy. Greedy podle IoU s poslední známou polohou stopy;
    stopa přežije `IOU_GAP` snímků bez detekce (mrknutí, krátká okluze)."""
    tracks = []
    for idx, dets in per_frame:
        free = list(range(len(dets)))
        pairs = sorted(
            ((iou(t["bbox"], dets[d]["bbox"]), ti, d)
             for ti, t in enumerate(tracks) if idx - t["last"] <= IOU_GAP
             for d in range(len(dets))),
            reverse=True, key=lambda p: p[0])
        taken_t, taken_d = set(), set()
        for score, ti, d in pairs:
            if score < iou_min or ti in taken_t or d in taken_d:
                continue
            taken_t.add(ti); taken_d.add(d)
            tracks[ti]["obs"].append((idx, dets[d]))
            tracks[ti]["bbox"] = dets[d]["bbox"]
            tracks[ti]["last"] = idx
            free.remove(d)
        for d in free:
            tracks.append({"bbox": dets[d]["bbox"], "last": idx, "obs": [(idx, dets[d])]})
    return sorted(tracks, key=lambda t: -len(t["obs"]))


def assign(tracks, refs):
    """Stopy → reference. Bere se přiřazení s nejvyšším součtem průměrných
    podobností, tedy volba mezi dvojicemi, ne „ke komu je tenhle snímek blíž".
    Vrací i `margin` — o kolik je vítězné přiřazení lepší než prohozené; malý
    margin znamená, že se ti dva lidé nedají rozlišit a číslům se nedá věřit."""
    import itertools, numpy as np
    means = [np.mean([o["emb"] for _, o in t["obs"]], axis=0) for t in tracks]
    means = [m / np.linalg.norm(m) for m in means]
    names = list(refs)
    best, second = None, None
    for perm in itertools.permutations(range(len(tracks)), len(names)):
        total = sum(sim(means[ti], refs[n]) for ti, n in zip(perm, names))
        if best is None or total > best[0]:
            best, second = (total, perm), best
        elif second is None or total > second[0]:
            second = (total, perm)
    margin = (best[0] - second[0]) / len(names) if second else float("nan")
    return dict(zip(best[1], names)), margin


# ---------------------------------------------------------------- běh

def cmd_score(a):
    import cv2
    refs = {}
    for spec in a.refs.split(","):
        name, _, path = spec.partition("=")
        if not path:
            name, path = os.path.splitext(os.path.basename(spec))[0], spec
        from bench import embedding
        e = embedding(path)
        if e is None:
            sys.exit("v referenci %s není tvář" % path)
        refs[name] = e
    if len(refs) < 2:
        sys.exit("--refs chce dvě reference, jinak stačí bench.py")

    clean_set = None
    if a.clean_frames:
        clean_set = set(json.load(open(a.clean_frames)))

    run_dir = a.out or os.path.join(HERE, "out", "vid-" + time.strftime("%m%d-%H%M"))
    os.makedirs(run_dir, exist_ok=True)

    cap = cv2.VideoCapture(a.video)
    if not cap.isOpened():
        sys.exit("nejde otevřít %s" % a.video)
    fps = cap.get(cv2.CAP_PROP_FPS) or 0
    per_frame, idx, t0 = [], 0, time.time()
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if idx % a.every == 0:
            per_frame.append((idx, detect(frame)))
        idx += 1
    cap.release()
    sec = time.time() - t0
    n_read = len(per_frame)
    print("  %d snímků z %d (každý %d.), %.1f fps videa, detekce %.0f s (%.2f s/snímek)"
          % (n_read, idx, a.every, fps, sec, sec / max(n_read, 1)))

    tracks = track(per_frame)[:len(refs)]
    if len(tracks) < len(refs):
        print("  ⚠ nalezeno jen %d stop pro %d referencí" % (len(tracks), len(refs)))
    who, margin = assign(tracks, refs)
    print("  margin přiřazení %.3f%s" % (margin, "  ⚠ osoby jsou zaměnitelné" if margin < 0.05 else ""))

    rows = []
    for ti, t in enumerate(tracks):
        name = who.get(ti)
        if name is None:
            continue
        other = next(n for n in refs if n != name)
        for fidx, o in t["obs"]:
            clean = (fidx in clean_set) if clean_set is not None else (
                o["det"] >= MIN_DET and abs(o["yaw"]) <= MAX_YAW and o["size"] >= MIN_FACE)
            rows.append({
                "action": a.action, "person": name, "frame": fidx,
                "sim": round(sim(o["emb"], refs[name]), 3),
                "sim_cross": round(sim(o["emb"], refs[other]), 3),
                "det": round(o["det"], 3), "yaw": round(o["yaw"], 1),
                "size": round(o["size"]), "clean": int(clean),
            })
    rows.sort(key=lambda r: (r["person"], r["frame"]))
    csvp = os.path.join(run_dir, "frames.csv")
    with open(csvp, "w", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=list(rows[0]) if rows else
                            ["action", "person", "frame", "sim", "sim_cross", "det", "yaw", "size", "clean"])
        wr.writeheader(); wr.writerows(rows)

    res = summary(csvp, a.threshold)
    res.update({"video": os.path.abspath(a.video), "frames_read": n_read, "frames_total": idx,
                "every": a.every, "fps": fps, "detect_sec": round(sec, 1),
                "assign_margin": round(margin, 3), "threshold": a.threshold, "action": a.action})
    json.dump(res, open(os.path.join(run_dir, "summary.json"), "w"), indent=2, ensure_ascii=False)
    print("  %s" % run_dir)
    return res


def summary(csvp, threshold=0.62):
    """Per osobu: p10 čistých snímků (to je gate), medián, minimum, a kolik
    snímků se zahodilo. `sim_cross` hlídá, že se identity nepřelily."""
    import statistics as st
    rows = list(csv.DictReader(open(csvp)))
    out, verdict = {}, True
    print("\n%-8s %6s %6s %6s %6s %8s %7s %6s" % ("osoba", "p10", "med", "min", "max", "cross", "čisté", "z"))
    for p in dict.fromkeys(r["person"] for r in rows):
        rs = [r for r in rows if r["person"] == p]
        clean = [float(r["sim"]) for r in rs if r["clean"] == "1"]
        cross = [float(r["sim_cross"]) for r in rs if r["clean"] == "1"]
        if not clean:
            print("%-8s %s" % (p, "žádný čistý snímek"))
            out[p] = {"clean": 0}; verdict = False
            continue
        p10 = st.quantiles(clean, n=10)[0] if len(clean) >= 10 else min(clean)
        ok = p10 >= threshold
        verdict &= ok
        out[p] = {"p10": round(p10, 3), "median": round(st.median(clean), 3),
                  "min": round(min(clean), 3), "max": round(max(clean), 3),
                  "cross_median": round(st.median(cross), 3),
                  "clean": len(clean), "frames": len(rs), "pass": ok}
        print("%-8s %6.3f %6.3f %6.3f %6.3f %8.3f %4d/%-3d %6s"
              % (p, p10, st.median(clean), min(clean), max(clean), st.median(cross),
                 len(clean), len(rs), "ok" if ok else "POD"))
    print("  gate p10 ≥ %.2f → %s" % (threshold, "PASS" if verdict else "FAIL"))
    return {"persons": out, "pass": verdict}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("score")
    p.add_argument("video")
    p.add_argument("--refs", required=True, help="a=ref_a.png,b=ref_b.png (jméno lze vynechat)")
    p.add_argument("--every", type=int, default=2, help="měřit každý N. snímek")
    p.add_argument("--action", default="", help="kiss/hug/gaze… — jen se zapíše, prahy se kalibrují z běhů")
    p.add_argument("--threshold", type=float, default=0.62)
    p.add_argument("--clean-frames", help="JSON se seznamem neokludovaných snímků z preprocesu")
    p.add_argument("--out")
    p = sub.add_parser("summary"); p.add_argument("csv"); p.add_argument("--threshold", type=float, default=0.62)
    a = ap.parse_args()
    {"score": cmd_score, "summary": lambda a: summary(a.csv, a.threshold)}[a.cmd](a)
