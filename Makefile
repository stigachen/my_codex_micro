# With only the Command Line Tools installed, swift test cannot find the Swift
# Testing macro plugin on its own; with Xcode it can. Detect which we have.
TESTING_PLUGIN = /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
TEST_FLAGS = $(shell xcode-select -p 2>/dev/null | grep -q CommandLineTools && echo "-Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN)")

.PHONY: build app icon test perf release install run clean

build:
	swift build

## Build build/MicroKeys.app (SIGN_IDENTITY="…" make app to sign with a certificate)
app:
	scripts/build-app.sh

## Regenerate Resources/AppIcon.icns from Resources/icon-source.png
icon:
	swift scripts/make-icon.swift Resources/icon-source.png Resources/AppIcon.icns

## Unit tests (Swift Testing; the plugin path is needed when only Command Line Tools are installed)
test:
	swift test $(TEST_FLAGS)

## Runtime soak: launch the app, watch memory/CPU for a minute, run `leaks` (DURATION=300 for longer)
perf: app
	scripts/perf-check.sh

## Distributable build under dist/: SIGN_IDENTITY="…" make release  (add NOTARY_PROFILE="…" to notarize)
release:
	scripts/release.sh

## Copy the app into /Applications and launch it
install: app
	rm -rf /Applications/MicroKeys.app
	cp -R build/MicroKeys.app /Applications/
	open /Applications/MicroKeys.app

## Run the freshly built bundle from build/
run: app
	open build/MicroKeys.app

clean:
	rm -rf .build build dist
