#!/usr/bin/env python3
"""Contact sheet for one Ol1nLLM-lab flow (img2img or repose) across 7 models
and both subjects (dancer, seated) — two separate lab run directories, one
per subject, merged into a single sheet. Rows are the 42 painters; columns
are model x subject. Self-contained HTML, thumbnails as data URIs.
"""
import base64
import html
import io
import json
import sys
from pathlib import Path

from PIL import Image

THUMB = 190

FLOW = sys.argv[1]  # "img2img" or "repose"
DANCER_DIR = Path(sys.argv[2])
SEATED_DIR = Path(sys.argv[3])
OUT = Path(sys.argv[4])
TITLE = sys.argv[5] if len(sys.argv) > 5 else FLOW

MODELS = ["animagine-xl", "flux-manga", "illustrious-xl", "juggernaut-xl",
          "juggernaut-xl-lightning", "noobai-xl", "wai-illustrious"]

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
        im.save(buf, "JPEG", quality=76)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def cell_path(run_dir: Path, model: str, style: str) -> Path | None:
    key = f"{FLOW}__{model}__{style}"
    p = run_dir / "img" / f"{key}.png"
    return p if p.exists() else None


def build() -> str:
    cols = [(m, "dancer") for m in MODELS] + [(m, "seated") for m in MODELS]
    out = [f"""<title>{html.escape(TITLE)}</title>
<style>
:root {{ --bg:#fafaf7; --fg:#1d1d1b; --dim:#77756f; --line:#e2e0da; --card:#fff; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#161614; --fg:#ecebe6; --dim:#9a988f; --line:#2d2c29; --card:#1f1f1c; }} }}
:root[data-theme="dark"] {{ --bg:#161614; --fg:#ecebe6; --dim:#9a988f; --line:#2d2c29; --card:#1f1f1c; }}
body {{ background:var(--bg); color:var(--fg); font:13px/1.4 system-ui, sans-serif; padding:16px; }}
h1 {{ font-size:20px; margin:0 0 4px; }}
.note {{ color:var(--dim); max-width:82ch; }}
.wrap {{ overflow-x:auto; }}
table {{ border-collapse:collapse; }}
th, td {{ border-bottom:1px solid var(--line); padding:5px; vertical-align:top; text-align:left; }}
th.col {{ font-weight:500; color:var(--dim); font-size:10px; white-space:nowrap; }}
td.style {{ min-width:120px; position:sticky; left:0; background:var(--bg); font-weight:600; font-size:12px; }}
img {{ width:{THUMB}px; display:block; border-radius:4px; background:var(--card); }}
</style>
<h1>{html.escape(TITLE)}</h1>
<p class="note">Řádky: 42 malířů. Sloupce: 7 modelů × 2 náměty (baletka, sedící muž) — nejdřív
všech 7 modelů pro baletku, pak všech 7 pro sedícího muže. Seed 777, {FLOW}.</p>
<div class="wrap"><table><tr><th></th>"""]
    for m, subj in cols:
        out.append(f'<th class="col">{html.escape(m)}<br>{subj}</th>')
    out.append("</tr>")

    missing = 0
    for style in PAINTERS:
        out.append(f'<tr><td class="style">{html.escape(style)}</td>')
        for m, subj in cols:
            run_dir = DANCER_DIR if subj == "dancer" else SEATED_DIR
            p = cell_path(run_dir, m, style)
            if p:
                out.append(f'<td><img loading="lazy" src="{data_uri(p)}" alt=""></td>')
            else:
                out.append("<td>—</td>")
                missing += 1
        out.append("</tr>")
    out.append("</table></div>")
    if missing:
        out.append(f"<p class='note'>{missing} buněk chybí.</p>")
    return "\n".join(out)


if __name__ == "__main__":
    OUT.parent.mkdir(parents=True, exist_ok=True)
    html_out = build()
    OUT.write_text(html_out)
    print(OUT, "missing" if "buněk chybí" in html_out else "complete")
