#!/bin/zsh
# The whole matrix from one photo: the person's pose and face (repose with
# face identity) on every model, in every style of the registry, and — on the
# tag-reading models — as every native artist and every native character.
#
#   tools/lab/complete.sh photo.jpg            (or: make lab-complete REF=photo.jpg)
#
# This is tens of thousands of cells and weeks of GPU, so it is built to be
# left alone: it only works inside the hours ComfyUI is scheduled on SPARK
# (WINDOWS), stops the lab at the end of a window and picks every run up where
# it stopped in the next one. Killing the script and starting it again with
# the same photo continues too — nothing is generated twice.
#
# The UI's 400-cell ceiling does not apply: it lives in the server's
# estimate, and this drives the terminal `lab run`, which never asked.
#
# One lab run per part, so each is its own FINETUNE session and its own style
# map later:
#   complete-<name>-styles              every model × every style (+ baseline)
#   complete-<name>-artists-<model>     one tag model × ~980 artists
#   complete-<name>-characters-<model>  one tag model × ~3900 characters
#
# On a shared ComfyUI the lab waits for an empty queue before every cell,
# leaves a pause after it, and stops the whole thing when a cell takes longer
# than MAX_CELL seconds — that is ComfyUI computing on the CPU, and the box
# overheats. FLUX models are left out: their identity path and the NIM next
# door do not fit into the window's memory.
#
# Knobs (environment):
#   NAME      id of the matrix (default: the photo's file name)
#   SUBJECT   who is in the photo, as a sentence — the styles part
#   TAGS      the same in danbooru tags — prefix of artists and characters
#   FACE      instantid | faceid | both | none   (FLUX always uses PuLID)
#   PARTS     "styles artists characters", any subset, in this order
#   MODELS    comma list for the styles part (default: every installed SDXL
#             model that can do repose)
#   TAG_MODELS comma list for artists/characters (default: NoobAI,
#             Illustrious, WAI and Animagine — the lines that know the tags)
#   PAUSE     seconds between cells (default 2.5)
#   MAX_CELL  seconds a cell may take before the run is stopped (default 120;
#             MAX_FIRST_CELL, default 300, for the first cell of a model)
#   WINDOWS   "HH:MM-HH:MM ..." when ComfyUI may be used; a window may cross
#             midnight. "always" switches the clock off.
#   TOP       only the top N artists/characters by danbooru post count
#             (candidates/native-*-ranked.tsv, written by danbooru_top.py)
#   DRY=1     no ComfyUI, placeholders, no waiting — to see the plan
set -u

REF=${1:?"chybí fotka: tools/lab/complete.sh <fotka>"}
[[ -f $REF ]] || { echo "fotka $REF neexistuje" >&2; exit 2; }
REF=${REF:A}
ROOT=${0:A:h:h:h}
cd $ROOT/tools/lab

