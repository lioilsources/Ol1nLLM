.PHONY: run debug build-ios build-android lab lab-dry lab-check lab-arcface lab-wd14 lab-resume lab-score lab-complete stylemap-env stylemap stylemap-tags stylemap-serve stylemap-video stylemap-publish

-include .env.local

DART_DEFINES = \
	--dart-define=CF_ACCESS_CLIENT_ID=$(CF_ACCESS_CLIENT_ID) \
	--dart-define=CF_ACCESS_CLIENT_SECRET=$(CF_ACCESS_CLIENT_SECRET) \
	$(if $(FLUX_NIM_URL),--dart-define=FLUX_NIM_URL=$(FLUX_NIM_URL),) \
	$(if $(COMFYUI_URL),--dart-define=COMFYUI_URL=$(COMFYUI_URL),) \
	$(if $(FINETUNE_URL),--dart-define=FINETUNE_URL=$(FINETUNE_URL),) \
	$(if $(LIBRARY_CHAT_URL),--dart-define=LIBRARY_CHAT_URL=$(LIBRARY_CHAT_URL),) \
	$(if $(LAW_CHAT_URL),--dart-define=LAW_CHAT_URL=$(LAW_CHAT_URL),) \
	$(if $(LEADS_CHAT_URL),--dart-define=LEADS_CHAT_URL=$(LEADS_CHAT_URL),) \
	$(if $(VLLM_URL),--dart-define=VLLM_URL=$(VLLM_URL),) \
	$(if $(UGC_FC_URL),--dart-define=UGC_FC_URL=$(UGC_FC_URL),) \
	$(if $(AUDIO_URL),--dart-define=AUDIO_URL=$(AUDIO_URL),) \
	$(if $(VIDEO_URL),--dart-define=VIDEO_URL=$(VIDEO_URL),) \
	$(if $(STYLEMAP_URL),--dart-define=STYLEMAP_URL=$(STYLEMAP_URL),)

run:
	flutter run --release $(DART_DEFINES)

debug:
	flutter run $(DART_DEFINES)

build-ios:
	flutter build ipa --release \
		--export-options-plist=ios/ExportOptions.plist \
		$(DART_DEFINES)

build-android:
	flutter build apk --release \
		$(DART_DEFINES)

# The lab is its own Go module, so it runs from its own directory; it walks up
# to the package root itself (pubspec.yaml) for assets and build/lab.
lab:
	cd tools/lab && go run . serve --port 8765 --open

lab-dry:
	cd tools/lab && go run . serve --port 8765 --open --force-dry

lab-check:
	cd tools/lab && go run . check

# Fill in every cell of a run that has no image — interrupted and failed alike
# (a ComfyUI restart mid-run fails cells in seconds). RUN is a run id from
# build/lab, a path, or empty for the newest run:
#   make lab-resume                  make lab-resume RUN=20260914-200437
lab-resume:
	cd tools/lab && go run . resume $(RUN)

lab-score:
	cd tools/lab && go run . score $(RUN)

# The whole matrix from one photo — repose with the photo's face on every SDXL
# model × every style, and every native artist and character on the tag
# models. ~40 000 cells: it runs only in ComfyUI's hours on SPARK and resumes
# by itself, so start it detached and leave it (knobs: tools/lab/complete.sh):
#   nohup make lab-complete REF=foto.jpg > build/lab/complete.log 2>&1 &
lab-complete:
	tools/lab/complete.sh $(REF)

# ArcFace metric for the lab (tools/lab/arcface.py): a local venv with
# insightface on CPU and the antelopev2 models copied from SPARK, the same
# files ComfyUI and the benches use — so identity numbers stay comparable.
# First install builds wheels for a while; the pip cache makes reruns fast.
lab-arcface:
	python3 -m venv tools/lab/.venv
	tools/lab/.venv/bin/pip install -q insightface onnxruntime opencv-python-headless numpy
	mkdir -p $(HOME)/.insightface/models
	rsync -a spark:Code/ComfyUI/models/insightface/models/antelopev2 $(HOME)/.insightface/models/

