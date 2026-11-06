#!/usr/bin/env python3
"""Výsledková stránka vlny 7: stav běhů a kontaktní arch 7a se zapečenými náhledy.

    python wave7_page.py OUT.html      (spouštět z kořene repa, potřebuje Pillow)
"""
import base64, html, io, json, os, sys
from pathlib import Path
from PIL import Image

LAB = Path("build/lab")
MODELS = [("pony", "Pony V6"), ("illustrious-xl", "Illustrious"),
          ("noobai-xl", "NoobAI"), ("animagine-xl", "Animagine")]
RUNS = [("w7-7a-t777", "Závorky, seed 777", "L40S"), ("w7-7a-t778", "Závorky, seed 778", "L40S"),
        ("w7-7a-r777", "Závorky, repose", "L40S"), ("w7-7d-fixes", "Opravy 8 stylů", "L40S"),
        ("w7-7b-media", "Média a techniky", "L40S"), ("w7-7c-artists", "Umělci", "L40S"),
        ("w7-7d-cultures", "Kultury a epochy", "L40S"), ("w7-7h-booru", "Přepis tagů", "L40S"),
        ("w7-fm-fixes", "FLUX dev: opravy", "L40S"), ("w7-fm-media", "FLUX dev: média", "L40S"), ("w7-fm-artists", "FLUX dev: umělci", "L40S"), ("w7-fm-cultures", "FLUX dev: kultury", "L40S"), ("w7-sc-fixes", "FLUX Schnell: opravy", "L40S"), ("w7-sc-media", "FLUX Schnell: média", "L40S"),
        ("w7-sc-artists", "FLUX Schnell: umělci", "L40S"), ("w7-sc-cultures", "FLUX Schnell: kultury", "L40S")]
CATS_7F = [("media", "média"), ("artists", "umělci"), ("cultures", "kultury"), ("registry", "styly z registru"), ("fixes", "opravy")]
NAMES_7F = {"base": "SDXL base", "rh": "RealVis a Hassaku", "cal": "CyberRealistic, AutismMix, Lustify",
            "x": "Lightning, WAI, Atomix, SD 1.5"}
RUNS += [(f"w7-7f-{g}-{c}", f"7f {NAMES_7F[g]}: {l}", "L40S") for g in NAMES_7F for c, l in CATS_7F]


def links_7f():
    return "".join(f'<li><a href="{r}.html">{html.escape(l)}</a></li>' for r, l, _ in RUNS
                   if r.startswith("w7-7f-") and (LAB / "sheets-w7" / f"{r}.html").exists())
TABLE = [("Pony V6", .050, .146, .146, 47), ("Illustrious", .053, .283, .281, 57),
         ("NoobAI", .060, .277, .278, 53), ("Animagine", .058, .287, .283, 63)]


def thumb(path, w=220):
    im = Image.open(path).convert("RGB")
    im = im.resize((w, round(im.height * w / im.width)))
    buf = io.BytesIO()
    im.save(buf, "WEBP", quality=70)
    return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode()


def speed_rows():
    import statistics as st
    def med(run):
        g = {}
        for k, c in json.loads((LAB / run / "state.json").read_text())["cells"].items():
            if c.get("seconds"):
                g.setdefault(k.split("__")[1], []).append(c["seconds"])
        return {m: st.median(v[1:]) for m, v in g.items()}
    a, b = med("w7-cal-spark"), med("w7-cal-l40s")
    return "".join(f"<tr><td>{m}</td><td>{a[m]:.1f} s</td><td>{b[m]:.1f} s</td><td>{a[m] / b[m]:.1f}×</td></tr>" for m in sorted(a, key=lambda m: a[m] / b[m], reverse=True))


def status_rows():
    out = []
    for run, label, where in RUNS:
        p = LAB / run / "state.json"
        done = total = 0
        if p.exists():
            total = json.loads(p.read_text()).get("total", 0)
            img = LAB / run / "img"
            done = len(os.listdir(img)) if img.is_dir() else 0
        pct = round(100 * done / total) if total else 0
        state = "hotovo" if total and done >= total else ("běží nebo čeká" if done else "ve frontě")
        out.append(f'<tr><th scope="row">{label}</th><td>{where}</td><td class="n">{done} / {total or "–"}</td>'
                   f'<td><span class="bar"><i style="width:{pct}%"></i></span></td><td>{state}</td></tr>')
    return "".join(out)