NAME=${NAME:-${${REF:t:r}//[^A-Za-z0-9_-]/-}}
SUBJECT=${SUBJECT:-"full body photo of a young woman, photorealistic"}
TAGS=${TAGS:-"1girl, solo, full body"}
FACE=${FACE:-faceid}
PARTS=${PARTS:-"styles artists characters"}
# ComfyUI's hours on SPARK, agreed with its scheduler. Whatever the table
# says, nothing is sent unless ComfyUI also answers.
WINDOWS=${WINDOWS:-"07:10-12:50"}
export LAB_SHARED_PAUSE=${PAUSE:-2.5}
export LAB_MAX_CELL_SECONDS=${MAX_CELL:-120}
export LAB_MAX_FIRST_CELL_SECONDS=${MAX_FIRST_CELL:-300}
# SPARK logs its hottest zone once a minute (column zone_max_c). At 95 °C no
# new cell starts until it is back under 90; when the log cannot be read the
# run carries on.
export LAB_THERMAL_CMD=${THERMAL_CMD-"ssh -o ConnectTimeout=5 -o BatchMode=yes spark 'tail -1 ~/ops/thermal.csv' | cut -d, -f9"}
export LAB_THERMAL_MAX=${THERMAL_MAX:-95}
export LAB_THERMAL_RESUME=${THERMAL_RESUME:-90}
DRY=${DRY:-}
TOP=${TOP:-}
# The lab's own dump reads LIMIT from the environment and cuts the plan to
# that many cells — a stray one would quietly shrink every part.
unset LIMIT
CANDIDATES_REF=${CANDIDATES_REF:-lab/prompt-candidates}
OUT=$ROOT/build/lab
LAB=$OUT/_bin/ol1n-lab
mkdir -p $OUT/_bin $OUT/_candidates

log() { print -r -- "$(date '+%m-%d %H:%M') $*"; }

if [[ -f $ROOT/.env.local ]]; then set -a; source $ROOT/.env.local; set +a; fi
COMFY=${COMFYUI_URL:-https://comfyui.ol1n.com}

# ── when ────────────────────────────────────────────────────────────────

minutes() { print $(( 10#${1%%:*} * 60 + 10#${1##*:} )); }

in_window() {
  [[ -n $DRY || $WINDOWS == always ]] && return 0
  local now=$(minutes $(date +%H:%M)) w from to
  for w in ${=WINDOWS}; do
    from=$(minutes ${w%%-*}); to=$(minutes ${w##*-})
    if (( from <= to )); then
      (( now >= from && now < to )) && return 0
    else  # crosses midnight
      (( now >= from || now < to )) && return 0
    fi
  done
  return 1
}

comfy_up() {
  [[ -n $DRY ]] && return 0
  curl -s -m 15 -o /dev/null -f \
    -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID:-}" \
    -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET:-}" \
    $COMFY/system_stats
}

wait_for_window() {
  local said=
  until in_window && comfy_up; do
    if [[ -z $said ]]; then
      log "čekám na okno ComfyUI ($WINDOWS)$(in_window && print ' — okno je, ComfyUI neodpovídá')"
      said=1
    fi
    sleep 120
  done
}

# ── what ────────────────────────────────────────────────────────────────

# done / failed / total of a run, "0 0 0" before its first dump.
progress() {
  python3 - $1 <<'EOF'
import json, sys
try:
    s = json.load(open(sys.argv[1] + "/state.json"))
    print(s.get("done", 0), s.get("failed", 0), s.get("total", 0))
except Exception:
    print(0, 0, 0)
EOF
}

# A prompt file with the motif taken out: the candidates carry their own
# ("standing, dress, outdoors"), here the photo is the motif, so an entry is
# only the tag — and TAGS goes in front of every one as the prefix.
candidates() {  # kind (artists|characters) → path
  local kind=$1 dst=$OUT/_candidates/complete-$1${TOP:+-top$TOP}.yaml
  local src=$ROOT/tools/lab/candidates/native-$kind.yaml
  if [[ ! -f $src ]]; then
    src=$OUT/_candidates/native-$kind.yaml
    git -C $ROOT show ${CANDIDATES_REF}:tools/lab/candidates/native-$kind.yaml > $src || {
      echo "native-$kind.yaml není v pracovním adresáři ani na větvi $CANDIDATES_REF" >&2
      return 1
    }
  fi
  python3 - $src $dst $kind "$TOP" $ROOT/tools/lab/candidates/native-$kind-ranked.tsv <<'EOF'
import os, re, sys
src, dst, kind, limit, ranked = sys.argv[1:6]
keys = []
for line in open(src, encoding="utf-8"):
    if not line.strip() or line[0] in " #":
        continue
    m = re.match(r"^(?:'((?:[^']|'')*)'|([^:#'][^:]*)):\s*$", line.rstrip("\n"))
    if m:
        keys.append(m.group(1).replace("''", "'") if m.group(1) is not None else m.group(2).strip())
keys = [k for k in keys if k != "baseline"]
# Most posts on danbooru first (danbooru_top.py) — so that TOP means "the
# hundred the models saw most of", not "the first hundred of the alphabet".
if os.path.exists(ranked):
    rank = {line.split("\t")[0]: i for i, line in enumerate(open(ranked, encoding="utf-8"))}
    keys.sort(key=lambda k: rank.get(k, len(rank)))
if limit:
    keys = keys[:int(limit)]
q = lambda s: "'" + s.replace("'", "''") + "'"
esc = lambda s: s.replace("(", r"\(").replace(")", r"\)")
with open(dst, "w", encoding="utf-8") as f:
    # The motif alone, to tell "the model follows the tag" from "it draws
    # this anyway".
    f.write("baseline:\n  danbooru: " + q("original" if kind == "characters" else "looking at viewer") + "\n")
    for k in keys:
        body = ("artist:" if kind == "artists" else "") + esc(k)
        f.write(f"{q(k)}:\n  danbooru: {q(body)}\n")
print(dst)
EOF
}

# Which models take part. The registry decides (a one-cell-per-model dry
# plan asks it: pose-capable, generic SDXL graph, prompt family), ComfyUI
# decides which of them are installed. Prints "<style models>|<tag models>".
models() {
  local probe=$OUT/complete-$NAME-probe
  if [[ ! -f $probe/wf/manifest.json ]]; then
    mkdir -p $probe
    $LAB run --dry --no-styles --flows repose --ref $REF --subject probe \
      --out $probe > $probe/complete.log 2>&1 || {
      echo "plán modelů selhal, viz $probe/complete.log" >&2; return 1
    }
  fi
  local installed=
  [[ -z $DRY ]] && installed=$(curl -s -m 30 \
    -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID:-}" \
    -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET:-}" \
    $COMFY/object_info/CheckpointLoaderSimple)
  python3 - $probe/wf/manifest.json "$installed" <<'EOF'
import json, sys
man = json.load(open(sys.argv[1]))
have = None
try:
    have = set(json.loads(sys.argv[2])["CheckpointLoaderSimple"]["input"]["required"]["ckpt_name"][0])
except Exception:
    pass  # dry, or ComfyUI did not say — then the registry alone decides
ok = [m for m in man["models"]
      if m.get("supportsPose") and m.get("ckptName") and (have is None or m["ckptName"] in have)]
print(",".join(m["id"] for m in ok) + "|" +
      " ".join(m["id"] for m in ok if m.get("promptFamily") == "danbooru"))
EOF
}

# ── how ─────────────────────────────────────────────────────────────────

# Runs one lab run to the end, a window at a time.
part() {  # id, lab-run arguments…
  local id=$1 dir=$OUT/complete-$NAME-$1; shift
  local stalls=0 before after pid p why
  while :; do
    p=($(progress $dir))
    if (( p[3] > 0 && p[1] + p[2] >= p[3] && p[2] == 0 )); then
      log "✓ $id: ${p[1]}/${p[3]}"; return 0
    fi
    wait_for_window
    before=${p[1]}
    if [[ -f $dir/wf/manifest.json && -f $dir/state.json ]]; then
      log "▸ $id: pokračuju (${p[1]}/${p[3]}, ${p[2]} chyb)"
      $LAB resume $dir >> $dir/complete.log 2>&1 &
    else
      log "▸ $id: plán a první buňky"
      mkdir -p $dir
      $LAB run "$@" --out $dir >> $dir/complete.log 2>&1 &
    fi
    pid=$!
    while kill -0 $pid 2>/dev/null; do
      if ! in_window; then
        log "■ $id: okno končí, zastavuju"
        pkill -INT -P $pid 2>/dev/null; kill -INT $pid 2>/dev/null
        sleep 20; pkill -KILL -P $pid 2>/dev/null; kill -KILL $pid 2>/dev/null
        break
      fi
      sleep 30
    done
    wait $pid 2>/dev/null
    p=($(progress $dir)); after=${p[1]}
    if (( p[3] > 0 && p[1] + p[2] >= p[3] && p[2] == 0 )); then continue; fi
    # The lab stopped itself for a reason no later pass will change: the
    # photo has no face it can find, or ComfyUI is computing on the CPU.
    why=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]+'/state.json')).get('message',''))" $dir 2>/dev/null)
    if [[ $why == *"běh zastaven"* ]]; then
      log "✗ $id: $why"
      log "končím celou matici — po nápravě stačí pustit stejný příkaz znovu"
      exit 3
    fi
    if [[ -n $DRY ]]; then log "✗ $id: nanečisto nedoběhlo, viz $dir/complete.log"; return 1; fi
    # The lab ended by itself with cells still missing. If ComfyUI is up and
    # nothing was added, another pass will not add anything either (a photo
    # without a face fails every identity cell, every time).
    if (( after == before )) && in_window && comfy_up; then
      (( ++stalls >= 2 )) && {
        log "✗ $id: dvakrát bez pokroku (${p[1]}/${p[3]}, ${p[2]} chyb) — nechávám být, viz $dir/complete.log"
        return 1
      }
    else
      stalls=0
    fi
    sleep 60
  done
}

log "matice $NAME z $REF — části: $PARTS; tvář: $FACE; okna: $WINDOWS${DRY:+; NANEČISTO}"
go build -o $LAB . || exit 1

common=(--ref $REF --flows repose --face-identity $FACE ${DRY:+--dry})

# The model list needs ComfyUI's word on what is installed.
wait_for_window
picked=$(models) || exit 1
style_models=${MODELS:-${picked%%|*}}
# Artist and character tags only mean something to the lines trained on
# danbooru with names intact — the Pony line had artist names hashed away
# (docs/style-matrix.md, wave 3). Of those, the ones that are installed.
want=(${=${TAG_MODELS:-noobai-xl,illustrious-xl,wai-illustrious,animagine-xl}//,/ })
have_tags=(${=picked##*|})
tag_models=(${want:*have_tags})
log "modely pro styly: $style_models"
log "modely pro tagy: $tag_models"

for what in ${=PARTS}; do
  case $what in
    styles)
      part styles "${common[@]}" --subject "$SUBJECT" --models $style_models
      ;;
    artists|characters)
      file=$(candidates $what) || exit 1
      for m in $tag_models; do
        part $what-$m "${common[@]}" --subject "$TAGS" --prompts-yaml $file \
          --models $m --no-styles
      done
      ;;
    *) log "neznámá část: $what" ;;
  esac
done
log "konec — běhy jsou v $OUT/complete-$NAME-*"
