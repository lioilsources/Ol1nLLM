#!/usr/bin/env python3
"""dino.py — DINOv2 podobnost celého obrázku k referenci pro metriky labu.

    echo '{"ref": "ref.png", "images": {"cell-id": "img/x.png"}}' | dino.py

Vrátí JSON: {"model": "dinov2_vits14", "cells": {"cell-id": {"dino": 0.83}}}.
`dino` je kosinová podobnost CLS embeddingů DINOv2 ViT-S/14 (torch hub
`facebookresearch/dinov2`) reference a buňky.

Proč vedle ArcFace: StoryTeller (STORYTELLER_MODELS_PLAN §2) rozhoduje
o `degraded` gatem `DINOv2 cos(ref, variant) ≥ 0.80`, a jeho postavy jsou
kreslená zvířata, věci a skřítci, na kterých ArcFace nenajde tvář. Lab tak
měří tou metrikou, která bude v produkci rozhodovat.

Předzpracování: celý obrázek zmenšený na 224×224 (bicubic, **bez ořezu** —
karta je celá postava a středový ořez by uřízl hlavu nebo nohy), normalizace
ImageNet. Produkční gate zatím není napsaný, takže tohle je návrh: až vznikne,
musí použít totéž, jinak čísla nesedí.

Závislosti: torch, torchvision, pillow (`make lab-dino`). Váhy (~90 MB) stáhne
torch hub při prvním běhu do `$TORCH_HOME`, výchozí `build/lab/torch` v repu
(ne boot disk). Jede na CPU, ~0.1–0.3 s na buňku.
"""
import json
import os
import sys
import warnings

MODEL = "dinov2_vits14"


def main():
    req = json.load(sys.stdin)
    # Go bere poslední řádek stderr jako chybovou hlášku — varování torch hubu
    # (xFormers not available…) tam nepatří.
    warnings.filterwarnings("ignore")
    here = os.path.dirname(os.path.abspath(__file__))
    os.environ.setdefault("TORCH_HOME", os.path.join(here, "..", "..", "build", "lab", "torch"))

    import torch
    from PIL import Image
    from torchvision import transforms

    torch.set_num_threads(max(1, (os.cpu_count() or 2) // 2))
    model = torch.hub.load("facebookresearch/dinov2", MODEL, verbose=False)
    model.eval()
    prep = transforms.Compose([
        transforms.Resize((224, 224), interpolation=transforms.InterpolationMode.BICUBIC),
        transforms.ToTensor(),
        transforms.Normalize((0.485, 0.456, 0.406), (0.229, 0.224, 0.225)),
    ])

    @torch.no_grad()
    def embed(path):
        img = Image.open(path).convert("RGB")
        e = model(prep(img).unsqueeze(0))[0]
        return e / e.norm()

    try:
        ref = embed(req["ref"])
    except OSError as e:
        sys.exit("reference %s nejde přečíst: %s" % (req["ref"], e))
    out = {"model": MODEL, "cells": {}}
    for cid, path in req["images"].items():
        try:
            e = embed(path)
        except OSError:
            out["cells"][cid] = {"dino": None}
            continue
        out["cells"][cid] = {"dino": round(float(ref @ e), 4)}
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
