# Windows build. Runs on Windows, and on macOS/Linux with the .NET SDK for
# building and testing (the app itself only runs on Windows).
#
#   make test        unit tests (platform-neutral Core)
#   make publish     single-file self-contained exe for win-x64 and win-arm64 -> dist/
#   make clean
DOTNET ?= dotnet
export DOTNET_CLI_TELEMETRY_OPTOUT = 1
export DOTNET_NOLOGO = 1
VERSION := $(shell tr -d '[:space:]' < ../VERSION)
RIDS ?= win-x64 win-arm64

.PHONY: test build publish clean

test:
	$(DOTNET) test MicroKeys.Core.Tests -c Release

build:
	$(DOTNET) build MicroKeys -c Release

## dist/MicroKeys-<version>-<rid>.zip: MicroKeys.exe + docs + config.example.json
publish:
	rm -rf dist; mkdir -p dist
	for rid in $(RIDS); do \
	  $(DOTNET) publish MicroKeys -c Release -r $$rid -o dist/$$rid || exit 1; \
	  (cd dist/$$rid && rm -f *.pdb && zip -qr ../MicroKeys-$(VERSION)-$$rid.zip .) || exit 1; \
	done
	ls -la dist/*.zip

clean:
	rm -rf dist */bin */obj
