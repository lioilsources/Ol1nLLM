#!/usr/bin/env python3
"""facebench — kolik identity z reference přežije face inpaint (FLUX Fill + PuLID).

Běží na SPARKu vedle ComfyUI (sync.sh to tam nakopíruje):

    bench.py mask  <src.png>                 # maska obličeje + vlasové linie (jako prstem)
    bench.py run   [--variants a,b] [--seeds 3] [--srcs A,B] [--refs r1,r2]
    bench.py sheet <run_dir>                 # kontaktní arch z výsledků

Flow appky: uživatel na fotce A přemaluje obličej, vloží portrét B, ten se má
otisknout do masky. Měří se ArcFace (insightface antelopev2) podobnost
výstupu k B (simB — to chceme vysoko) a k původní tváři A (simA — hlídá, že
se tvář opravdu vyměnila). 1.0 = táž tvář, ~0.6 = „stejná osoba", < 0.4 cizí.
Graf = asset appky (assets/comfyui/*.api.json) s dosazenými placeholdery,
varianta = dict změn nodů, stejně jako to dělá comfyui_service.dart.
"""
import argparse, csv, glob, json, os, shutil, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.join(HERE, "bench")
OUT = os.path.join(HERE, "out")
sys.path.insert(0, os.path.expanduser("~/Code/video-stack"))
import chain  # noqa: E402  submit/outfile/drop_page_cache

ASSET = os.path.join(HERE, "assets", "flux_fill_inpaint_face.api.json")
PROMPT = "portrait of the person's face, natural skin texture, soft window light, photorealistic, sharp focus"


# ---------------------------------------------------------------- tváře

_app = None


def analyser():
    global _app
    if _app is None:
        from insightface.app import FaceAnalysis
        root = os.path.expanduser("~/Code/ComfyUI/models/insightface")
        _app = FaceAnalysis(name="antelopev2", root=root, providers=["CPUExecutionProvider"])
        _app.prepare(ctx_id=-1, det_size=(640, 640))
    return _app


def faces(path):
    import cv2
    return analyser().get(cv2.imread(path))


def embedding(path):
    import numpy as np
    fs = faces(path)
    if not fs:
        return None
    f = max(fs, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))
    return f.normed_embedding / np.linalg.norm(f.normed_embedding)


def sim(a, b):
    return float(a @ b) if a is not None and b is not None else float("nan")


# ---------------------------------------------------------------- maska

def cmd_mask(a):
    """Bílá elipsa přes obličej a vlasovou linii, jak by to prstem namaloval
    uživatel: bbox z detekce, o 35 % širší, nahoru o 45 % výšky (čelo + vlasy),
    dolů o 15 % (brada + kus krku)."""
    from PIL import Image, ImageDraw
    fs = faces(a.src)
    if not fs:
        chain.die("v %s není tvář" % a.src)
    f = max(fs, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))
    x0, y0, x1, y1 = f.bbox
    w, h = x1 - x0, y1 - y0
    box = (x0 - 0.35 * w / 2, y0 - 0.45 * h, x1 + 0.35 * w / 2, y1 + 0.15 * h)
    im = Image.open(a.src)
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    dst = os.path.splitext(a.src)[0] + "_mask.png"
    m.save(dst)
    print("  %s  tvář %dx%d px, maska %dx%d" % (os.path.relpath(dst, HERE), w, h, box[2] - box[0], box[3] - box[1]))


# ---------------------------------------------------------------- varianty

def v_no_redux(g):
    g["16"]["inputs"]["conditioning"] = ["14", 0]        # FluxGuidance rovnou z textu, Redux mimo

def v_redux(x):
    def f(g): g["83"]["inputs"]["strength"] = x
    return f

v_redux15 = v_redux(0.15)

def v_weight(x):
    def f(g): g["87"]["inputs"]["weight"] = x
    return f

def v_start(x):
    def f(g): g["87"]["inputs"]["start_at"] = x
    return f

def v_attn(g):
    g["87"]["inputs"]["attn_mask"] = ["90", 2]            # maska po cropu — identita jen do ní

def v_ctx(x):
    def f(g): g["90"]["inputs"]["context_from_mask_extend_factor"] = x
    return f

def v_guid(x):
    def f(g): g["16"]["inputs"]["guidance"] = x
    return f

def v_steps(x):
    def f(g): g["18"]["inputs"]["steps"] = x
    return f

