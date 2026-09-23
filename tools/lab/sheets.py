#!/usr/bin/env python3
"""Build self-contained contact sheets for the style-matrix wave runs.

    python3 tools/lab/sheets.py            # all waves listed in WAVES
    python3 tools/lab/sheets.py 20260917-114732

One HTML file per run under docs/sheets/, with every frame embedded as a WebP
data URI. Self-contained on purpose: the runs themselves live in build/lab/,
which is gitignored and gets cleaned, so a sheet that referenced them would go
blank the first time someone tidied up. No webfonts and no scripts from the
network either — the point of keeping these is that they still open in five
years, on a laptop with no internet, from a plain `git clone`.

Rows are styles, columns are whatever the run varied (model × dialect ×
subject). The baseline row is pinned to the top: it is the thing every other
row is judged against.
"""
import base64
import html
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNS = ROOT / "build" / "lab"
OUT = ROOT / "docs" / "sheets"

# The runs docs/style-matrix.md names by directory. Anything not in here was
# exploration, not a wave — keeping those too would bury the six that the text
# actually refers to.
WAVES = [
    {
        "id": "20260910-104000", "file": "wave3-ablace-clip-t5.html",
        "wave": "Vlna 3", "title": "Ablace: jméno, nebo popis?",
        "note": "Šest autorů napříč známostí, text stylu v šesti variantách "
                "(<code>@name</code> jen jméno, <code>@desc</code> blok bez "
                "jména, <code>@both</code> celý blok, <code>@prose</code> věta "
                "pro T5). Modely, které čtou volnou frázi. Otázka: nese styl "
                "jméno autora, nebo popis? Odpověď byla „popis“ — a proto má "
                "<code>StylePreset</code> dvě pole, ne tři.",
    },
    {
        "id": "20260910-104001", "file": "wave3-ablace-booru.html",
        "wave": "Vlna 3", "title": "Ablace na booru modelech",
        "note": "Táž ablace na modelech, které čtou danbooru tagy, plus "
                "varianty <code>@booru</code> (tagy bez jména) a <code>@tag</code> "
                "(tagy + tag umělce). Tagy vyhrály nebo se vyrovnaly popisu u "
                "všech tří modelů; tag umělce nepřidal nic a u NoobAI jednou "
                "uškodil — proto pole <code>booruArtist</code> nevzniklo.",
    },
    {
        "id": "20260910-133000", "file": "wave3-kandidati-umelci.html",
        "wave": "Vlna 3", "title": "54 kandidátů umělců",
        "note": "Všichni kandidáti, každý model s textem pro svůj dialekt, plus "
                "šest stylů z registru jako kontroly. Do registru prošlo 42. "
                "Laťka byla nejlepší reakce nejslabší kontroly (0.747), ale "
                "metrika propustila skoro všechno a u stylů na bílém pozadí "
                "dala nízká čísla, přestože styl viditelně prošel — rozhodoval "
                "pohled na tenhle arch.",
    },
    {
        "id": "20260910-133001", "file": "wave3-degas-druhy-namet.html",
        "wave": "Vlna 3", "title": "Degas na druhém námětu",
        "note": "Jediná buňka celé vlny, která běžela v txt2img a na jiném "
                "námětu — „a man reading at a table“. Degasův blok čtenáři "
                "oblékl tutu nebo ho nahradil baletkami, na všech pěti "
                "modelech. Proto byl zahozen jako „obsah místo stylu“, a proto "
                "má vlna 5 druhý námět od začátku.",
    },
    {
        "id": "20260915-091418", "file": "wave4-booru-kultury.html",
        "wave": "Vlna 4", "title": "Booru tagy pro kulturní styly",
        "note": "39 kulturních stylů proti čtyřem anime SDXL modelům, každý ve "
                "dvou dialektech — sloupce jsou tedy model × dialekt. Tagy "
                "vyhrály u všech čtyř modelů (0.76–0.93 proti 0.39–0.69). Do "
                "registru jich prošlo 19. Neutrální předloha: dřívější vlny "
                "běžely na fotce v plavkách, což zkreslovalo styly měnící "
                "oblečení.",
    },
    {
        "id": "20260917-163349", "file": "wave5-pony-vs-atomix.html",
        "wave": "Vlna 5", "title": "pony × atomix-pony-anime",
        "note": "Táž sada 82 stylů a tytéž dva náměty jako u schnella, aby šlo "
                "srovnávat. Oba modely jsou Pony linie, oba čtou booru tagy, "
                "oba mají týž score prefix — liší se checkpointem a o dva kroky. "
                "Sloupce jsou model × námět. <b>Ani jeden nevyrobí médium</b>: "
                "styl dorazí jako design postavy a kulisa, ne jako materiál "
                "obrazu. U <code>pony</code> se navíc na části bloků ztratí "
                "i námět (himba a vangogh-arles dají antropomorfní zvíře, "
                "maasai leopardí vzor) — a protože takový rozpad je barevně "
                "nejdál od baseline, metrika ho odmění: pony má vyšší rozptyl "
                "(0.646) než soudržnější atomix (0.555).",
    },
    {
        "id": "20260917-114732", "file": "wave5-schnell.html",
        "wave": "Vlna 5", "title": "flux-schnell, 82 stylů na dvou námětech",
        "note": "První vlna mimo ComfyUI (gen-queue) a první v txt2img. Sloupce "
                "jsou dva náměty. <b>Barevná metrika tenhle běh neseřadila</b>: "
                "<code>inca 0.276</code> a <code>elgreco 0.167</code> leží dole "
                "a přitom styl jasně prošel, zatímco 66 z 82 stylů leží nad "
                "0.94 a navzájem se nerozliší. Řazení je proto abecední.",
    },
]