def sheet():
    d = LAB / "w7-7a-t777"
    man = json.loads((d / "wf" / "manifest.json").read_text())
    ids = {(c["model"], c["style"], c["promptIndex"], (c.get("variant") or {}).get("value")): c["id"]
           for c in man["cells"]}
    labels = {c["style"]: c.get("styleLabel") or c["style"] for c in man["cells"]}
    styles = sorted(s for s in labels if s != "__baseline")
    out = []
    for s in styles:
        cells = []
        for mid, mlabel in MODELS:
            pair = "".join(
                f'<img loading="lazy" alt="{mlabel}, {tag}" src="{thumb(d / "img" / (ids[(mid, s, 0, v)] + ".png"))}">'
                for v, tag in (("natural", "bez escapování"), ("booru", "s escapováním")))
            cells.append(f'<figure><div class="pair">{pair}</div><figcaption>{mlabel}</figcaption></figure>')
        out.append(f'<section class="row"><h3>{html.escape(labels[s])}</h3><div class="models">{"".join(cells)}</div></section>')
    return "".join(out)


GALLERY = [("Média a techniky", "media", "w7-7b-media", "w7-fm-media", "w7-sc-media"),
           ("Umělci", "artists", "w7-7c-artists", "w7-fm-artists", "w7-sc-artists"),
           ("Kultury a epochy", "cultures", "w7-7d-cultures", "w7-fm-cultures", "w7-sc-cultures")]
GROUPS_7F = ("base", "rh", "cal", "x")
GMODELS = [("juggernaut-xl", "Juggernaut"), ("pony", "Pony"), ("illustrious-xl", "Illustrious"),
           ("noobai-xl", "NoobAI"), ("animagine-xl", "Animagine"), ("flux-manga", "FLUX dev"), ("flux-schnell", "Schnell"),
           ("sdxl-base", "SDXL base"), ("realvis-xl", "RealVis"), ("hassaku-illustrious", "Hassaku"),
           ("cyberrealistic-xl", "CyberRealistic"), ("autismmix-pony", "AutismMix"), ("lustify-zenith", "Lustify"),
           ("juggernaut-xl-lightning", "Lightning"), ("wai-illustrious", "WAI"),
           ("atomix-pony-anime", "Atomix"), ("sd15", "SD 1.5")]


def gallery():
    """Every candidate on one row: its text and the first subject on each model."""
    out = []
    for title, cat, *runs in GALLERY:
        cells, texts, labels = {}, {}, {}
        runs += [f"w7-7f-{g}-{cat}" for g in GROUPS_7F]
        for run in runs:
            if not (LAB / run / "wf" / "manifest.json").exists():
                continue
            for c in json.loads((LAB / run / "wf" / "manifest.json").read_text())["cells"]:
                if c["promptIndex"] == 0:
                    cells[(c["model"], c["style"])] = LAB / run / "thumb" / (c["id"] + ".jpg")
                    labels.setdefault(c["style"], c.get("styleLabel") or c["style"])
                    if c["model"] == "juggernaut-xl":
                        texts[c["style"]] = c.get("styleText") or ""
        styles = ["__baseline"] + sorted((x for x in labels if x != "__baseline"), key=lambda x: labels[x].lower())
        shown = [(mid, m) for mid, m in GMODELS if any((mid, x) in cells for x in styles)]
        rows = []
        for st in styles:
            figs = "".join(
                f'<figure><img loading="lazy" alt="{m}" src="{thumb(cells[(mid, st)], 104)}"><figcaption>{m}</figcaption></figure>'
                if (mid, st) in cells and cells[(mid, st)].exists() else f'<figure><div class="miss"></div><figcaption>{m}</figcaption></figure>'
                for mid, m in shown)
            name = "bez stylu (srovnání)" if st == "__baseline" else labels[st]
            pick = "" if st == "__baseline" else (
                f'<button type="button" class="pick" data-id="{html.escape(st)}" aria-pressed="false" hidden>Vyřadit</button>')
            attr = "" if st == "__baseline" else f' data-id="{html.escape(st)}" data-label="{html.escape(name)}"'
            rows.append(f'<div class="cand"{attr}><div class="ctext"><div class="chead"><b>{html.escape(name)}</b>{pick}</div>'
                        f'<code>{html.escape(texts.get(st, ""))}</code></div><div class="strip">{figs}</div></div>')
        n = len(styles) - 1
        out.append(f'<details style="--n:{len(shown)}"{" open" if not out else ""}><summary>{title} <span>{n} kandidátů</span></summary>{"".join(rows)}</details>')
    return "".join(out)


