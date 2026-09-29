#!/usr/bin/env python3
"""storyteller_cast.py — vzorek postav StoryTelleru pro lab.

Plán: storyteller/STORYTELLER_CHARACTER_MODELS_LAB_PLAN.md §2.1–2.2.

    python3 tools/lab/candidates/storyteller_cast.py select   # → storyteller-cast.json + reference
    python3 tools/lab/candidates/storyteller_cast.py yaml     # → storyteller-cast{,-tier0}.yaml (z JSON)
    python3 tools/lab/candidates/storyteller_cast.py          # obojí

`select` čte repo storyteller (jen čtení): text postavy z
`rag/data/{world,cz,motif}_cards.json`, české jméno z `cards.cs.jsonl`
(řádky `length == "title"`), zemi z packů `rag/data/packs/*.db` a obrázek
tier 0 z `rag/data/motif_images/<id>.jpg`, který zkopíruje do
`build/lab/refs/storyteller/<key>.jpg` (build/ je v .gitignore — obrázky do
gitu nepatří). Seed je týž, pod kterým obrázek vyrobil `render-motifs`
(§0 plánu), takže vlna B může pustit „tier 0 znovu pod tímtéž seedem“.

`yaml` z JSON napíše prompty pro `--prompts-yaml`: tělo bez stylu (styl je
v labu vlastní osa), pro tři rodiny modelů. Klíč položky = `key` postavy,
takže `--prompt-ids fox,dragon` vybírá postavy.

Cestu k repu storyteller bere z `--storyteller`, `$STORYTELLER`, jinak
`<kořen Ol1nLLM>/../storyteller`.
"""
import argparse
import glob
import hashlib
import json
import os
import shutil
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CAST_JSON = os.path.join(HERE, "storyteller-cast.json")
CAST_YAML = os.path.join(HERE, "storyteller-cast.yaml")
CAST_TIER0_YAML = os.path.join(HERE, "storyteller-cast-tier0.yaml")
REFS = os.path.join(REPO, "build", "lab", "refs", "storyteller")

# Výběr (§2.1): 6 lidí, 6 zvířat, 5 nadpřirozených, 3 věci. Přednost mají
# postavy s českým jménem v packu; id se hledala podle text_en. Obrázky
# z app/assets/cast/*.jpg nejsou motif_images (jiné soubory, jiné id), takže
# „viditelné v appce“ tu znamená stejnou postavu (liška, drak, vodník, sluha…),
# ne týž obrázek.
#
# Odchylky od seznamu v plánu, protože takové id s obrázkem neexistuje:
# - mluvící mlýn: v korpusu není (jen mlynáři) → mluvící „Moudrý kámen“,
# - kouzelný předmět: jediný čistý je kouzelná květina (láme kletby),
# - had: jediný samotný had je „Bílý had z jezera“ (Hadí král je napůl člověk).
PICKS = [
    # lidé
    ("child", "8c4863a20f1c752b", "person"),            # Chytrá Anička (Jeníček a Mařenka)
    ("youngest-son", "3a3365f00caa094e", "person"),     # Ivan Durák
    ("princess", "6b5324095e421756", "person"),         # Zlatovláska
    ("old-woman", "53a25fc6ee60fbbe", "person"),        # Babička z lesa
    ("blacksmith", "6f3ea8e2cf43bcf9", "person"),       # Kovář Mustafa
    ("servant", "98a283cd49943f48", "person"),          # Chytrý sluha
    # zvířata
    ("fox", "fc5ee8dd1600bb0e", "animal"),              # Chytrá liška (kontrola seedu)
    ("golden-bird", "5f28650a078076c0", "animal"),      # Zlatý ptáček
    ("bear", "79ee7ea7f0452d59", "animal"),             # Medvěd Brumla
    ("fish", "54fcbd66b67e27d9", "animal"),             # kouzelná ryba (O rybáři a jeho ženě)
    ("horse", "59290a892dec702f", "animal"),            # mluvící kůň (Falada, Husopaska)
    ("snake", "8991eac495aaf687", "animal"),            # Bílý had z jezera
    # nadpřirození
    ("dragon", "8bb037ec49fe9315", "supernatural"),     # Drak z Alp
    ("water-sprite", "9d5dc320c3f422ef", "supernatural"),  # Vodník z řeky
    ("witch", "007b5c578424e208", "supernatural"),      # Zlá čarodějnice
    ("giant", "88578bcaaf50fdab", "supernatural"),      # Veliký obr Hora
    ("elf", "6f355e279baa2ba8", "supernatural"),        # Chytrý skřítek
    # věci
    ("wise-stone", "83942e103a435d2d", "object"),       # Moudrý kámen (místo mluvícího mlýna)
    ("magic-flower", "6584f0b9d590f779", "object"),     # kouzelná květina
    ("tree", "e1b5411142bf5e6f", "object"),             # Malý smrček
]

