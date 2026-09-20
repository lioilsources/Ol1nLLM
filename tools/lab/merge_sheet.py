#!/usr/bin/env python3
"""Combine two different pipelines' outputs into one contact sheet: Ol1nLLM's
lab (flux-schnell, txt2img, gen-queue) vs tsumiki-bench (flux-dev/flux-manga,
restyle, ComfyUI on SPARK). Same 42 painters, same subject wording, but two
structurally different mechanisms — schnell renders from text alone, dev
restyles the actual source photo (depth ControlNet + PuLID identity). Rows
are painters; columns are schnell/dancer, schnell/seated, dev/dancer,
dev/seated. Self-contained HTML, thumbnails as data URIs.

    merge_sheet.py OUT.html SCHNELL_DIR FLUX_DIR

SCHNELL_DIR is an Ol1nLLM lab run dir (build/lab/<run>, has state.json + img/).
FLUX_DIR is a tsumiki-bench restyle run dir (out/<run>, has manifest.json +
img/) — it only ever exists on SPARK (gitignored bench output), so rsync it
to a local path first and pass that path here.
"""
import base64
import html
import io
import json
import sys
from pathlib import Path

from PIL import Image

THUMB = 200

if len(sys.argv) < 4:
    sys.exit("usage: merge_sheet.py OUT.html SCHNELL_DIR FLUX_DIR")
OUT = Path(sys.argv[1])
SCHNELL_DIR = Path(sys.argv[2])
FLUX_DIR = Path(sys.argv[3])

PAINTERS = ("davinci,davinci-chalk,picasso-blue,picasso-rose,picasso-cubist,basquiat,"
            "hockney-pool,monet,kahlo,goya-black,goya-caprichos,kandinsky-early,"
            "vangogh-arles,vangogh-saintremy,lautrec-poster,lautrec-cabaret,"
            "mucha-slav-epic,kubista,schiele,klimt-golden,vermeer,botticelli,elgreco,"
            "munch,matisse-fauve,matisse-cutout,gauguin,cezanne,seurat,hopper,warhol,"
            "lichtenstein,haring,bacon,rivera,chagall,dali,magritte,lempicka,beardsley,"
            "lada,josef-capek").split(",")


def data_uri(path: Path, size: int = THUMB) -> str:
    with Image.open(path) as im:
        im = im.convert("RGB")
        im.thumbnail((size, size * 2))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=78)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def schnell_cell(style: str, subject_idx: int) -> Path | None:
    name = f"txt2img__flux-schnell__{style}__p{subject_idx:02d}.png"
    p = SCHNELL_DIR / "img" / name
    return p if p.exists() else None


def flux_manifest() -> dict:
    return json.loads((FLUX_DIR / "manifest.json").read_text())


def flux_cell(manifest: dict, style: str, src: str) -> Path | None:
    for row in manifest["cells"].values():
        if row["style"] == style and row["src"] == src and row["status"] == "done":
            return FLUX_DIR / row["file"]
    return None


def build() -> str:
    manifest = flux_manifest()
    cols = [
        ("schnell", "dancer"), ("schnell", "seated"),
        ("flux-dev", "dancer"), ("flux-dev", "seated"),
    ]
    out = ["""<title>schnell vs flux-dev — 42 malířů</title>
<style>
:root { --bg:#fafaf7; --fg:#1d1d1b; --dim:#77756f; --line:#e2e0da; --card:#fff; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#161614; --fg:#ecebe6; --dim:#9a988f; --line:#2d2c29; --card:#1f1f1c; } }
:root[data-theme="dark"] { --bg:#161614; --fg:#ecebe6; --dim:#9a988f; --line:#2d2c29; --card:#1f1f1c; }
body { background:var(--bg); color:var(--fg); font:13px/1.4 system-ui, sans-serif; padding:16px; }
h1 { font-size:20px; margin:0 0 4px; }
.note { color:var(--dim); max-width:78ch; }
.wrap { overflow-x:auto; }
table { border-collapse:collapse; }
th, td { border-bottom:1px solid var(--line); padding:6px; vertical-align:top; text-align:left; }
th.grp { font-weight:600; text-align:center; border-bottom:none; padding-bottom:2px; }
th.col { font-weight:500; color:var(--dim); font-size:11px; }
td.style { min-width:150px; position:sticky; left:0; background:var(--bg); font-weight:600; }
img { width:200px; display:block; border-radius:4px; background:var(--card); }
</style>
<h1>flux-schnell vs FLUX.1-dev (flux-manga) — 42 malířů</h1>
<p class="note">Stejných 42 malířů (bajtově identický <code>block</code> text v Ol1nLLM i MangaPrompts
registru) a stejné dva náměty (baletka, sedící muž) — ale dva strukturálně různé mechanismy.
<b>schnell</b>: čistý txt2img z gen-queue (4 kroky), subjekt je popsaný textem
(<code>srcs/prompts.json</code>), žádná fotka, žádný ControlNet. <b>flux-dev</b> (MangaPrompts
nazývá stejný checkpoint „manga prompts", Ol1nLLM „flux-manga"): tsumiki-bench restyle na SPARKu,
plný denoise 1.0 z prázdného latentu, ale veden depth ControlNetem a PuLID identitou ze zdrojové
fotky — pozice těla a identita jdou z fotky, ne z textu. Je to tedy spíš srovnání „umí styl
prosadit přes text" vs „umí styl prosadit přes ControlNet/identitu", ne čistě architektura vs
architektura.</p>
<div class="wrap"><table><tr><th></th>"""]
    out.append('<th class="grp" colspan="2">flux-schnell (text)</th><th class="grp" colspan="2">flux-dev (foto+ControlNet)</th></tr><tr><th></th>')
    for eng, subj in cols:
        out.append(f'<th class="col">{html.escape(subj)}</th>')
    out.append("</tr>")

    missing = []
    for style in PAINTERS:
        out.append(f'<tr><td class="style">{html.escape(style)}</td>')
        for eng, subj in cols:
            if eng == "schnell":
                idx = 0 if subj == "dancer" else 1
                p = schnell_cell(style, idx)
            else:
                src = "p-dancer.png" if subj == "dancer" else "p-seated.png"
                p = flux_cell(manifest, style, src)
            if p:
                out.append(f'<td><img loading="lazy" src="{data_uri(p)}" alt=""></td>')
            else:
                out.append("<td><i style='color:var(--dim)'>čeká</i></td>")
                missing.append(f"{eng}/{subj}/{style}")
        out.append("</tr>")
    out.append("</table></div>")
    if missing:
        out.append(f"<p class='note'>{len(missing)} buněk zatím chybí (běh v pořízení): {html.escape(', '.join(missing[:8]))}{'…' if len(missing) > 8 else ''}</p>")
    return "\n".join(out)


if __name__ == "__main__":
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build())
    print(OUT)
