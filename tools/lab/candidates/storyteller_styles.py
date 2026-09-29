#!/usr/bin/env python3
"""storyteller_styles.py — styly StoryTelleru jako kandidáti pro --styles-file.

Plán: storyteller/STORYTELLER_CHARACTER_MODELS_LAB_PLAN.md §2.3.

    python3 tools/lab/candidates/storyteller_styles.py [--storyteller DIR]

Čte `infra/seed/models_styles.sql` (regex nad `INSERT INTO styles … VALUES`),
ne kopii — registr se bude měnit a kandidáti mají jít s ním. Každý řádek →
`{id, label, block, negative, preferred_model, status, sort_order}`:

- `block` = `prompt_prefix` + `prompt_suffix`, spojené jednou čárkou (SQL
  prefix končí „, “ a suffix jí začíná; doslovné spojení by dalo „, ,“).
  Pozor: appka StoryTelleru dává prefix **před** námět a suffix za něj, lab
  dá celý blok za námět (`stylePosition=end`) — pořadí se liší, slova ne.
- `negative` se labu nepředává (soubor stylů ho nečte); generátor ho vypíše
  k ručnímu použití přes `--negative`. Všechny řádky dnes sdílejí dětský
  negativ, jen `anime-lite` přidává „mature“ a `clay` nemá „realistic photo“.

Navíc osmý styl `pixar-3d` (v registru není, návrh k měření) s `booru`
textem pro anime SDXL.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(HERE, "storyteller-styles.json")

PIXAR = {
    "id": "pixar-3d",
    "label": "3D / Pixar (návrh)",
    "block": "3D animated film still, Pixar-style character render, smooth subsurface skin, "
             "big expressive eyes, soft global illumination, rounded stylized proportions",
    "booru": "3d, pixar style, cgi, smooth shading, big eyes",
    "note": "není v models_styles.sql — kandidát na nový řádek (plán §2.3), text je návrh k měření",
}

INSERT_RE = re.compile(r"INSERT\s+INTO\s+styles\s*\(([^)]*)\)\s*VALUES(.*?)\bON\s+CONFLICT",
                       re.IGNORECASE | re.DOTALL)
TOKEN_RE = re.compile(r"""\s*(?:
    (?P<str>'(?:[^']|'')*')       # SQL řetězec, '' = apostrof
  | (?P<null>NULL)\b
  | (?P<num>-?\d+(?:\.\d+)?)
  | (?P<bool>true|false)\b
  | (?P<punct>[(),])
  | (?P<comment>--[^\n]*)
)""", re.IGNORECASE | re.VERBOSE)


def parse_values(body):
    """Rozloží `(…), (…)` na seznam n-tic. Jen literály, které seed používá."""
    rows, row, depth, pos = [], None, 0, 0
    while pos < len(body):
        if body[pos:].strip() == "":
            break
        m = TOKEN_RE.match(body, pos)
        if not m:
            raise SystemExit("models_styles.sql: nečitelné u %r" % body[pos:pos + 40])
        pos = m.end()
        if m.group("comment"):
            continue
        if m.group("punct") == "(":
            depth += 1
            row = []
        elif m.group("punct") == ")":
            depth -= 1
            rows.append(row)
            row = None
        elif m.group("punct") == ",":
            continue
        elif depth != 1:
            raise SystemExit("models_styles.sql: hodnota mimo závorky: %r" % m.group(0))
        elif m.group("str") is not None:
            row.append(m.group("str")[1:-1].replace("''", "'"))
        elif m.group("null"):
            row.append(None)
        elif m.group("num"):
            row.append(float(m.group("num")))
        elif m.group("bool"):
            row.append(m.group("bool").lower() == "true")
    return rows


def join_block(prefix, suffix):
    parts = [p.strip().strip(",").strip() for p in (prefix or "", suffix or "")]
    return ", ".join(p for p in parts if p)


def styles_from_sql(sql):
    m = INSERT_RE.search(sql)
    if not m:
        raise SystemExit("models_styles.sql: nenašel jsem INSERT INTO styles")
    cols = [c.strip() for c in m.group(1).split(",")]
    out = []
    for vals in parse_values(m.group(2)):
        if len(vals) != len(cols):
            raise SystemExit("models_styles.sql: řádek má %d hodnot, sloupců je %d: %r"
                             % (len(vals), len(cols), vals[:1]))
        r = dict(zip(cols, vals))
        names = json.loads(r["name_i18n"])
        out.append({
            "id": r["id"],
            "label": "%s / %s" % (names.get("cs", r["id"]), names.get("en", r["id"])),
            "block": join_block(r["prompt_prefix"], r["prompt_suffix"]),
            "negative": r["negative"],
            "preferred_model": r["preferred_model"],
            "status": r["status"],
            "sort_order": int(r["sort_order"]) if r["sort_order"] is not None else None,
            "note": "z infra/seed/models_styles.sql; appka dává prefix před námět, lab celý blok za něj",
        })
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--storyteller", help="kořen repa storyteller")
    a = ap.parse_args()
    root = os.path.abspath(a.storyteller or os.environ.get("STORYTELLER")
                           or os.path.join(REPO, "..", "storyteller"))
    path = os.path.join(root, "infra", "seed", "models_styles.sql")
    if not os.path.isfile(path):
        sys.exit("chybí %s (--storyteller)" % path)
    styles = styles_from_sql(open(path, encoding="utf-8").read())
    styles.append(PIXAR)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(styles, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("%s: %s" % (os.path.relpath(OUT, REPO), ", ".join(s["id"] for s in styles)))
    # Negativ labu jde jen přes --negative; společný dětský je u watercolor.
    for s in styles:
        if s.get("negative"):
            print("  --negative %-11s %s" % (s["id"], json.dumps(s["negative"], ensure_ascii=False)))


if __name__ == "__main__":
    main()