def v_facepass(denoise=0.55, weight=1.2, guidance=3.5, steps=20, ctx=2.0):
    """Iterace 2: za stitch druhý průchod jen přes detekovanou tvář na FLUX.1-dev
    (PuLID je na něm nativní), crop 1024², denoise < 1 — kompozice a světlo
    zůstávají z Fill průchodu, identita se dotáhne tam, kde má PuLID nejvíc
    pixelů. Loader PuLID/EVA/InsightFace (84/85/86) se sdílí s Fill větví."""
    def f(g):
        g["100"] = {"class_type": "UNETLoader", "inputs": {"unet_name": "flux1-dev.safetensors", "weight_dtype": "fp8_e4m3fn"}}
        # vlastní loadery: sdílené EVA-CLIP z Fill větve skončí po samplingu
        # offloadnuté na CPU a druhý ApplyPulidFlux spadne na cuda/cpu mismatch
        g["107"] = {"class_type": "PulidFluxModelLoader", "inputs": {"pulid_file": "pulid_flux_v0.9.1.safetensors"}}
        g["108"] = {"class_type": "PulidFluxEvaClipLoader", "inputs": {}}
        g["109"] = {"class_type": "PulidFluxInsightFaceLoader", "inputs": {"provider": "CPU"}}
        g["101"] = {"class_type": "ApplyPulidFlux", "inputs": {
            "model": ["100", 0], "pulid_flux": ["107", 0], "eva_clip": ["108", 0], "face_analysis": ["109", 0],
            "image": ["70", 0], "weight": weight, "start_at": 0.0, "end_at": 1.0}}
        g["102"] = {"class_type": "CLIPTextEncode", "inputs": {"clip": ["11", 0], "text": PROMPT}}
        g["103"] = {"class_type": "FluxGuidance", "inputs": {"conditioning": ["102", 0], "guidance": guidance}}
        g["104"] = {"class_type": "CLIPTextEncode", "inputs": {"clip": ["11", 0], "text": ""}}
        g["105"] = {"class_type": "UltralyticsDetectorProvider", "inputs": {"model_name": "bbox/face_yolov8m.pt"}}
        g["106"] = {"class_type": "FaceDetailer", "inputs": {
            "image": ["91", 0], "model": ["101", 0], "clip": ["11", 0], "vae": ["12", 0],
            "guide_size": 1024.0, "guide_size_for": True, "max_size": 1024.0, "seed": g["18"]["inputs"]["seed"],
            "steps": steps, "cfg": 1.0, "sampler_name": "euler", "scheduler": "simple",
            "positive": ["103", 0], "negative": ["104", 0], "denoise": denoise, "feather": 8,
            "noise_mask": True, "force_inpaint": True, "bbox_threshold": 0.5, "bbox_dilation": 24,
            "bbox_crop_factor": ctx, "sam_detection_hint": "center-1", "sam_dilation": 0,
            "sam_threshold": 0.93, "sam_bbox_expansion": 0, "sam_mask_hint_threshold": 0.7,
            "sam_mask_hint_use_negative": "False", "drop_size": 10, "bbox_detector": ["105", 0],
            "wildcard": "", "cycle": 1}}
        g["20"]["inputs"]["images"] = ["106", 0]
    return f


KONTEXT_INSTR = ("Replace the face of the person in the first image with the face of the person in the "
                 "second image. Keep the hair, head pose, expression, lighting, clothing and background of "
                 "the first image exactly as they are. Photorealistic, sharp.")


