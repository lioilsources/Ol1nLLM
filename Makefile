.PHONY: run build-ios build-android

-include .env.local

DART_DEFINES = \
	--dart-define=CF_ACCESS_CLIENT_ID=$(CF_ACCESS_CLIENT_ID) \
	--dart-define=CF_ACCESS_CLIENT_SECRET=$(CF_ACCESS_CLIENT_SECRET) \
	$(if $(FLUX_NIM_URL),--dart-define=FLUX_NIM_URL=$(FLUX_NIM_URL),)

run:
	flutter run --release $(DART_DEFINES)

build-ios:
	flutter build ipa --release \
		--export-options-plist=ios/ExportOptions.plist \
		$(DART_DEFINES)

build-android:
	flutter build apk --release \
		$(DART_DEFINES)
