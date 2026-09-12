TESTING_PLUGIN = /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib

.PHONY: build app test install run clean

build:
	swift build

## Build build/MicroKeys.app (SIGN_IDENTITY="…" make app to sign with a certificate)
app:
	scripts/build-app.sh

## Unit tests (Swift Testing; the plugin path is needed when only Command Line Tools are installed)
test:
	swift test -Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN)

## Copy the app into /Applications and launch it
install: app
	rm -rf /Applications/MicroKeys.app
	cp -R build/MicroKeys.app /Applications/
	open /Applications/MicroKeys.app

## Run the freshly built bundle from build/
run: app
	open build/MicroKeys.app

clean:
	rm -rf .build build
