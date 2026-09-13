# Repository-level entry points. Each platform lives in its own directory
# with its own build; these targets just forward. Version is the VERSION file.
.PHONY: test app perf release install run icon clean version macos-test

version:
	@cat VERSION

## macOS (Swift) - see macos/Makefile for the full list
test app perf release install run icon clean:
	$(MAKE) -C macos $@

macos-test:
	$(MAKE) -C macos test