def size_of(path: Path):
    """Pixel size of a thumbnail, straight from its header."""
    from PIL import Image
    with Image.open(path) as im:
        return im.size


def webp(path: Path) -> str:
    """Re-encode a lab thumbnail as WebP. Same pixels, ~44 % of the bytes —
    which is what makes keeping ~930 frames in git defensible at all."""
    r = subprocess.run(["cwebp", "-quiet", "-q", "72", str(path), "-o", "-"],
                       capture_output=True)
    if r.returncode != 0 or not r.stdout:
        raise RuntimeError(f"cwebp selhal na {path}: {r.stderr.decode()[:200]}")
    return "data:image/webp;base64," + base64.b64encode(r.stdout).decode()


def col_key(cell, n_prompts, n_variants):
    v = (cell["variant"] or {}).get("value", "")
    return (cell["model"], v if n_variants > 1 else "",
            cell["promptIndex"] if n_prompts > 1 else 0)


def col_label(key, prompts):
    model, variant, pi = key
    bits = [html.escape(model)]
    if variant:
        bits.append(f'<span class="v">{html.escape(variant)}</span>')
    if len(prompts) > 1:
        short = prompts[pi].split(",")[0].strip()
        bits.append(f'<span class="v">{html.escape(short[:22])}</span>')
    return "".join(bits)