# Tělo promptu po rodinách (§2.2). `flux` je prompt `render-motifs` bez slova
# „Watercolor“ a bez stylové věty, aby šel styl měnit beze změny námětu.
BODIES = {
    # Bez tečky na konci: lab připojí styl za námět přes „, “, a tečka by dala
    # „background., soft watercolor…“. Dnešní prompt má za „background“ taky čárku.
    "flux": "A character portrait of {t}. One figure, full body, standing on a plain soft cream background",
    "juggernaut": "a full body character portrait of {t}, one figure standing on a plain soft cream background",
    # Fráze uvnitř tagů: Pony/Illustrious tu měří i překlad fráze, ne jen model.
    "danbooru": "solo, full body, standing, simple background, {t}",
}


# Přesný prompt `render-motifs -kind character` (storyteller
# internal/nimqueue/cmd/render-motifs: characterPrefix + text + characterStyle).
# Jde do zvláštního souboru storyteller-cast-tier0.yaml, jen pro flux-schnell
# s --no-styles a seedem postavy: kontrola, že lab reprodukuje dnešní obrázek.
# V hlavním YAML by se s během bez --prompt-ids násobil.
TIER0 = ("Watercolor character portrait: {t}. One figure, full body, standing on a plain "
         "soft cream background, soft warm colors, gentle storybook painting.")


def seed_of(motif_id):
    """contentkey.Seed(sha256("character\\x1f"+id)) oříznutý na 32 bitů (NIM)."""
    h = hashlib.sha256(("character\x1f" + motif_id).encode()).hexdigest()
    return (int(h[:16], 16) & 0x7FFFFFFFFFFFFFFF) & 0xFFFFFFFF


# Ověřeno proti Go implementaci (plán §0); spadne, kdyby se vzorec rozešel.
assert seed_of("fc5ee8dd1600bb0e") == 1499655865, seed_of("fc5ee8dd1600bb0e")


def storyteller_root(arg):
    root = arg or os.environ.get("STORYTELLER") or os.path.join(REPO, "..", "storyteller")
    root = os.path.abspath(root)
    if not os.path.isdir(os.path.join(root, "rag", "data")):
        # Worktree Ol1nLLM-lab leží vedle Ol1nLLM, takže ../storyteller sedí
        # i tam; jinde je potřeba --storyteller.
        sys.exit("nenašel jsem storyteller/rag/data v %s (--storyteller)" % root)
    return root


