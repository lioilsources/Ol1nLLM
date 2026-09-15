.PHONY: run debug build-ios build-android lab lab-dry lab-check lab-arcface lab-resume lab-score

-include .env.local

DART_DEFINES = \
	--dart-define=CF_ACCESS_CLIENT_ID=$(CF_ACCESS_CLIENT_ID) \
	--dart-define=CF_ACCESS_CLIENT_SECRET=$(CF_ACCESS_CLIENT_SECRET) \
	$(if $(FLUX_NIM_URL),--dart-define=FLUX_NIM_URL=$(FLUX_NIM_URL),) \
	$(if $(COMFYUI_URL),--dart-define=COMFYUI_URL=$(COMFYUI_URL),) \
	$(if $(FINETUNE_URL),--dart-define=FINETUNE_URL=$(FINETUNE_URL),) \
	$(if $(LIBRARY_CHAT_URL),--dart-define=LIBRARY_CHAT_URL=$(LIBRARY_CHAT_URL),) \
	$(if $(VLLM_URL),--dart-define=VLLM_URL=$(VLLM_URL),) \
	$(if $(UGC_FC_URL),--dart-define=UGC_FC_URL=$(UGC_FC_URL),)

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

# ArcFace metric for the lab (tools/lab/arcface.py): a local venv with
# insightface on CPU and the antelopev2 models copied from SPARK, the same
# files ComfyUI and the benches use — so identity numbers stay comparable.
# First install builds wheels for a while; the pip cache makes reruns fast.
lab-arcface:
	python3 -m venv tools/lab/.venv
	tools/lab/.venv/bin/pip install -q insightface onnxruntime opencv-python-headless numpy
	mkdir -p $(HOME)/.insightface/models
	rsync -a spark:Code/ComfyUI/models/insightface/models/antelopev2 $(HOME)/.insightface/models/