def build(spec):
    d = RUNS / spec["id"]
    man = json.loads((d / "wf" / "manifest.json").read_text())
    met_path = d / "metrics.json"
    met = json.loads(met_path.read_text()) if met_path.exists() else {"cells": {}}
    styles = {s["id"]: s for s in man["styles"]}
    prompts = man.get("prompts", [""])
    cells = man["cells"]

    n_prompts = len({c["promptIndex"] for c in cells})
    n_variants = len({(c["variant"] or {}).get("value", "") for c in cells})
    cols = sorted({col_key(c, n_prompts, n_variants) for c in cells})

    grid = {}
    for c in cells:
        grid[(c["style"], col_key(c, n_prompts, n_variants))] = c

    order = sorted({c["style"] for c in cells},
                   key=lambda s: (s != "__baseline",
                                  styles.get(s, {}).get("label", s).lower()))

    rows_html = []
    for sid in order:
        s = styles.get(sid, {})
        if sid == "__baseline":
            name, sub, cls = "bez stylu", "baseline", " base"
        else:
            name = html.escape(s.get("label", sid))
            sub = html.escape(s.get("artist") or s.get("period") or sid)
            cls = ""
        frames = []
        for k in cols:
            c = grid.get((sid, k))
            if not c:
                frames.append('<div class="gap" title="buňka neexistuje"></div>')
                continue
            t = d / "thumb" / f"{c['id']}.jpg"
            if not t.exists():
                frames.append('<div class="gap" title="obrázek chybí"></div>')
                continue
            r = met["cells"].get(c["id"], {}).get("reaction")
            rt = f"{r:.2f}" if isinstance(r, float) else "—"
            alt = f"{name} — {k[0]}"
            # Explicit dimensions so a lazy frame reserves its box before it
            # loads. Without them every unloaded row collapses to its label,
            # the page height is wrong until you have scrolled past everything,
            # and jumping to a row lands somewhere else.
            w, h = size_of(t)
            frames.append(
                f'<figure><img src="{webp(t)}" alt="{html.escape(alt)}" '
                f'width="{w}" height="{h}" loading="lazy" decoding="async">'
                f'<figcaption class="metric">{rt}</figcaption></figure>')
        rows_html.append(
            f'<div class="row{cls}" data-q="{html.escape((sid + " " + name + " " + sub).lower())}">'
            f'<div class="rh"><b>{name}</b><span>{sub}</span></div>'
            f'{"".join(frames)}</div>')

    head = "".join(f'<div class="ch">{col_label(k, prompts)}</div>' for k in cols)
    subject = "<br>".join(html.escape(p) for p in prompts)
    flows = ", ".join(sorted({c["flow"] for c in cells}))
    seed = json.loads((d / "spec.json").read_text()).get("seed", "?") \
        if (d / "spec.json").exists() else "?"

    doc = TEMPLATE.format(
        title=f"{spec['wave']} — {spec['title']}",
        wave=spec["wave"], name=html.escape(spec["title"]), note=spec["note"],
        run=spec["id"], cells=len(cells), models=len({c["model"] for c in cells}),
        styles=len(order) - (1 if "__baseline" in order else 0),
        flows=flows, seed=seed, subject=subject,
        ncols=len(cols), head=head, rows="\n".join(rows_html),
        width=max(760, 150 * len(cols) + 150),
    )
    out = OUT / spec["file"]
    out.write_text(doc)
    return out, len(cells), out.stat().st_size