def select(root):
    data = os.path.join(root, "rag", "data")
    texts = {}
    for name in ("world_cards.json", "cz_cards.json", "motif_cards.json"):
        for row in json.load(open(os.path.join(data, name), encoding="utf-8")):
            texts.setdefault(row["id"], row["text_en"])
    titles = {}
    with open(os.path.join(data, "cards.cs.jsonl"), encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            if row.get("length") == "title":
                titles.setdefault(row["motif_id"], row["text"])
    countries = {}
    for db in sorted(glob.glob(os.path.join(data, "packs", "*.db"))):
        # read-only URI: repo storyteller se jen čte
        con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
        try:
            for mid, cc in con.execute("SELECT id, country_code FROM motifs"):
                if cc:
                    countries.setdefault(mid, cc)
        except sqlite3.OperationalError:
            pass
        finally:
            con.close()

    os.makedirs(REFS, exist_ok=True)
    cast, errors = [], []
    for key, mid, category in PICKS:
        img = os.path.join(data, "motif_images", mid + ".jpg")
        if mid not in texts:
            errors.append("%s: id %s není v *_cards.json" % (key, mid))
            continue
        if not os.path.isfile(img):
            errors.append("%s: chybí %s" % (key, img))
            continue
        row = {"key": key, "id": mid, "text_en": texts[mid]}
        if mid in titles:
            row["cs_name"] = titles[mid]
        row.update({"category": category, "country": countries.get(mid, ""),
                    "seed": seed_of(mid), "ref": "build/lab/refs/storyteller/%s.jpg" % key})
        cast.append(row)
        shutil.copyfile(img, os.path.join(REFS, key + ".jpg"))
    if errors:
        sys.exit("\n".join(errors))
    keys = [c["key"] for c in cast]
    assert len(set(keys)) == len(keys), "duplicitní key"
    with open(CAST_JSON, "w", encoding="utf-8") as f:
        json.dump(cast, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("%s: %d postav, reference v %s" % (os.path.relpath(CAST_JSON, REPO), len(cast),
                                              os.path.relpath(REFS, REPO)))


def q(s):
    # JSON řetězec je platný YAML double-quoted scalar.
    return json.dumps(s, ensure_ascii=False)


def write_yaml():
    cast = json.load(open(CAST_JSON, encoding="utf-8"))
    out = [
        "# Vygenerováno: tools/lab/candidates/storyteller_cast.py yaml — neupravovat ručně.",
        "# Postavy StoryTelleru (storyteller-cast.json), tělo promptu bez stylu:",
        "# styl je v labu vlastní osa (--styles-file candidates/storyteller-styles.json).",
        "# Klíč = key postavy, výběr přes --prompt-ids; seed postavy je v JSON.",
        "",
    ]
    for c in cast:
        t = c["text_en"]
        label = " / ".join(x for x in (c.get("cs_name"), c["category"], c["country"], c["id"]) if x)
        out.append("# %s" % label)
        out.append("%s:" % c["key"])
        for fam in ("danbooru", "juggernaut", "flux"):
            out.append("  %s: %s" % (fam, q(BODIES[fam].format(t=t))))
        out.append("")
    with open(CAST_YAML, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print("%s: %d promptů" % (os.path.relpath(CAST_YAML, REPO), len(cast)))

    t0 = [
        "# Vygenerováno: tools/lab/candidates/storyteller_cast.py yaml — neupravovat ručně.",
        "# Přesný prompt render-motifs -kind character (tier 0 StoryTelleru), jen flux.",
        "# Kontrola reprodukce, po postavě s jejím seedem ze storyteller-cast.json:",
        "#   lab run --prompts-yaml candidates/storyteller-cast-tier0.yaml --prompt-ids fox \\",
        "#           --models flux-schnell --flows txt2img --no-styles --seed 1499655865",
        "# Karty přegenerované přes render-motifs -reroll mají jiný seed a nesednou.",
        "",
    ]
    for c in cast:
        t0.append("%s:" % c["key"])
        t0.append("  flux: %s" % q(TIER0.format(t=c["text_en"])))
    with open(CAST_TIER0_YAML, "w", encoding="utf-8") as f:
        f.write("\n".join(t0) + "\n")
    print("%s: %d promptů" % (os.path.relpath(CAST_TIER0_YAML, REPO), len(cast)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cmd", nargs="?", choices=("select", "yaml", "all"), default="all")
    ap.add_argument("--storyteller", help="kořen repa storyteller")
    a = ap.parse_args()
    if a.cmd in ("select", "all"):
        select(storyteller_root(a.storyteller))
    if a.cmd in ("yaml", "all"):
        write_yaml()


if __name__ == "__main__":
    main()
