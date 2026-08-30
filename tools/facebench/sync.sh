#!/usr/bin/env bash
# facebench na SPARK: skript + workflow assety appky (bench/ obrázky a out/ zůstávají na SPARKu)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/../.." && pwd)"
ssh "${SPARK_HOST:-spark}" 'mkdir -p ~/Code/facebench/assets ~/Code/facebench/bench'
scp -q "$HERE/bench.py" "${SPARK_HOST:-spark}:Code/facebench/"
scp -q "$APP"/assets/comfyui/flux_fill_inpaint_face.api.json "${SPARK_HOST:-spark}:Code/facebench/assets/"
echo "sync ok"
