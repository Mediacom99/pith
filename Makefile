# Every command goes through here; `make` lists the targets.

APP_NAME := Launcher
CONFIG   ?= release
APP      := .build/$(APP_NAME).app
BINARY   := $(APP)/Contents/MacOS/$(APP_NAME)
INSTALLED := $(HOME)/Applications/$(APP_NAME).app
# Matches both the dev copy and the installed one.
PROCESS  := $(APP_NAME).app/Contents/MacOS/$(APP_NAME)

.DEFAULT_GOAL := help
.PHONY: help build app run install stop logs stats test bench lint format clean

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

run: app stop ## Build and launch the dev copy; it takes ⌘P system-wide
	open $(APP)

install: app stop ## Build, copy to ~/Applications and launch: the copy that starts at login
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(INSTALLED)"
	cp -R $(APP) "$(INSTALLED)"
	open "$(INSTALLED)"

stop: ## Quit the running app, dev or installed copy, and wait until it's gone
	@pkill -f "$(PROCESS)" || true
	@while pgrep -f "$(PROCESS)" > /dev/null; do sleep 0.1; done

logs: ## Stream the app's logs, including ⌘P and keystroke latencies
	log stream --level debug --predicate 'subsystem == "dev.edoardo.launcher"'

stats: ## Memory footprint, CPU and thread count of the running app
	@pid=$$(pgrep -f "$(PROCESS)" | head -1); [ -n "$$pid" ] || { echo "Launcher isn't running"; exit 1; }; \
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
