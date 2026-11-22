"""Rank the native artist and character candidates by how much the models saw
of them: the number of posts each tag has on danbooru.

    python3 tools/lab/danbooru_top.py

Reads `candidates/native-{artists,characters}.yaml` (from the working tree, or
from the branch they still live on) and writes
`candidates/native-{artists,characters}-ranked.tsv` — key, danbooru tag, post
count, most posts first. `complete.sh` with LIMIT=N takes the first N of that.

A tag danbooru does not have (renamed, merged, or never one) gets 0 and sinks
to the bottom; the summary says how many.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
BRANCH = "lab/prompt-candidates"
API = "https://danbooru.donmai.us/tags.json"


def keys_of(kind: str) -> list[str]:
    path = HERE / "candidates" / f"native-{kind}.yaml"
    if path.exists():
        text = path.read_text(encoding="utf-8")
    else:
        text = subprocess.run(
            ["git", "-C", str(HERE), "show", f"{BRANCH}:tools/lab/candidates/native-{kind}.yaml"],
            check=True, capture_output=True, text=True,
        ).stdout
    keys = []
    for line in text.splitlines():
        if not line.strip() or line[0] in " #":
            continue
        m = re.match(r"^(?:'((?:[^']|'')*)'|([^:#'][^:]*)):\s*$", line)
        if m:
            keys.append(m.group(1).replace("''", "'") if m.group(1) is not None else m.group(2).strip())
    return [k for k in keys if k != "baseline"]


def tag_of(kind: str, key: str) -> str:
    """The danbooru tag a candidate stands for. A character's key is
    "character, series"; the character tag is the part before the series."""
    name = key.rsplit(", ", 1)[0] if kind == "characters" and ", " in key else key
    return name.strip().lower().replace(" ", "_")


def counts(tags: list[str]) -> dict[str, int]:
    out: dict[str, int] = {}
    for i in range(0, len(tags), 100):
        batch = tags[i:i + 100]
        q = urllib.parse.urlencode({
            "search[name_comma]": ",".join(batch), "limit": 1000,
            "only": "name,post_count",
        })
        req = urllib.request.Request(f"{API}?{q}", headers={"User-Agent": "ol1n-lab/1 (tag counts)"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    for t in json.loads(r.read()):
                        out[t["name"]] = t["post_count"]
                break
            except Exception as e:  # noqa: BLE001 — a rate limit or a blip
                if attempt == 3:
                    raise SystemExit(f"danbooru: {e}") from None
                time.sleep(5 * (attempt + 1))
        print(f"  {min(i + 100, len(tags))}/{len(tags)}", flush=True)
        time.sleep(0.6)
    return out


def main() -> None:
    for kind in ("artists", "characters"):
        keys = keys_of(kind)
        tags = {k: tag_of(kind, k) for k in keys}
        print(f"{kind}: {len(keys)} kandidátů")
        got = counts(sorted(set(tags.values())))
        rows = sorted(((got.get(tags[k], 0), k) for k in keys), key=lambda r: (-r[0], r[1]))
        dst = HERE / "candidates" / f"native-{kind}-ranked.tsv"
        dst.write_text("".join(f"{k}\t{tags[k]}\t{n}\n" for n, k in rows), encoding="utf-8")
        missing = sum(1 for n, _ in rows if n == 0)
        print(f"  → {dst.name}: nejvíc {rows[0][1]} ({rows[0][0]}), stý {rows[99][1]} ({rows[99][0]}), "
              f"bez tagu na danbooru {missing}")


if __name__ == "__main__":
    sys.exit(main())
