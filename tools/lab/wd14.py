#!/usr/bin/env python3
"""wd14.py — booru tagy předlohy pro lab (flag „tagy z předlohy“).

    echo '{"image": "ref.png"}' | wd14.py

Vrátí JSON ve tvaru sidecaru FINETUNE gallery (`finetune-gallery/tagger/main.py`):
{"general": {tag: conf}, "character": {…}, "rating": {…}, "model": "…"}.
Je to jeho **zrcadlo**: týž model (SmilingWolf/wd-swinv2-tagger-v3), týž
preprocess (bílé doplnění na čtverec, bicubic, BGR) a tytéž prahy (0.35
obecné, 0.75 postavy), takže tagy předlohy jsou na stejné stupnici jako
`auto` caption v galerii. Měnit spolu.

Lokálně a ne přes sidecar: ten je na SPARKu jen v LAN bez Cloudflare, lab má
fungovat i mimo domácí síť. Jede na CPU, ~1–2 s na obrázek.

Model: `$LAB_WD14_DIR` (výchozí `~/.cache/lab-wd14`), stahuje `make lab-wd14`.
"""
import json
import os
import sys

MODEL_REPO = os.environ.get("TAGGER_MODEL", "SmilingWolf/wd-swinv2-tagger-v3")
THRESHOLD = float(os.environ.get("TAGGER_THRESHOLD", "0.35"))
CHARACTER_THRESHOLD = float(os.environ.get("TAGGER_CHARACTER_THRESHOLD", "0.75"))


def preprocess(image, size):
    import numpy as np
    from PIL import Image

    # Reference WD14 preprocessing: pad to square on white, resize, BGR.
    image = image.convert("RGBA")
    canvas = Image.new("RGBA", image.size, (255, 255, 255))
    canvas.alpha_composite(image)
    image = canvas.convert("RGB")

    w, h = image.size
    side = max(w, h)
    padded = Image.new("RGB", (side, side), (255, 255, 255))
    padded.paste(image, ((side - w) // 2, (side - h) // 2))
    if side != size:
        padded = padded.resize((size, size), Image.BICUBIC)

    arr = np.asarray(padded, dtype=np.float32)[:, :, ::-1]  # RGB → BGR
    return arr[np.newaxis, :]


def main():
    req = json.load(sys.stdin)
    root = os.path.expanduser(os.environ.get("LAB_WD14_DIR") or "~/.cache/lab-wd14")
    model_dir = os.path.join(root, MODEL_REPO.replace("/", "--"))
    model_path = os.path.join(model_dir, "model.onnx")
    csv_path = os.path.join(model_dir, "selected_tags.csv")
    if not (os.path.isfile(model_path) and os.path.isfile(csv_path)):
        sys.exit("chybí model WD14 v %s (make lab-wd14)" % model_dir)

    import csv

    import onnxruntime as ort
    from PIL import Image

    names, rating_idx, general_idx, character_idx = [], [], [], []
    with open(csv_path, newline="", encoding="utf-8") as f:
        for i, row in enumerate(csv.DictReader(f)):
            names.append(row["name"])
            cat = int(row["category"])
            if cat == 9:
                rating_idx.append(i)
            elif cat == 0:
                general_idx.append(i)
            elif cat == 4:
                character_idx.append(i)

    session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    try:
        image = Image.open(req["image"])
        image.load()
    except Exception as e:  # noqa: BLE001
        sys.exit("předlohu nejde načíst: %s" % e)

    inp = session.get_inputs()[0]
    probs = session.run(None, {inp.name: preprocess(image, inp.shape[1])})[0][0]

    out = {"general": {}, "character": {}, "rating": {}, "model": MODEL_REPO}
    for i in rating_idx:
        out["rating"][names[i]] = round(float(probs[i]), 4)
    for i in general_idx:
        p = float(probs[i])
        if p >= THRESHOLD:
            out["general"][names[i].replace("_", " ")] = round(p, 4)
    for i in character_idx:
        p = float(probs[i])
        if p >= CHARACTER_THRESHOLD:
            out["character"][names[i].replace("_", " ")] = round(p, 4)
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