CSS = """
:root{--bg:#f3f1ee;--fg:#1d1b22;--dim:#67626f;--line:#d6d1cb;--panel:#fff;--accent:#6a3df0;--track:#e3dfda;--drop:#b42318}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15131a;--fg:#ece9f2;--dim:#a49eb0;--line:#332f3b;--panel:#1e1b25;--accent:#a98bff;--track:#2c2834;--drop:#d4493a;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#15131a;--fg:#ece9f2;--dim:#a49eb0;--line:#332f3b;--panel:#1e1b25;--accent:#a98bff;--track:#2c2834;--drop:#d4493a;color-scheme:dark}
body{background:var(--bg);color:var(--fg);font:16px/1.55 "Instrument Sans",system-ui,sans-serif}
main{max-width:1180px;margin:0 auto;padding-block:40px 72px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));display:grid;gap:44px}
h1{font:600 clamp(34px,6vw,58px)/1.05 "Fraunces",Georgia,serif;margin:0;text-wrap:balance}
h2{font:600 26px/1.2 "Fraunces",Georgia,serif;margin:0 0 12px;text-wrap:balance}
h3{font:500 13px/1.3 "IBM Plex Mono",ui-monospace,monospace;margin:0 0 8px;color:var(--dim)}
p{max-width:68ch;margin:0 0 10px}.lead{font-size:19px}
.wrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}
th,td{text-align:left;padding:8px 14px 8px 0;border-bottom:1px solid var(--line);font-weight:400;white-space:nowrap}
thead th{color:var(--dim);font-size:13px}td.n{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:14px}
.bar{display:block;width:120px;height:6px;background:var(--track)}.bar i{display:block;height:100%;background:var(--accent)}
.row{border-top:1px solid var(--line);padding-top:12px}.rows{display:grid;gap:22px}
.models{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}
@media (max-width:760px){.models{grid-template-columns:repeat(2,minmax(0,1fr))}}
figure{margin:0;min-width:0}.pair{display:grid;grid-template-columns:1fr 1fr;gap:2px}.pair img{width:100%;display:block}
figcaption{font-size:12px;color:var(--dim);margin-top:4px}
details{border-top:1px solid var(--line);padding-top:10px}summary{cursor:pointer;font:600 20px/1.3 "Fraunces",Georgia,serif;padding:6px 0}summary span{font:400 14px "Instrument Sans",system-ui,sans-serif;color:var(--dim);margin-left:8px}
.cand{display:grid;gap:8px;padding:12px 0;border-bottom:1px solid var(--line)}
.ctext b{display:block;font-weight:600;margin-bottom:4px}.ctext code{font:12px/1.45 "IBM Plex Mono",ui-monospace,monospace;color:var(--dim);display:block;overflow-wrap:anywhere}
.strip{display:grid;grid-template-columns:repeat(var(--n),minmax(0,1fr));gap:6px}.strip img,.miss{width:100%;aspect-ratio:2/3;object-fit:cover;display:block;background:var(--track)}
@media (max-width:760px){.strip{grid-template-columns:repeat(4,minmax(0,1fr))}}
.chead{display:flex;align-items:baseline;justify-content:space-between;gap:12px}
.pick{font:500 13px "Instrument Sans",system-ui,sans-serif;padding:5px 12px;border:1px solid var(--line);border-radius:999px;background:var(--panel);color:var(--dim);cursor:pointer;flex:none}
.pick:hover{border-color:var(--fg);color:var(--fg)}
.pick[aria-pressed="true"]{background:var(--drop);border-color:var(--drop);color:#fff}
.cand.dropped .strip{opacity:.35}.cand.dropped .ctext b{text-decoration:line-through;color:var(--dim)}
.verdict{position:sticky;top:0;z-index:2;background:var(--bg);border-bottom:1px solid var(--line);padding:10px 0;display:flex;flex-wrap:wrap;gap:8px 16px;align-items:center;font-size:14px}
.verdict b{font-weight:600}.verdict .dim{color:var(--dim)}.verdict label{display:flex;gap:6px;align-items:center;cursor:pointer}
.verdict ul{flex-basis:100%;margin:0;padding:0;list-style:none;display:flex;flex-wrap:wrap;gap:4px 12px;color:var(--dim)}
body.only-dropped .cand:not(.dropped){display:none}
"""


