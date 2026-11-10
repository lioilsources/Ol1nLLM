#!/usr/bin/env python3
"""Pages for lab run 7e: style position x quality prefix on the six tag models.

Writes index.html + one page per model (self-contained, thumbs as webp data URIs).
Run from the Ol1nLLM repo root.
"""
import base64, html, io, json, re, sys
from collections import defaultdict
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / "build/lab"
OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)

MODELS = [("pony", "Pony V6"), ("illustrious-xl", "Illustrious"), ("noobai-xl", "NoobAI"),
          ("animagine-xl", "Animagine"), ("wai-illustrious", "WAI"), ("hassaku-illustrious", "Hassaku")]
STYLES = ["watercolor-wet", "oil-impasto", "gouache", "marker", "graphite", "charcoal", "soft-pastel",
          "linocut", "acrylic-flat", "crayon", "ballpoint", "oil-pastel", "baroque", "rococo", "prerafael",
          "bauhaus-poster", "egyptian", "byzantine", "vermeer", "caravaggio", "hokusai", "klee", "miro", "van-eyck"]
PROMPTS = [("p00", "Baletka na špičce"), ("p01", "Muž čte u stolu")]
# (run, variant, caption)
VARIANTS = [("w7-7e-pos", "stylePosition-end", "prefix · styl na konci (appka)"),
            ("w7-7e-pos", "stylePosition-front", "prefix · styl před námětem"),
            ("w7-7e-pos", "stylePosition-first", "styl úplně první"),
            ("w7-7e-nopfx", "stylePosition-end", "bez prefixu · styl na konci"),
            ("w7-7e-nopfx", "stylePosition-front", "bez prefixu · styl před námětem")]
THRESH = 0.15

# style labels + booru text from the registry
labels, booru = {}, {}
for f in ROOT.glob("lib/models/style_presets_*.dart"):
    cur = None
    for line in f.read_text().splitlines():
        m = re.match(r"\s*id: '([^']+)',", line)
        if m: cur = m.group(1); continue
        m = re.match(r"\s*label: '([^']+)',", line)
        if m and cur: labels[cur] = m.group(1)
        m = re.match(r"\s*booru:\s*'(.*)',\s*$", line)
        if m and cur: booru[cur] = m.group(1)
        m = re.match(r"\s*booru:\s*$", line)
        if m and cur: booru[cur] = "(víceřádkové)"

metrics = {r: json.load(open(LAB / r / "metrics.json"))["cells"] for r, _, _ in VARIANTS[:1] + VARIANTS[3:4]}

def key(var, model, style, p): return f"txt2img@{var}__{model}__{style}__{p}"
def thumb(run, k, w=160):
    im = Image.open(LAB / run / "thumb" / f"{k}.jpg").convert("RGB").resize((w, w), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, "WEBP", quality=62)
    return "data:image/webp;base64," + base64.b64encode(b.getvalue()).decode()
def reaction(run, k):
    v = metrics[run].get(k, {}).get("reaction"); return v

CSS = """
:root{--bg:#f6f4ef;--fg:#1d1b17;--mute:#6d675c;--line:#d9d3c6;--card:#fffdf8;--acc:#8a4b1f;--quiet:#b23a2e;--ok:#2f6b3a;
--font:ui-sans-serif,system-ui,"Segoe UI",Roboto,sans-serif;--mono:ui-monospace,SFMono-Regular,Menlo,monospace}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#17160f;--fg:#ece7da;--mute:#a39b8b;--line:#3a362c;--card:#201e16;--acc:#e0a068;--quiet:#ef7b6e;--ok:#8fcf9a;color-scheme:dark}}
:root[data-theme=dark]{--bg:#17160f;--fg:#ece7da;--mute:#a39b8b;--line:#3a362c;--card:#201e16;--acc:#e0a068;--quiet:#ef7b6e;--ok:#8fcf9a;color-scheme:dark}
body{background:var(--bg);color:var(--fg);font:15px/1.45 var(--font);padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));padding-block:12px 40px;max-width:1200px;margin:0 auto}
h1{font-size:1.5rem;margin:.2em 0;text-wrap:balance}h2{font-size:1.1rem;margin:1.6em 0 .3em;border-top:1px solid var(--line);padding-top:.8em}
p,li{max-width:65ch}.mute{color:var(--mute)}a{color:var(--acc)}
nav{display:flex;flex-wrap:wrap;gap:6px 14px;margin:.6em 0 1em;font-size:.95rem}
table{border-collapse:collapse;font-variant-numeric:tabular-nums;font-size:.9rem}td,th{padding:3px 10px;border-bottom:1px solid var(--line);text-align:right}th:first-child,td:first-child{text-align:left}
.wrap{overflow-x:auto}
.style{margin:1.2em 0}.style h3{font-size:1rem;margin:0 0 .1em}.tags{font:.78rem/1.3 var(--mono);color:var(--mute);margin:0 0 .4em;max-width:none;word-break:break-word}
.row{display:flex;gap:6px;overflow-x:auto;padding-bottom:6px;margin-bottom:4px}.row .pl{flex:0 0 auto;width:64px;font-size:.78rem;color:var(--mute);align-self:center;line-height:1.2}
.cell{flex:0 0 auto;width:160px}.cell img{display:block;width:160px;height:160px;border-radius:3px;background:var(--line)}
.cell .cap{font-size:.72rem;line-height:1.2;color:var(--mute);margin-top:2px}.cell .r{font:.72rem var(--mono)}.cell .r.q{color:var(--quiet)}
.base img{outline:2px solid var(--line)}.sep{flex:0 0 1px;background:var(--line);margin:0 4px}
"""
HEAD = '<meta name="claude:viewport-fit-sides" content="cover">'