TEMPLATE = """<!doctype html>
<html lang="cs"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
:root{{
  --ground:#15141A; --surface:#1E1C25; --edge:#2E2B38;
  --ink:#EFEBE3; --muted:#928DA0; --dim:#6B6678;
  --safelight:#E8B33C; --frame:#0E0D12;
  --ui:"Helvetica Neue",Helvetica,Arial,sans-serif;
  --prose:Georgia,"Times New Roman",serif;
  --mono:ui-monospace,Menlo,Consolas,monospace;
}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--ground);color:var(--ink);font-family:var(--prose);
  font-size:16px;line-height:1.6;-webkit-font-smoothing:antialiased}}
.wrap{{max-width:1240px;margin:0 auto;padding:0 20px;padding-block:36px 64px}}
a{{color:var(--safelight)}}
h1{{font-family:var(--ui);font-size:clamp(26px,4.5vw,40px);font-weight:700;
  letter-spacing:-.01em;line-height:1.1;margin:0;text-wrap:balance}}
.eyebrow{{font-family:var(--ui);text-transform:uppercase;letter-spacing:.14em;
  font-size:12px;font-weight:700;color:var(--safelight);margin-bottom:10px}}
.note{{color:#DAD5CC;max-width:70ch;margin:16px 0 0}}
.note code{{font-family:var(--mono);font-size:13px;color:var(--safelight)}}
.facts{{display:flex;flex-wrap:wrap;gap:4px 26px;margin-top:20px;
  font-family:var(--mono);font-size:12.5px;color:var(--dim)}}
.facts b{{color:var(--ink);font-weight:500}}
.subject{{margin-top:14px;padding:12px 14px;background:var(--surface);
  border-radius:5px;font-size:14px;color:var(--muted);max-width:80ch}}
.subject b{{font-family:var(--ui);text-transform:uppercase;letter-spacing:.1em;
  font-size:11px;color:var(--dim);display:block;margin-bottom:4px}}
.bar{{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:26px 0 0}}
input[type=search]{{flex:1 1 200px;min-width:0;padding:9px 12px;border-radius:5px;
  border:1px solid var(--edge);background:var(--frame);color:var(--ink);
  font:inherit;font-size:14.5px}}
label.t{{display:flex;align-items:center;gap:7px;cursor:pointer;font-family:var(--ui);
  text-transform:uppercase;letter-spacing:.09em;font-size:12px;font-weight:700;
  color:var(--muted)}}
label.t input{{accent-color:var(--safelight);width:15px;height:15px}}
:focus-visible{{outline:2px solid var(--safelight);outline-offset:2px}}

.scroll{{overflow-x:auto;padding-bottom:8px}}
.grid{{min-width:{width}px}}
.row,.chead{{display:grid;grid-template-columns:150px repeat({ncols},1fr);gap:5px;
  align-items:start}}
/* The header sits OUTSIDE .scroll on purpose. `overflow-x:auto` makes the
   other axis compute to `auto` too, so a sticky header inside that container
   sticks to the container — which is as tall as its content, so it scrolls
   away after the first row. Out here its ancestors scroll with the page, so it
   really stays put; the script below keeps it aligned sideways. */
.chead-wrap{{position:sticky;top:0;z-index:3;overflow:hidden;margin-top:18px;
  background:var(--ground);border-bottom:1px solid var(--edge)}}
.chead{{min-width:{width}px;padding:8px 0}}
.ch{{font-family:var(--ui);font-size:12px;font-weight:700;color:var(--muted);
  letter-spacing:.02em;padding:0 2px;overflow-wrap:anywhere}}
.ch .v{{display:block;font-weight:400;color:var(--dim);font-size:11px;
  text-transform:uppercase;letter-spacing:.08em}}
.row{{padding:6px 0;border-bottom:1px solid #232029}}
.row.base{{background:#1C1A23;border-bottom:2px solid var(--safelight)}}
.rh{{padding:4px 8px 0 2px;min-width:0}}
.rh b{{display:block;font-size:14px;line-height:1.25;font-weight:600}}
.rh span{{display:block;font-family:var(--ui);font-size:10.5px;color:var(--dim);
  text-transform:uppercase;letter-spacing:.07em;margin-top:2px;overflow-wrap:anywhere}}
.row figure{{margin:0;min-width:0;position:relative}}
.row img{{display:block;width:100%;height:auto;max-width:100%;border-radius:3px;
  background:var(--frame)}}
.gap{{aspect-ratio:1;border:1px dashed var(--edge);border-radius:3px}}
.metric{{display:none;font-family:var(--mono);font-size:10px;color:var(--dim);
  padding-top:3px;font-variant-numeric:tabular-nums}}
body.m .metric{{display:block}}
.row[hidden]{{display:none}}
footer{{margin-top:44px;padding-top:20px;border-top:1px solid var(--edge);
  color:var(--dim);font-size:13.5px;max-width:74ch}}
footer code{{font-family:var(--mono);font-size:12.5px;color:var(--muted)}}
@media (max-width:460px){{.wrap{{padding-block:24px 40px}}}}
</style></head><body>
<div class="wrap">
<p class="eyebrow">{wave} · stylová matice</p>
<h1>{name}</h1>
<p class="note">{note}</p>
<p class="facts"><span><b>{cells}</b> buněk</span><span><b>{models}</b> modelů</span>
  <span><b>{styles}</b> stylů</span><span>flow <b>{flows}</b></span>
  <span>seed <b>{seed}</b></span><span><code>build/lab/{run}</code></span></p>
<p class="subject"><b>Námět</b>{subject}</p>

<div class="bar">
  <input type="search" id="q" placeholder="hledat styl nebo autora…" aria-label="Hledat styl">
  <label class="t"><input type="checkbox" id="m"> skóre</label>
</div>

<div class="chead-wrap" id="ch"><div class="chead"><div class="ch">styl</div>{head}</div></div>
<div class="scroll" id="sc"><div class="grid">
  {rows}
</div></div>

<footer>Kontaktní kopie běhu z <code>tools/lab</code>; rámečky jsou v souboru
zapečené, takže arch funguje i po smazání <code>build/lab/</code>. Skóre pod
přepínačem je barevná reakce vůči baseline téhož sloupce — měří paletu, ne
převzetí stylu, a rozhodovat má pohled. Verdikty jsou v
<code>docs/style-matrix.md</code>.</footer>
</div>
<script>
var rows=[].slice.call(document.querySelectorAll('.row')),q=document.getElementById('q');
q.addEventListener('input',function(){{
  var t=q.value.trim().toLowerCase();
  rows.forEach(function(r){{r.hidden=!!t&&r.dataset.q.indexOf(t)<0;}});
}});
document.getElementById('m').addEventListener('change',function(e){{
  document.body.classList.toggle('m',e.target.checked);
}});
var sc=document.getElementById('sc'),ch=document.getElementById('ch');
sc.addEventListener('scroll',function(){{ch.scrollLeft=sc.scrollLeft;}},{{passive:true}});
</script></body></html>
"""