def v_kontext(guidance=2.5, steps=20):
    """Iterace 3: místo Fill+PuLID edituje crop FLUX Kontext s dvěma referencemi
    (crop zdroje jako kontext, portrét jako druhý obrázek). Kontext drží identitu
    z pixelů, které vidí — ne z embeddingu. Mimo masku zůstane originál (stitch)."""
    def f(g):
        g["200"] = {"class_type": "UNETLoader", "inputs": {"unet_name": "flux1-dev-kontext_fp8_scaled.safetensors", "weight_dtype": "default"}}
        g["201"] = {"class_type": "CLIPTextEncode", "inputs": {"clip": ["11", 0], "text": KONTEXT_INSTR}}
        g["202"] = {"class_type": "FluxKontextImageScale", "inputs": {"image": ["90", 1]}}
        g["203"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["202", 0], "vae": ["12", 0]}}
        g["204"] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["201", 0], "latent": ["203", 0]}}
        g["205"] = {"class_type": "FluxKontextImageScale", "inputs": {"image": ["70", 0]}}
        g["206"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["205", 0], "vae": ["12", 0]}}
        g["207"] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["204", 0], "latent": ["206", 0]}}
        g["208"] = {"class_type": "FluxGuidance", "inputs": {"conditioning": ["207", 0], "guidance": guidance}}
        g["209"] = {"class_type": "CLIPTextEncode", "inputs": {"clip": ["11", 0], "text": ""}}
        g["210"] = {"class_type": "EmptyLatentImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1}}
        g["211"] = {"class_type": "KSampler", "inputs": {"model": ["200", 0], "positive": ["208", 0], "negative": ["209", 0],
                    "latent_image": ["210", 0], "seed": g["18"]["inputs"]["seed"], "steps": steps, "cfg": 1.0,
                    "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}}
        g["212"] = {"class_type": "VAEDecode", "inputs": {"samples": ["211", 0], "vae": ["12", 0]}}
        g["91"]["inputs"]["inpainted_image"] = ["212", 0]
        for n in ("10", "14", "15", "16", "18", "19", "42", "43", "80", "81", "82", "83", "84", "85", "86", "87"):
            g.pop(n, None)                                   # Fill/PuLID/Redux větev pryč
    return f


def combo(*fs):
    def f(g):
        for x in fs: x(g)
    return f

VARIANTS = {
    "baseline":  combo(),
    "no_redux":  v_no_redux,
    "redux15":   v_redux15,
    "w13":       v_weight(1.3),
    "w16":       v_weight(1.6),
    "attn":      v_attn,
    "ctx15":     v_ctx(1.5),
    "ctx20":     v_ctx(2.0),
    "guid20":    v_guid(20.0),
    "start01":   v_start(0.1),
    "redux08":   v_redux(0.8),                         # Redux z reference identitě POMÁHÁ (no_redux propadl)
    "redux10":   v_redux(1.0),
    "redux10_w13": combo(v_redux(1.0), v_weight(1.3)),
    "it1":       combo(v_no_redux, v_attn, v_weight(1.3), v_ctx(1.5)),
    "it1_w16":   combo(v_no_redux, v_attn, v_weight(1.6), v_ctx(1.5)),
    "it1_g20":   combo(v_no_redux, v_attn, v_weight(1.3), v_ctx(1.5), v_guid(20.0)),
    # iterace 2: it1 + druhý průchod tváře na FLUX dev
    "it2_d45":   combo(v_no_redux, v_attn, v_weight(1.3), v_ctx(1.5), v_facepass(0.45)),
    "it2_d55":   combo(v_no_redux, v_attn, v_weight(1.3), v_ctx(1.5), v_facepass(0.55)),
    "it2_d65":   combo(v_no_redux, v_attn, v_weight(1.3), v_ctx(1.5), v_facepass(0.65)),
    "it2_w15":   combo(v_no_redux, v_attn, v_weight(1.3), v_ctx(1.5), v_facepass(0.55, weight=1.5)),
    "fp_only":   v_facepass(0.55),                       # druhý průchod nad dnešním grafem
    # iterace 3: Kontext s dvěma referencemi místo Fill+PuLID
    "kontext":   v_kontext(),
    "kontext_g35": v_kontext(guidance=3.5),
}


# ---------------------------------------------------------------- běh

def stage(path):
    """Soubor do ComfyUI input/ pod stabilním jménem (bench_<basename>)."""
    name = "bench_" + os.path.basename(path)
    shutil.copy(path, os.path.join(chain.IN, name))
    return name


def build(asset, src, mask, ref, seed, variant):
    g = json.load(open(asset))
    s = json.dumps(g)
    s = s.replace("__PROMPT__", PROMPT).replace("__IMAGE__", src).replace("__MASK__", mask).replace("__REF__", ref)
    g = json.loads(s)
    for n in g.values():
        if "seed" in n["inputs"]:
            n["inputs"]["seed"] = seed
        if n["class_type"] == "RepeatLatentBatch":
            n["inputs"]["amount"] = 1
    VARIANTS[variant](g)
    return g


def cmd_run(a):
    srcs = a.srcs.split(",")
    refs = a.refs.split(",")
    variants = a.variants.split(",")
    run_dir = os.path.join(OUT, a.name or time.strftime("%m%d-%H%M"))
    os.makedirs(run_dir, exist_ok=True)
    emb_ref = {r: embedding(os.path.join(BENCH, r + ".png")) for r in refs}
    emb_src = {s: embedding(os.path.join(BENCH, s + ".png")) for s in srcs}
    rows = []
    csvp = os.path.join(run_dir, "results.csv")
    with open(csvp, "a", newline="") as fh:
        wr = csv.writer(fh)
        if fh.tell() == 0:
            wr.writerow(["variant", "src", "ref", "seed", "simB", "simA", "sec", "file"])
        for v in variants:
            for s in srcs:
                src_name = stage(os.path.join(BENCH, s + ".png"))
                mask_name = stage(os.path.join(BENCH, s + "_mask.png"))
                for r in refs:
                    ref_name = stage(os.path.join(BENCH, r + ".png"))
                    for seed in range(a.seeds):
                        g = build(ASSET, src_name, mask_name, ref_name, 1000 + seed, v)
                        for n in g.values():
                            if n["class_type"] == "SaveImage":
                                n["inputs"]["filename_prefix"] = "facebench/%s_%s_%s_%d" % (v, s, r, seed)
                        t0 = time.time()
                        outputs = chain.submit(g, "%s %s←%s #%d" % (v, s, r, seed))
                        out = chain.outfile(outputs, [k for k, n in g.items() if n["class_type"] == "SaveImage"][0], ".png")
                        dst = os.path.join(run_dir, "%s__%s__%s__%d.png" % (v, s, r, seed))
                        shutil.copy(out, dst)
                        e = embedding(dst)
                        row = [v, s, r, seed, round(sim(e, emb_ref[r]), 3), round(sim(e, emb_src[s]), 3),
                               round(time.time() - t0), os.path.basename(dst)]
                        rows.append(row); wr.writerow(row); fh.flush()
                        print("     simB %.3f  simA %.3f" % (row[4], row[5]))
    summary(csvp)


def summary(csvp):
    import statistics as st
    rows = list(csv.DictReader(open(csvp)))
    by = {}
    for r in rows:
        by.setdefault(r["variant"], []).append(r)
    print("\n%-10s %6s %6s %6s %6s %5s" % ("varianta", "simB", "min", "simA", "s", "n"))
    for v, rs in by.items():
        b = [float(r["simB"]) for r in rs if r["simB"] != "nan"]
        a_ = [float(r["simA"]) for r in rs if r["simA"] != "nan"]
        print("%-10s %6.3f %6.3f %6.3f %6.0f %5d" % (v, st.mean(b) if b else float("nan"), min(b) if b else float("nan"),
                                                      st.mean(a_) if a_ else float("nan"), st.mean(float(r["sec"]) for r in rs), len(rs)))


def cmd_sheet(a):
    """Řádek na variantu: reference | zdroj | výstupy (všechny seedy) pro jeden pár."""
    from PIL import Image
    rows = list(csv.DictReader(open(os.path.join(a.run_dir, "results.csv"))))
    pair = (a.src, a.ref)
    H = 360
    def th(p):
        im = Image.open(p); return im.resize((int(im.width * H / im.height), H))
    tiles = []
    for v in dict.fromkeys(r["variant"] for r in rows):
        outs = [r for r in rows if r["variant"] == v and (r["src"], r["ref"]) == pair]
        if not outs:
            continue
        imgs = [th(os.path.join(BENCH, a.ref + ".png")), th(os.path.join(BENCH, a.src + ".png"))] + \
               [th(os.path.join(a.run_dir, r["file"])) for r in outs]
        tiles.append((v, imgs))
    W = max(sum(i.width for i in imgs) + 10 * len(imgs) for _, imgs in tiles)
    sheet = Image.new("RGB", (W, len(tiles) * (H + 10)), (20, 20, 20))
    y = 0
    for v, imgs in tiles:
        x = 0
        for im in imgs:
            sheet.paste(im, (x, y)); x += im.width + 10
        y += H + 10
    dst = os.path.join(a.run_dir, "sheet_%s_%s.jpg" % pair)
    sheet.save(dst, quality=85)
    print(dst, "řádky:", [v for v, _ in tiles])


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("mask"); p.add_argument("src")
    p = sub.add_parser("run")
    p.add_argument("--variants", default="baseline"); p.add_argument("--seeds", type=int, default=3)
    p.add_argument("--srcs", default="srcA,srcB"); p.add_argument("--refs", default="ref1,ref2,ref3")
    p.add_argument("--name")
    p = sub.add_parser("summary"); p.add_argument("csv")
    p = sub.add_parser("sheet"); p.add_argument("run_dir"); p.add_argument("--src", default="srcA"); p.add_argument("--ref", default="ref2")
    a = ap.parse_args()
    {"mask": cmd_mask, "run": cmd_run, "summary": lambda a: summary(a.csv), "sheet": cmd_sheet}[a.cmd](a)
