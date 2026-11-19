# Every command goes through here; `make` lists the targets.

APP_NAME := Launcher
CONFIG   ?= release
APP      := .build/$(APP_NAME).app
BINARY   := $(APP)/Contents/MacOS/$(APP_NAME)

.DEFAULT_GOAL := help
.PHONY: help build app run test bench lint format clean

help: ## List the targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z]+:.*## / { printf "  make %-7s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Compile (CONFIG=release by default, CONFIG=debug for a debug build)
	swift build -c $(CONFIG)

app: build ## Assemble .build/Launcher.app and sign it ad hoc
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp .build/$(CONFIG)/$(APP_NAME) $(BINARY)
	codesign --force --sign - $(APP)

run: app ## Build and (re)launch the app; it takes ⌘P system-wide
	-pkill -f "$(CURDIR)/$(BINARY)"
	open $(APP)

test: ## Run the unit tests
	swift test --skip Benchmark

bench: ## Time scanning and fuzzy search in a release build
	swift test -c release --filter Benchmark

lint: ## Check formatting
	swift format lint --strict --recursive Package.swift Sources Tests

format: ## Format the code in place
	swift format --in-place --recursive Package.swift Sources Tests

clean: ## Remove build products
	rm -rf .build
