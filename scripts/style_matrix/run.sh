#!/usr/bin/env bash
# Style/model matrix: how each installed model renders each style preset,
# through the app's own workflow builder.
#
#   ./scripts/style_matrix/run.sh --ref-prompt "photo of a dancer, full body"
#   ./scripts/style_matrix/run.sh --ref my.png --flows repose --models pony,juggernaut-xl
#   ./scripts/style_matrix/run.sh --ref my.png --styles ukiyoe,baroque --edit-denoise 0.9
#
# Needs CF Access creds — taken from .env.local in the repo root.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="build/style-matrix/$(date +%Y%m%d-%H%M%S)"
REF=""; REF_PROMPT=""; FLOWS="repose,img2img"; MODELS=""; STYLES=""
SEED="777"; EDIT_DENOISE=""; STEP="all"
SUBJECT="a ballerina in leggings and a short ballet skirt, standing on pointe on one leg with the other leg raised straight up beside her head"

while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="$2"; shift 2;;
    --ref-prompt) REF_PROMPT="$2"; shift 2;;
    --subject) SUBJECT="$2"; shift 2;;
    --flows) FLOWS="$2"; shift 2;;
    --models) MODELS="$2"; shift 2;;
    --styles) STYLES="$2"; shift 2;;
    --seed) SEED="$2"; shift 2;;
    --edit-denoise) EDIT_DENOISE="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --step) STEP="$2"; shift 2;;   # dump | run | score | sheets | all
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    *) echo "neznámý přepínač: $1" >&2; exit 2;;
  esac
done

[ -f .env.local ] && { set -a; . ./.env.local; set +a; }
mkdir -p "$OUT"
export COMFYUI_URL="${COMFYUI_URL:-https://comfyui.ol1n.com}"

# 1 · reference image (the pose every flow works from)
if [ -z "$REF" ] && [ -n "$REF_PROMPT" ]; then
  echo "▸ generuji referenci…"
  REF="$OUT/reference.png"
  SUBJECT_REF="$REF_PROMPT" OUT_DIR="$OUT/refwf" REF_SEED="$SEED" \
    python3 - "$OUT" <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, 'scripts/style_matrix'); import comfy
out = sys.argv[1]
# One plain txt2img on the first installed checkpoint, portrait bucket.
wf = json.load(open('assets/comfyui/sdxl_txt2img.api.json'))
ckpt = next(c for c in comfy.checkpoints() if 'XL' in c or 'xl' in c)
for n in wf.values():
    i = n['inputs']
    for k, v in list(i.items()):
        if v == '__CKPT__': i[k] = ckpt
        if v == '__PROMPT__': i[k] = os.environ['SUBJECT_REF']
        if v == '__NEGATIVE__': i[k] = ''
    if n['class_type'] == 'EmptyLatentImage':
        i.update(width=832, height=1216, batch_size=1)
    if 'seed' in i: i['seed'] = int(os.environ['REF_SEED'])
comfy.download(comfy.images(comfy.wait(comfy.submit(wf)))[0], f'{out}/reference.png')
print('  →', f'{out}/reference.png')
PY
fi
[ -n "$REF" ] || { echo "chybí --ref nebo --ref-prompt" >&2; exit 2; }

REF_NAME=""
if [ "$STEP" = "all" ] || [ "$STEP" = "dump" ]; then
  echo "▸ nahrávám referenci na server…"
  REF_NAME=$(python3 -c "
import sys; sys.path.insert(0,'scripts/style_matrix'); import comfy
print(comfy.upload('$REF','style_matrix_ref.png'))")
  echo "  → $REF_NAME"

  echo "▸ zjišťuji nainstalované checkpointy…"
  python3 -c "
import sys; sys.path.insert(0,'scripts/style_matrix'); import comfy
open('$OUT/ckpts.txt','w').write('\n'.join(comfy.checkpoints()))"

  echo "▸ generuji workflow přes kód appky…"
  OUT_DIR="$OUT/wf" REF_NAME="$REF_NAME" REF_FILE="$REF" SUBJECT="$SUBJECT" \
  SEED="$SEED" FLOWS="$FLOWS" MODELS="$MODELS" STYLES="$STYLES" \
  CKPTS="$OUT/ckpts.txt" ${EDIT_DENOISE:+EDIT_DENOISE="$EDIT_DENOISE"} \
    flutter test scripts/style_matrix/dump.dart 2>&1 | grep -E 'DUMP|Some tests'
fi

[ "$STEP" = "all" ] || [ "$STEP" = "run" ]    && python3 scripts/style_matrix/matrix.py run    "$OUT"
[ "$STEP" = "all" ] || [ "$STEP" = "score" ]  && python3 scripts/style_matrix/matrix.py score  "$OUT"
[ "$STEP" = "all" ] || [ "$STEP" = "sheets" ] && python3 scripts/style_matrix/matrix.py sheets "$OUT"
echo "▸ hotovo: $OUT"
