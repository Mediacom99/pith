# Every command goes through here; `make` lists the targets.

APP_NAME := Launcher
CONFIG   ?= release
APP      := .build/$(APP_NAME).app
BINARY   := $(APP)/Contents/MacOS/$(APP_NAME)

.DEFAULT_GOAL := help
.PHONY: help build app run stop logs stats test bench lint format clean

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

run: app stop ## Build and (re)launch the app; it takes ⌘P system-wide
	open $(APP)

stop: ## Quit the running app
	@pkill -f "$(CURDIR)/$(BINARY)" || true

logs: ## Stream the app's logs, including ⌘P and keystroke latencies
	log stream --level debug --predicate 'subsystem == "dev.edoardo.launcher"'

stats: ## Memory footprint, CPU and thread count of the running app
	@pid=$$(pgrep -f "$(CURDIR)/$(BINARY)") || { echo "Launcher isn't running"; exit 1; }; \
	footprint $$pid | sed -n 2p | sed 's/.*Footprint/footprint/'; \
	echo "cpu $$(ps -o %cpu= -p $$pid | tr -d ' ')%  threads $$(($$(ps -M -p $$pid | wc -l) - 1))"

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
