# Repository-level entry points. Each platform lives in its own directory
# with its own build; these targets just forward. Version is the VERSION file.
.PHONY: test app perf release install run icon clean version macos-test windows-test windows-publish

version:
	@cat VERSION

## Both platforms' unit tests (the Windows Core tests run anywhere the .NET SDK is installed)
test: macos-test windows-test

## macOS (Swift) - see macos/Makefile for the full list
app perf release install run icon:
	$(MAKE) -C macos $@

macos-test:
	$(MAKE) -C macos test

## Windows (C#) - see windows/Makefile
windows-test:
	$(MAKE) -C windows test

windows-publish:
	$(MAKE) -C windows publish

clean:
	$(MAKE) -C macos clean
	$(MAKE) -C windows clean