# WD14 tags of the reference for the lab (tools/lab/wd14.py, `--ref-tags` /
# „tagy z předlohy“): the same tagger as the FINETUNE gallery sidecar, run on
# CPU in the lab venv. Model ~450 MB from Hugging Face, downloaded once.
WD14_DIR = $(HOME)/.cache/lab-wd14/SmilingWolf--wd-swinv2-tagger-v3
WD14_URL = https://huggingface.co/SmilingWolf/wd-swinv2-tagger-v3/resolve/main
lab-wd14:
	test -x tools/lab/.venv/bin/python || python3 -m venv tools/lab/.venv
	tools/lab/.venv/bin/pip install -q onnxruntime numpy pillow
	mkdir -p $(WD14_DIR)
	test -s $(WD14_DIR)/selected_tags.csv || curl -fL -o $(WD14_DIR)/selected_tags.csv $(WD14_URL)/selected_tags.csv
	test -s $(WD14_DIR)/model.onnx || { curl -fL -o $(WD14_DIR)/model.onnx.part $(WD14_URL)/model.onnx && mv $(WD14_DIR)/model.onnx.part $(WD14_DIR)/model.onnx; }

# Style maps (tools/stylemap): a set of pictures → a pack the app's StyleMap
# widget reads (map.json + atlas + previews in build/stylemap/<SET>).
# The set is one or more FINETUNE gallery sessions, or a lab run on disk:
#   make stylemap SET=noobai-artists SESSIONS="<id> <id>" TITLE="NoobAI — umělci"
#   make stylemap SET=noobai-artists RUN=noobai-artists-v3
# WHERE narrows a gallery set with /api/images filters (WHERE="score=1").
# FULL=1 downloads the originals instead of the gallery's small thumbnails.
# TAG_REGEX pulls the prompt fragment out of the prompt text — always for the
# gallery, and for lab runs made before --prompts-yaml:
#   TAG_REGEX='artist:[^,]+'
STYLEMAP_PY = tools/stylemap/.venv/bin/python
# Where the gallery keeps its data on the NAS (docker mount of /data).
STYLEMAP_DEST ?= joda:/media/storage/FineTuneGallery/stylemaps

stylemap-env:
	python3 -m venv tools/stylemap/.venv
	tools/stylemap/.venv/bin/pip install -q -r tools/stylemap/requirements.txt

stylemap:
	$(STYLEMAP_PY) tools/stylemap/extract_features.py --out build/stylemap/$(SET) \
		$(if $(RUN),--run build/lab/$(RUN),) \
		$(foreach s,$(SESSIONS),--session $(s)) $(foreach w,$(WHERE),--where $(w)) \
		$(if $(FULL),--full,) $(if $(TAG_REGEX),--tag-regex '$(TAG_REGEX)',)
	$(STYLEMAP_PY) tools/stylemap/perceptual.py --set build/stylemap/$(SET)
	$(STYLEMAP_PY) tools/stylemap/build_map.py --set build/stylemap/$(SET) \
		$(if $(TITLE),--title "$(TITLE)",)
	$(STYLEMAP_PY) tools/stylemap/make_thumbs.py --set build/stylemap/$(SET)

# VLM tags for a set (facets and search in the widget), then the manifest
# again — the layout does not change, only what the pictures carry. The model
# is shared and runs in a window (SPARK, 19:15–00:50); the script stops by
# itself and keeps what it has, so the same command another evening finishes
# the set. TAG_ARGS passes options through (--jobs, --until, --url).
stylemap-tags:
	$(STYLEMAP_PY) tools/stylemap/tag_images.py --set build/stylemap/$(SET) $(TAG_ARGS)
	$(STYLEMAP_PY) tools/stylemap/build_map.py --set build/stylemap/$(SET) \
		--title "$$(python3 -c "import json;print(json.load(open('build/stylemap/$(SET)/map.json'))['title'])")"
	$(STYLEMAP_PY) tools/stylemap/make_thumbs.py --set build/stylemap/$(SET)

