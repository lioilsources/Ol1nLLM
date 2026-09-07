.PHONY: run debug build-ios build-android lab lab-dry lab-check learn learn-dry check-learned

-include .env.local

DART_DEFINES = \
	--dart-define=CF_ACCESS_CLIENT_ID=$(CF_ACCESS_CLIENT_ID) \
	--dart-define=CF_ACCESS_CLIENT_SECRET=$(CF_ACCESS_CLIENT_SECRET) \
	$(if $(FLUX_NIM_URL),--dart-define=FLUX_NIM_URL=$(FLUX_NIM_URL),) \
	$(if $(COMFYUI_URL),--dart-define=COMFYUI_URL=$(COMFYUI_URL),) \
	$(if $(FINETUNE_URL),--dart-define=FINETUNE_URL=$(FINETUNE_URL),) \
	$(if $(LIBRARY_CHAT_URL),--dart-define=LIBRARY_CHAT_URL=$(LIBRARY_CHAT_URL),) \
	$(if $(VLLM_URL),--dart-define=VLLM_URL=$(VLLM_URL),)

run:
	flutter run --release $(DART_DEFINES)

debug:
	flutter run $(DART_DEFINES)

build-ios: check-learned
	flutter build ipa --release \
		--export-options-plist=ios/ExportOptions.plist \
		$(DART_DEFINES)

build-android: check-learned
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

# Read the gallery's eval and regenerate lib/generated/learned.dart. Run this
# before a release: the diff it produces *is* the release note ("repose now
# defaults to Pony — pose adherence 90 %, n=31"). `learn-dry` shows the
# decisions and the diff without writing.
learn:
	cd tools/lab && go run . learn

learn-dry:
	cd tools/lab && go run . learn --dry

# A warning, never a hard fail. CI has no route to the gallery (it lives on the
# NAS behind CF Access), so a build that *required* fresh knowledge would be a
# build CI can never do. The point is only that a stale release is noticed by
# the person doing it.
check-learned:
	@snap=$$(sed -n 's|^// snapshot: \([0-9-]*\).*|\1|p' lib/generated/learned.dart); \
	if [ -z "$$snap" ]; then \
		echo "!! lib/generated/learned.dart nikdy negeneroval — appka jede na výchozích hodnotách"; \
		echo "   \`make learn\` (potřebuje CF_ACCESS_* a nasazenou galerii)"; \
	else \
		age=$$(( ( $$(date +%s) - $$(date -j -f %Y-%m-%d "$$snap" +%s 2>/dev/null || date -d "$$snap" +%s) ) / 86400 )); \
		if [ "$$age" -gt 30 ]; then \
			echo "!! znalost je $$age dní stará (snapshot $$snap) — zvaž \`make learn\` před releasem"; \
		else \
			echo "znalost: snapshot $$snap ($$age dní)"; \
		fi; \
	fi
