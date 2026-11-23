# Every command goes through here; `make` lists the targets.

APP_NAME := Pith
CONFIG   ?= release
APP      := .build/$(APP_NAME).app
BINARY   := $(APP)/Contents/MacOS/$(APP_NAME)
INSTALLED := $(HOME)/Applications/$(APP_NAME).app
# Matches both the dev copy and the installed one.
PROCESS  := $(APP_NAME).app/Contents/MacOS/$(APP_NAME)
# The local certificate (`make certificate`, decision 41) when it's in the keychain, otherwise ad hoc. A stable signature
# keeps macOS's permissions (Accessibility, for paste) across reinstalls; an ad hoc one changes with every build.
CERTIFICATE := Pith Local Signing
SIGN_AS  = $(shell security find-certificate -c "$(CERTIFICATE)" >/dev/null 2>&1 && echo "$(CERTIFICATE)" || echo -)
# What `make package` writes: the version from Info.plist and the commit it was built from.
VERSION  = $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
PACKAGE  = .build/$(APP_NAME)-$(VERSION)-$(shell git rev-parse --short HEAD).zip

.DEFAULT_GOAL := help
.PHONY: help build app package certificate run install uninstall stop logs stats test bench snapshots lint format clean

help: ## List the targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z]+:.*## / { printf "  make %-11s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Compile (CONFIG=release by default, CONFIG=debug for a debug build)
	swift build -c $(CONFIG)

app: build ## Assemble .build/Pith.app and sign it (with the local certificate, if there is one)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp .build/$(CONFIG)/$(APP_NAME) $(BINARY)
	codesign --force --sign "$(SIGN_AS)" $(APP)

package: app ## Zip the app to send to someone: signed with the local certificate, not notarized
	@[ "$(SIGN_AS)" != "-" ] || { echo "Run make certificate first: an ad hoc signature loses their permissions at every update"; exit 1; }
	rm -f $(PACKAGE)
	ditto -c -k --keepParent $(APP) $(PACKAGE)
	@echo "$(PACKAGE)"

certificate: ## Once: create the self-signed certificate that keeps Pith's permissions across reinstalls (asks for your password)
	@if security find-certificate -c "$(CERTIFICATE)" >/dev/null 2>&1; then echo "$(CERTIFICATE) is already in the keychain"; exit 0; fi; \
	dir=$$(mktemp -d); \
	/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$(CERTIFICATE)" \
		-addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
		-keyout $$dir/key.pem -out $$dir/cert.pem 2>/dev/null \
	&& /usr/bin/openssl pkcs12 -export -passout pass:pith -inkey $$dir/key.pem -in $$dir/cert.pem -out $$dir/cert.p12 \
	&& security import $$dir/cert.p12 -k login.keychain-db -P pith -T /usr/bin/codesign \
	&& security add-trusted-cert -r trustRoot -p codeSign -k login.keychain-db $$dir/cert.pem; \
	status=$$?; rm -rf $$dir; \
	if [ $$status -eq 0 ]; then echo "$(CERTIFICATE) created: make install signs with it from now on"; fi; exit $$status

run: app stop ## Build and launch the dev copy; it takes ⌘P system-wide
	open $(APP)

install: app stop ## Build, copy to ~/Applications and launch: the copy that starts at login
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(INSTALLED)"
	cp -R $(APP) "$(INSTALLED)"
	open "$(INSTALLED)"

uninstall: stop ## Quit the app and remove the installed copy from ~/Applications
	rm -rf "$(INSTALLED)"

stop: ## Quit the running app, dev or installed copy, and wait until it's gone
	@pkill -f "$(PROCESS)" || true
	@while pgrep -f "$(PROCESS)" > /dev/null; do sleep 0.1; done

logs: ## Stream the app's logs, including ⌘P and keystroke latencies
	log stream --level debug --predicate 'subsystem == "dev.edoardo.pith"'

stats: ## Memory footprint, CPU and thread count of the running app
	@pid=$$(pgrep -f "$(PROCESS)" | head -1); [ -n "$$pid" ] || { echo "Pith isn't running"; exit 1; }; \
	footprint $$pid | sed -n 2p | sed 's/.*Footprint/footprint/'; \
	echo "cpu $$(ps -o %cpu= -p $$pid | tr -d ' ')%  threads $$(($$(ps -M -p $$pid | wc -l) - 1))"

test: ## Run the unit tests
	swift test --skip 'Benchmark|Snapshots'

bench: ## Time scanning and fuzzy search in a release build
	swift test -c release --filter Benchmark

snapshots: ## Draw the panel's main states, light and dark, into docs/snapshots/ (off screen)
	swift test --filter Snapshots

lint: ## Check formatting
	swift format lint --strict --recursive Package.swift Sources Tests

format: ## Format the code in place
	swift format --in-place --recursive Package.swift Sources Tests

clean: ## Remove build products
	rm -rf .build