# Slideshow as a vertical MP4 for TikTok/Reels/Shorts (make_video.py), from a
# pack (SET=…, the LPIPS route, re-planned over a filtered subset) or straight
# from a lab run (RUN=…, no pack needed). ORDER=style plays one style at a time
# across all models (default for RUN), LABEL=1 burns in "style · model",
# GRID=1 puts every model of one style on one frame (RATE = styles per second),
# COLS=3 fixes its columns (rows follow; default picks the largest pictures),
# RUN="a b c" merges runs by prompt id; MIX=1 (with GRID=1) shows every model on
# the same prompt, each in its own style, for runs whose styles differ.
# COMPLETE=1 drops grid frames where a model has no picture. OUTER=style plays
# style → prompts instead of prompt → styles. SPLIT=60 cuts the output into
# videos of at most 60 s, only between prompts (or styles) (NAME-01.mp4 …).
# WHERE filters like the app (model=…, style=…, flow=repose), RATE = pictures
# per second, FADE = share of each picture spent crossfading (0 = cut).
# VIDEO_ARGS passes the rest (--fit cover, --max-seconds 60, --audio song.mp3,
# --model-order a,b,c, --size 1080x1350).
#   make stylemap-video SET=muj-beh NAME=noobai-4fps WHERE="model=noobai-xl" RATE=4
#   make stylemap-video RUN=20261124-112650 NAME=po-stylech RATE=3 LABEL=1
#   make stylemap-video RUN=20261124-112650 NAME=mrizka GRID=1 RATE=2 LABEL=1
# A run needs only numpy and Pillow, so without the stylemap venv it uses python3.
VIDEO_PY = $(if $(wildcard $(STYLEMAP_PY)),$(STYLEMAP_PY),python3)
# One run writes next to it; several runs (RUN="a b c") into build/lab/_merged.
VIDEO_DIR = $(if $(RUN),$(if $(word 2,$(RUN)),build/lab/_merged/video,build/lab/$(RUN)/video),build/stylemap/$(SET)/video)
stylemap-video:
	$(VIDEO_PY) tools/stylemap/make_video.py \
		$(if $(RUN),--run $(addprefix build/lab/,$(RUN)),--set build/stylemap/$(SET)) \
		--out $(VIDEO_DIR)/$(or $(NAME),$(SET),$(firstword $(RUN))).mp4 \
		$(foreach w,$(WHERE),--where $(w)) $(if $(RATE),--rate $(RATE),) \
		$(if $(FADE),--fade $(FADE),) $(if $(ORDER),--order $(ORDER),) $(if $(OUTER),--outer $(OUTER),) \
		$(if $(LABEL),--label,) $(if $(GRID),--grid,) \
		$(if $(COLS),--cols $(COLS),) $(if $(COMPLETE),--complete,) $(if $(MIX),--mix,) \
		$(if $(SPLIT),--split $(SPLIT),) $(VIDEO_ARGS)

# Serves the packs to a phone on the LAN (STYLEMAP_URL=http://<mac-ip>:8770,
# `make debug` only — cleartext). Generated pictures, no credentials.
stylemap-serve:
	cd build/stylemap && python3 -m http.server 8770

# Copies the packs to the gallery, which serves them at /stylemaps/ — only what
# the widget reads, not features, logs or the download cache.
stylemap-publish:
	rsync -av --prune-empty-dirs \
		--include='index.json' --include='*/' --include='*/map.json' \
		--include='*/atlas.webp' --include='*/t/*.webp' --exclude='*' \
		build/stylemap/ $(STYLEMAP_DEST)/