JS = """
const bar = document.getElementById("verdict"), list = bar.querySelector("ul"), count = bar.querySelector("#vcount");
const cands = [...document.querySelectorAll(".cand[data-id]")];
let dropped = new Map();
function render() {
  for (const c of cands) {
    const on = dropped.has(c.dataset.id);
    c.classList.toggle("dropped", on);
    const b = c.querySelector(".pick"); b.setAttribute("aria-pressed", on); b.textContent = on ? "Vyřazeno" : "Vyřadit";
  }
  count.textContent = dropped.size ? `Vyřazeno ${dropped.size} z ${cands.length}` : `Všech ${cands.length} stylů zůstává`;
  list.replaceChildren(...[...dropped.values()].sort().map(l => Object.assign(document.createElement("li"), {textContent: l})));
}
document.getElementById("onlydrop").onchange = e => document.body.classList.toggle("only-dropped", e.target.checked);
(async () => {
  const db = await claude.use("db"), user = await claude.use("user");
  const note = bar.querySelector(".dim");
  if (!db) { note.textContent = "Výběr se tu nedá uložit, otevři stránku přihlášený na claude.ai."; return; }
  const col = db.collection("verdicts");
  const canWrite = user ? await user.isOwner() : false;
  const t = setTimeout(() => note.textContent = "Výběr se nenačetl.", 10000);
  col.onSnapshot(snap => {
    clearTimeout(t);
    dropped = new Map(snap.docs.filter(d => d.data().drop).map(d => [d.id, d.data().label || d.id]));
    note.textContent = canWrite ? "Výchozí je ponechat. Klepni na Vyřadit u stylu, který do appky nechceš, výběr se ukládá hned." : "Výběr dělá vlastník stránky.";
    render();
  }, () => { clearTimeout(t); note.textContent = "Výběr se nenačetl."; });
  if (!canWrite) return;
  for (const c of cands) {
    const b = c.querySelector(".pick"); b.hidden = false;
    b.onclick = async () => {
      const id = c.dataset.id, doc = col.doc(id); b.disabled = true;
      try { dropped.has(id) ? await doc.delete() : await doc.set({drop: true, label: c.dataset.label}); }
      catch { note.textContent = "Uložení se nepovedlo, zkus to znovu."; }
      finally { b.disabled = false; }
    };
  }
})();
"""


