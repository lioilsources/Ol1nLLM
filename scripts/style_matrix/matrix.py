"""Runs the dumped workflows, scores the results, builds contact sheets.

    python3 scripts/style_matrix/matrix.py run    <dir>
    python3 scripts/style_matrix/matrix.py score  <dir>
    python3 scripts/style_matrix/matrix.py sheets <dir>

`run` is resumable — anything already in <dir>/img is skipped.
"""
import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy  # noqa: E402


def _cells(d):
    """(flow, model, style) triples present as dumped workflows."""
    out = []
    for f in sorted(os.listdir(f'{d}/wf')):
        if f.endswith('.json'):
            # maxsplit=2: the baseline entry is itself called `__baseline`.
            flow, model, style = f[:-5].split('__', 2)
            out.append((flow, model, style))
    return out


def run(d, chunk=10):
    os.makedirs(f'{d}/img', exist_ok=True)
    # Grouped by model so each checkpoint loads once, not once per style.
    jobs = [(f'{flow}__{model}__{style}', model)
            for flow, model, style in _cells(d)]
    jobs.sort(key=lambda j: (j[1], j[0]))
    jobs = [n for n, _ in jobs if not os.path.exists(f'{d}/img/{n}.png')]
    print(f'{len(jobs)} jobs', flush=True)
    t0, done, fail = time.time(), 0, 0
    for i in range(0, len(jobs), chunk):
        pending = []
        for name in jobs[i:i + chunk]:
            try:
                pending.append((name, comfy.submit(
                    json.load(open(f'{d}/wf/{name}.json')))))
            except Exception as e:                      # noqa: BLE001
                print(f'FAIL submit {name}: {e}'[:160], flush=True)
                fail += 1
        for name, pid in pending:
            try:
                ims = comfy.images(comfy.wait(pid))
                if not ims:
                    raise RuntimeError('no output image')
                comfy.download(ims[0], f'{d}/img/{name}.png')
                done += 1
            except Exception as e:                      # noqa: BLE001
                print(f'FAIL run {name}: {e}'[:200], flush=True)
                fail += 1
        el = time.time() - t0
        eta = (len(jobs) - done - fail) * el / max(done, 1)
        print(f'PROGRESS {done + fail}/{len(jobs)} ok={done} fail={fail} '
              f'elapsed={el / 60:.1f}m eta={eta / 60:.1f}m', flush=True)
    print(f'DONE ok={done} fail={fail} in {(time.time() - t0) / 60:.1f}m')


# ── scoring ──────────────────────────────────────────────────────────
def _hist(path):
    from PIL import Image
    q = Image.open(path).convert('RGB').resize((96, 96), Image.LANCZOS)
    h = [0] * 512
    for r, g, b in q.getdata():
        h[(r >> 5) * 64 + (g >> 5) * 8 + (b >> 5)] += 1
    n = sum(h)
    return [x / n for x in h]


def _cos(a, b):
    num = sum(x * y for x, y in zip(a, b))
    da = math.sqrt(sum(x * x for x in a))
    db = math.sqrt(sum(y * y for y in b))
    return 1 - num / (da * db) if da and db else 1.0


def score(d):
    """Per model/flow: does the style block change anything?

    reaction = histogram distance from that model's own no-style baseline.
    spread   = mean pairwise distance among the styles (style responsiveness).
    """
    cells = _cells(d)
    groups = {}
    for flow, model, style in cells:
        p = f'{d}/img/{flow}__{model}__{style}.png'
        if os.path.exists(p):
            groups.setdefault((flow, model), {})[style] = p
    report = {}
    for (flow, model), styles in sorted(groups.items()):
        base = styles.pop('__baseline', None)
        hs = {s: _hist(p) for s, p in styles.items()}
        if not hs:
            continue
        react = ({s: round(_cos(_hist(base), h), 3) for s, h in hs.items()}
                 if base else {})
        keys = sorted(hs)
        pair = [_cos(hs[a], hs[b])
                for i, a in enumerate(keys) for b in keys[i + 1:]]
        report[f'{flow}__{model}'] = {
            'n': len(hs),
            'spread': round(sum(pair) / len(pair), 3) if pair else 0.0,
            'reaction': react,
            'weakest': min(react, key=react.get) if react else None,
        }
        print(f'{flow:10} {model:24} n={len(hs):3} '
              f'spread={report[f"{flow}__{model}"]["spread"]:.3f}'
              + (f'  nejslabší styl: {report[f"{flow}__{model}"]["weakest"]}'
                 f' ({min(react.values()):.3f})' if react else ''))
    json.dump(report, open(f'{d}/score.json', 'w'), indent=1, ensure_ascii=False)
    print(f'→ {d}/score.json')


# ── contact sheets ───────────────────────────────────────────────────
def sheets(d, size=240):
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 13)
        big = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 20)
    except OSError:
        font = big = ImageFont.load_default()
    cells = _cells(d)
    flows = sorted({f for f, _, _ in cells})
    os.makedirs(f'{d}/sheets', exist_ok=True)
    for flow in flows:
        models = sorted({m for f, m, _ in cells if f == flow})
        styles = sorted({s for f, _, s in cells if f == flow})
        head, side, pad = 44, 200, 6
        sh = Image.new('RGB',
                       (side + len(styles) * (size + pad) + pad,
                        head + len(models) * (size + pad) + pad), (12, 12, 14))
        dr = ImageDraw.Draw(sh)
        dr.text((10, 12), f'{flow} — {len(models)} modelů × {len(styles)} promptů',
                font=big, fill=(240, 240, 245))
        for j, s in enumerate(styles):
            dr.text((side + j * (size + pad) + 3, head - 18), s[:24],
                    font=font, fill=(185, 185, 195))
        for i, m in enumerate(models):
            y = head + i * (size + pad)
            dr.text((8, y + size // 2), m, font=font, fill=(235, 235, 240))
            for j, s in enumerate(styles):
                p = f'{d}/img/{flow}__{m}__{s}.png'
                cv = Image.new('RGB', (size, size), (26, 26, 30))
                if os.path.exists(p):
                    im = Image.open(p).convert('RGB')
                    k = size / max(im.size)
                    im = im.resize((int(im.width * k), int(im.height * k)),
                                   Image.LANCZOS)
                    cv.paste(im, ((size - im.width) // 2, (size - im.height) // 2))
                sh.paste(cv, (side + j * (size + pad), y))
        out = f'{d}/sheets/{flow}.png'
        sh.save(out)
        print(f'→ {out}  {sh.size[0]}×{sh.size[1]}')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    {'run': run, 'score': score, 'sheets': sheets}[sys.argv[1]](sys.argv[2])