def artifact_body(doc: str) -> str:
    """The same page minus the document wrapper.

    Artifacts supply their own <head> (charset, viewport, a small reset) and
    reject <html>/<head>/<body> in the uploaded file, so the published copy is
    this transform of the repo file rather than a second generator — a second
    one would drift from the archive it is supposed to mirror.
    """
    title = doc.split("<title>", 1)[1].split("</title>", 1)[0]
    style = doc[doc.index("<style>"):doc.index("</style>") + len("</style>")]
    body = doc.split("<body>", 1)[1].rsplit("</body>", 1)[0]
    return f"<title>{title}</title>\n{style}\n{body}"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    args = sys.argv[1:]
    art = None
    if "--artifact" in args:
        i = args.index("--artifact")
        art = Path(args[i + 1])
        args = args[:i] + args[i + 2:]
    wanted = args
    todo = [w for w in WAVES if not wanted or w["id"] in wanted or w["file"] in wanted]
    if not todo:
        sys.exit(f"nic k sestavení; znám: {', '.join(w['id'] for w in WAVES)}")
    built = []
    for spec in todo:
        if not (RUNS / spec["id"]).exists():
            print(f"✗ {spec['id']} — běh na disku není, přeskakuji")
            continue
        path, n, size = build(spec)
        print(f"✓ {path.relative_to(ROOT)}  {n} buněk  {size/1048576:.1f} MB")
        built.append((spec, path, n, size))
        if art is not None:
            art.write_text(artifact_body(path.read_text()))
            print(f"✓ {art}  (bez obalu dokumentu, {art.stat().st_size/1048576:.1f} MB)")
    if built and art is None:
        index(built)


def index(built):
    items = []
    for spec, path, n, size in built:
        items.append(f"""<li><a href="{path.name}">{html.escape(spec['title'])}</a>
      <span class="w">{spec['wave']}</span>
      <span class="f">{n} buněk · {size/1048576:.1f} MB · <code>{spec['id']}</code></span></li>""")
    (OUT / "index.html").write_text(f"""<!doctype html>
<html lang="cs"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Archy stylové matice</title>
<style>
body{{margin:0;background:#15141A;color:#EFEBE3;font:16px/1.6 Georgia,serif}}
.wrap{{max-width:760px;margin:0 auto;padding:0 20px;padding-block:44px 64px}}
h1{{font-family:"Helvetica Neue",Arial,sans-serif;font-size:34px;margin:0 0 10px}}
p{{color:#928DA0;max-width:68ch}}
code{{font-family:ui-monospace,Menlo,monospace;font-size:13px;color:#928DA0}}
ul{{list-style:none;padding:0;margin:28px 0 0;display:grid;gap:2px}}
li{{padding:14px 16px;background:#1E1C25;border-radius:6px;
  border-left:3px solid #2E2B38}}
li:hover{{border-left-color:#E8B33C}}
a{{color:#EFEBE3;font-size:18px;text-decoration:none;font-weight:600}}
a:hover{{color:#E8B33C}}
.w{{font-family:"Helvetica Neue",Arial,sans-serif;font-size:11px;font-weight:700;
  text-transform:uppercase;letter-spacing:.12em;color:#E8B33C;margin-left:9px}}
.f{{display:block;font-family:ui-monospace,Menlo,monospace;font-size:12px;
  color:#6B6678;margin-top:4px}}
</style></head><body><div class="wrap">
<h1>Archy stylové matice</h1>
<p>Kontaktní kopie běhů, na kterých stojí verdikty v
<code>docs/style-matrix.md</code>. Rámečky jsou v souborech zapečené, takže
archy fungují i po smazání <code>build/lab/</code> a bez sítě.</p>
<p>Sestaveno <code>tools/lab/sheets.py</code>; řádky jsou styly, sloupce to, co
běh měnil (model × dialekt × námět).</p>
<ul>{"".join(items)}</ul>
</div></body></html>
""")
    total = sum(s for _, _, _, s in built)
    print(f"✓ docs/sheets/index.html  ({len(built)} archů, celkem {total/1048576:.1f} MB)")


if __name__ == "__main__":
    main()
