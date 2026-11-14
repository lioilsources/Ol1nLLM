.PHONY: run debug build-ios build-android lab lab-dry lab-check lab-arcface lab-resume lab-score lab-complete stylemap-env stylemap stylemap-tags stylemap-serve stylemap-publish

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