def doc(title, body):
    return (f'<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
            f'<title>{html.escape(title)}</title>{HEAD}<style>{CSS}</style></head><body>{body}</body></html>')

nav = '<nav><a href="index.html">Souhrn</a>' + "".join(f'<a href="{m}.html">{html.escape(l)}</a>' for m, l in MODELS) + "</nav>"

# ---- summary numbers
summary = {}
for m, _ in MODELS:
    for run, var, cap in VARIANTS:
        rs = [reaction(run, key(var, m, s, p)) for s in STYLES for p, _ in PROMPTS]
        rs = [r for r in rs if r is not None]
        summary[(m, run, var)] = (sum(rs) / len(rs), sum(r < THRESH for r in rs), len(rs))

# ---- model pages
for m, ml in MODELS:
    parts = [nav, f"<h1>7e · {html.escape(ml)}</h1>",
             "<p class=mute>Řádek = námět, sloupce = kde v promptu stojí styl a jestli jde před ním prefix kvalitních tagů. "
             "Číslo pod obrázkem je barevná vzdálenost od baseline téhož běhu (pod 0,15 červeně = model na blok skoro nereagoval). "
             "Baseline bez prefixu je vlevo od dvou buněk bez prefixu.</p>"]
    for s in STYLES:
        parts.append(f'<section class=style><h3>{html.escape(labels.get(s, s))} <span class=mute>· {s}</span></h3>'
                     f'<p class=tags>{html.escape(booru.get(s, "(bez booru textu — jde block)"))}</p>')
        for p, pl in PROMPTS:
            cells = [f'<div class=pl>{html.escape(pl)}</div>']
            for i, (run, var, cap) in enumerate(VARIANTS):
                if i in (0, 3):
                    bk = key(var, m, "__baseline", p)
                    cells.append(f'<div class="cell base"><img src="{thumb(run, bk)}" loading=lazy alt=""><div class=cap>baseline {"s prefixem" if i == 0 else "bez prefixu"}</div></div>')
                    if i == 3: pass
                k = key(var, m, s, p); r = reaction(run, k)
                rc = "" if r is None else f'<span class="r{" q" if r < THRESH else ""}">{r:.2f}</span>'
                cells.append(f'<div class=cell><img src="{thumb(run, k)}" loading=lazy alt=""><div class=cap>{html.escape(cap)} {rc}</div></div>')
                if i == 2: cells.append('<div class=sep></div>')
            parts.append('<div class=row>' + "".join(cells) + '</div>')
        parts.append("</section>")
    (OUT / f"{m}.html").write_text(doc(f"7e {ml}", "".join(parts)))
    print(m, (OUT / f"{m}.html").stat().st_size // 1024, "KB")

# ---- index
rows = []
for m, ml in MODELS:
    tds = "".join(f"<td>{summary[(m, r, v)][0]:.2f}<span class=mute> · {summary[(m, r, v)][1]}</span></td>" for r, v, _ in VARIANTS)
    rows.append(f'<tr><td><a href="{m}.html">{html.escape(ml)}</a></td>{tds}</tr>')
head = "".join(f"<th>{html.escape(c)}</th>" for _, _, c in VARIANTS)
index = f"""{nav}<h1>Vlna 7e: kam dát styl v promptu</h1>
<p>Běh 7e na L40S, 10. 11. 2026: 24 stylů (12 technik, 12 epoch a malířů) × 6 tagových modelů × 2 náměty, seed 777.
Tři polohy bloku stylu s prefixem kvalitních tagů (900 buněk) a dvě bez prefixu (600 buněk), 0 chyb.
Appka dnes posílá <em>prefix, námět, styl</em> (sloupec „styl na konci“).</p>
<h2>Barevná metrika</h2>
<p class=mute>Průměrná reakce vůči baseline téhož běhu · počet tichých dvojic (pod 0,15) ze 48. Barva nevidí, jestli postava přežila — na to jsou archy.</p>
<div class=wrap><table><tr><th>model</th>{head}</tr>{"".join(rows)}</table></div>
<h2>Co z čísel plyne a co ne</h2>
<ul>
<li>Poloha stylu barvu skoro nemění: rozdíly mezi end / front / first jsou do 0,04 u všech šesti modelů.</li>
<li>Vypnutí prefixu probudí Hassaku (6 tichých → 0) a zvedne WAI, Pony i Animagine o 0,06–0,08; u Animagine ale zároveň vyrobí 8 tichých dvojic, kde s prefixem nebyla žádná.</li>
<li>Illustrious má 0,82–0,83 ve všech pěti variantách — čmáranice bez postavy jsou v každé z nich stejně barevně vzdálené, takže o postavě rozhodne jen pohled.</li>
</ul>
<h2>Archy</h2>
<ul>{"".join(f'<li><a href="{m}.html">{html.escape(l)}</a></li>' for m, l in MODELS)}</ul>
<p class=mute>Otázky k archům: (1) Na kterém modelu dostane postava s blokem „před námětem“ nebo „bez prefixu“ zpět tělo (Illustrious)? (2) Probudí některá varianta techniku na WAI / NoobAI / Hassaku, nebo je to jen jiná barva? (3) Rozbije „styl první“ nebo „bez prefixu“ něco, co dnes funguje (Pony, Animagine)?</p>
"""
# the artifact page itself gets wrapped by the publisher: no doctype/head here
(OUT / "index.html").write_text(f"<title>Vlna 7e: poloha stylu</title>{HEAD}<style>{CSS}</style>{index}")
print("index", (OUT / "index.html").stat().st_size // 1024, "KB")