def page():
    rows = "".join(f'<tr><th scope="row">{m}</th><td class="n">{a:.3f}</td><td class="n">{b:.3f}</td>'
                   f'<td class="n">{c:.3f}</td><td class="n">{p} %</td></tr>' for m, a, b, c, p in TABLE)
    return f"""<title>Vlna 7 stylů</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600&family=IBM+Plex+Mono&family=Instrument+Sans:wght@400;600&display=swap">
<style>{CSS}</style>
<main>
<header><h1>Vlna 7 stylů</h1>
<p class="lead">243 nových stylů je změřeno na všech 17 modelech, které appka umí pro txt2img. První kolo je kompletní. O tom, co půjde do appky, rozhoduješ ty.</p></header>
<section><h2>Nové styly</h2><p>Každý kandidát vlny 7 na jednom řádku: jeho text a týž námět na všech modelech, které už ho prošly, seed 777. FLUX dev a Schnell jely na L40S s vahami fp8, jsou jen předvýběr. Deset modelů, které dřív nikdo neměřil (SDXL base, RealVis, Hassaku, CyberRealistic, AutismMix, Lustify, Juggernaut Lightning, WAI, Atomix, SD 1.5), jelo na L40S celé, i přes 82 stylů z registru. Nahoře je pro srovnání obrázek bez stylu. Do appky zatím nic nešlo, vybíráš ty. Oba náměty a všechny varianty jsou v archech níž.</p><div class="verdict" id="verdict"><b id="vcount"></b><label><input type="checkbox" id="onlydrop"> jen vyřazené</label><span class="dim">Načítám výběr…</span><ul></ul></div>{gallery()}</section>
<section><h2>Stav měření</h2><div class="wrap"><table><thead><tr><th>běh</th><th>stroj</th><th>obrázky</th><th>průběh</th><th>stav</th></tr></thead><tbody>{status_rows()}</tbody></table></div></section>
<section><h2>Závorky v tazích styl nezměnily</h2>
<p>Tag <code>oil painting (medium)</code> šel do ComfyUI bez escapování, takže ho model nedostal celý. Oprava je správná a zůstává. Čekal jsem, že přinese médium i na Pony, ale měření to nepotvrdilo: obrázek s opravou a bez ní jsou si 3–5× blíž než kterýkoli z nich obrázku bez stylu a žádný směr nevyhrává.</p>
<div class="wrap"><table><thead><tr><th>model</th><th>s opravou × bez</th><th>s opravou × bez stylu</th><th>bez opravy × bez stylu</th><th>s opravou dál od bez stylu</th></tr></thead><tbody>{rows}</tbody></table></div>
<p style="margin-top:10px;color:var(--dim)">Průměrný rozdíl pixelů, 240 párů na dvou námětech a dvou seedech. Měří barvu, ne převzetí stylu.</p></section>
<section><h2>Rychlost: SPARK a L40S</h2><div class="wrap"><table><thead><tr><th>model</th><th>SPARK</th><th>L40S</th><th>L40S rychlejší</th></tr></thead><tbody>{speed_rows()}</tbody></table></div><p style="margin-top:10px;color:var(--dim)">Medián na buňku od odeslání po stažení, 19 buněk na model, jedna naráz, po načtení modelu. flux-manga má na L40S fp8, na SPARKu jiné váhy, takže jeho řádek není čisté srovnání strojů. SPARK šel přes comfyui.ol1n.com, tedy Cloudflare, L40S přes SSH tunel, takže část rozdílu je síť. Opakování po LAN narušila další zátěž GPU a je použitelné jen u animagine-xl: 12,5 s proti 15,4 s přes Cloudflare, tedy tam 1,6× místo 2,0×. flux-schnell tu chybí, na SPARKu nefunguje.</p></section>\n<section><h2>Archy běhů</h2><ul><li><a href="w7-7d-fixes.html">Opravy 8 stylů, starý a nový text</a></li><li><a href="w7-7b-media-1.html">Média a techniky, část 1 (akryl až linoryt)</a></li><li><a href="w7-7b-media-2.html">Média a techniky, část 2 (linoryt až rentgen)</a></li><li><a href="w7-7c-artists.html">Umělci</a></li><li><a href="w7-7d-cultures.html">Kultury a epochy</a></li><li><a href="w7-7h-booru-1.html">Přepis tagů, část 1</a></li><li><a href="w7-7h-booru-2.html">Přepis tagů, část 2</a></li><li><a href="w7-fm-fixes.html">flux-manga: opravy</a></li><li><a href="w7-fm-media.html">flux-manga: média</a></li><li><a href="w7-fm-artists.html">flux-manga: umělci</a></li><li><a href="w7-fm-cultures.html">flux-manga: kultury</a></li><li><a href="w7-7a-r777.html">Závorky v repose</a></li><li><a href="w7-sc-fixes.html">FLUX Schnell: opravy</a></li><li><a href="w7-sc-media.html">FLUX Schnell: média</a></li><li><a href="w7-sc-artists.html">FLUX Schnell: umělci</a></li><li><a href="w7-sc-cultures.html">FLUX Schnell: kultury</a></li>{links_7f()}</ul><p style="color:var(--dim)">Pět modelů SDXL, dva náměty, seed 777. FLUX se měří zvlášť. Nic není vyřazené.</p></section>
<section><h2>Kontaktní arch</h2><p>Každá dvojice je vlevo bez opravy a vpravo s opravou, stejný seed. Námět baletka, 15 stylů, 4 tagové modely.</p><div class="rows">{sheet()}</div></section>
</main>
<script>{JS}</script>"""


if __name__ == "__main__":
    Path(sys.argv[1]).write_text(page())
