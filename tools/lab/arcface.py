#!/usr/bin/env python3
"""arcface.py — podobnost tváře k referenci pro metriky labu.

    echo '{"ref": "ref.png", "images": {"cell-id": "img/x.png"}}' | arcface.py

Vrátí JSON: {"ref": {"faces": n}, "cells": {"cell-id": {"identity": 0.71,
"faces": 1, "face": 212}}}. `identity` je kosinová podobnost ArcFace
embeddingů (insightface antelopev2) **největší** tváře ve výstupu a v referenci:
1.0 = táž tvář, ~0.6 = pořád táž osoba, < 0.4 jiný člověk. Stejné modely,
detekce (640×640) i výběr největší tváře jako `tools/facebench/bench.py` a
bench Kadeřníka, takže čísla jsou srovnatelná s 0.48 / 0.72 z face inpaintu.
`face` je výška tváře v px — pod ~40 px ArcFace přestává být spolehlivý.
Buňka bez tváře má `identity: null`.

Modely: `$LAB_INSIGHTFACE_ROOT/models/antelopev2` (výchozí `~/.insightface`),
nastavení: `make lab-arcface`. Jede na CPU.
"""
import json
import os
import sys
import warnings


def main():
    req = json.load(sys.stdin)
    # insightface ohlašuje zastaralá API scikit-image na stderr; Go z něj bere
    # poslední řádek jako chybovou hlášku, takže tam patří jen skutečná chyba
    warnings.filterwarnings("ignore", category=FutureWarning)
    import cv2
    import numpy as np
    from insightface.app import FaceAnalysis

    root = os.path.expanduser(os.environ.get("LAB_INSIGHTFACE_ROOT") or "~/.insightface")
    if not os.path.isdir(os.path.join(root, "models", "antelopev2")):
        sys.exit("chybí modely %s/models/antelopev2 (make lab-arcface)" % root)
    app = FaceAnalysis(name="antelopev2", root=root, providers=["CPUExecutionProvider"],
                       allowed_modules=["detection", "recognition"])
    app.prepare(ctx_id=-1, det_size=(640, 640))

    def largest(path):
        img = cv2.imread(path)
        if img is None:
            return None, 0
        faces = app.get(img)
        if not faces:
            return None, 0
        f = max(faces, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))
        return f, len(faces)

    ref, n = largest(req["ref"])
    if ref is None:
        sys.exit("v referenci %s není tvář" % req["ref"])
    emb = ref.normed_embedding / np.linalg.norm(ref.normed_embedding)
    out = {"ref": {"faces": n}, "cells": {}}
    for cid, path in req["images"].items():
        f, n = largest(path)
        if f is None:
            out["cells"][cid] = {"identity": None, "faces": 0}
            continue
        e = f.normed_embedding / np.linalg.norm(f.normed_embedding)
        out["cells"][cid] = {"identity": round(float(emb @ e), 4), "faces": n,
                             "face": int(round(f.bbox[3] - f.bbox[1]))}
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
