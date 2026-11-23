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
# Sparkle (decision 48): its framework, embedded by `make app`, and the tools that sign and list updates.
SPARKLE  := $(APP)/Contents/Frameworks/Sparkle.framework/Versions/B
TOOLS    := .build/artifacts/sparkle/Sparkle/bin
FEED     := https://pith.edoardobertoli.xyz
# The version in Info.plist, 0.<milestone>.<patch> (decision 47): `make package` names the zip and the tag after it.
VERSION  = $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
PACKAGE  = .build/$(APP_NAME)-$(VERSION).zip
# What the Worker serves (Support/wrangler.toml): the landing page and its snapshots, the feed and the builds.
SITE     := .build/site
SNAPSHOTS := recent search actions clipboard-text long-names

.DEFAULT_GOAL := help
.PHONY: help build app package publish site page update-key certificate run install uninstall stop logs stats test bench snapshots lint format clean

help: ## List the targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  make %-11s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Compile (CONFIG=release by default, CONFIG=debug for a debug build)
	swift build -c $(CONFIG)

# Sparkle's framework goes in Contents/Frameworks, and is signed from the inside out before the app, the order Sparkle
# documents (never --deep).
app: build ## Assemble .build/Pith.app and sign it (with the local certificate, if there is one)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Frameworks
	cp Support/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$(date +%Y%m%d%H%M)" $(APP)/Contents/Info.plist
	cp .build/$(CONFIG)/$(APP_NAME) $(BINARY)
	ditto .build/$(CONFIG)/Sparkle.framework $(APP)/Contents/Frameworks/Sparkle.framework
	install_name_tool -add_rpath @executable_path/../Frameworks $(BINARY)
	codesign --force --sign "$(SIGN_AS)" $(SPARKLE)/XPCServices/Installer.xpc
	codesign --force --sign "$(SIGN_AS)" --preserve-metadata=entitlements $(SPARKLE)/XPCServices/Downloader.xpc
	codesign --force --sign "$(SIGN_AS)" $(SPARKLE)/Autoupdate
	codesign --force --sign "$(SIGN_AS)" $(SPARKLE)/Updater.app
	codesign --force --sign "$(SIGN_AS)" $(APP)/Contents/Frameworks/Sparkle.framework
	codesign --force --sign "$(SIGN_AS)" $(APP)

# A build that goes out comes from a commit, tagged v<version>; a version already tagged elsewhere has to be raised.
package: ## Zip the app to send to someone and tag it v<version>: signed with the local certificate, not notarized
	@[ "$(SIGN_AS)" != "-" ] || { echo "Run make certificate first: an ad hoc signature loses their permissions at every update"; exit 1; }
	@[ -z "$$(git status --porcelain)" ] || { echo "Commit first: the build is tagged v$(VERSION)"; exit 1; }
	@tagged=$$(git rev-parse -q --verify "refs/tags/v$(VERSION)^{commit}"); \
	[ -z "$$tagged" ] || [ "$$tagged" = "$$(git rev-parse HEAD)" ] || { echo "v$(VERSION) is an earlier build: raise the version in Support/Info.plist"; exit 1; }
	$(MAKE) app
	rm -f $(PACKAGE)
	ditto -c -k --keepParent $(APP) $(PACKAGE)
	@git rev-parse -q --verify "refs/tags/v$(VERSION)" > /dev/null || git tag "v$(VERSION)"
	@echo "$(PACKAGE), tagged v$(VERSION)"

# The feed lists only the newest build; Pith.zip is the same build at a fixed address, for a first install. The private
# key leaves the keychain only for generate_appcast, in a temporary folder that's removed after.
publish: package ## Put the packaged build and its update feed on pith.edoardobertoli.xyz, for every copy to update to
	@[ -n "$$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Support/Info.plist)" ] || { echo "Run make update-key first"; exit 1; }
	rm -rf $(SITE) .build/feed
	mkdir -p $(SITE) .build/feed
	cp $(PACKAGE) .build/feed/
	@secret=$$(mktemp -d); trap 'rm -rf "$$secret"' EXIT; \
	$(TOOLS)/generate_keys --account pith -x "$$secret/key" > /dev/null && \
	$(TOOLS)/generate_appcast --ed-key-file "$$secret/key" --download-url-prefix $(FEED)/ --maximum-versions 1 .build/feed
	cp .build/feed/appcast.xml $(PACKAGE) $(SITE)/
	cp $(PACKAGE) $(SITE)/$(APP_NAME).zip
	$(MAKE) page
	WRANGLER_SEND_METRICS=false npx --yes wrangler@4.166.0 deploy --config Support/wrangler.toml
	@echo "Published $(VERSION): $(FEED)/$(APP_NAME).zip"

# A deploy replaces everything the Worker serves, so the page goes out with the feed and builds `make publish` left.
site: page ## Put the landing page (site/) on pith.edoardobertoli.xyz, keeping the published feed and builds
	@[ -f $(SITE)/appcast.xml ] || { echo "Run make publish first: a deploy without the feed would take updates offline"; exit 1; }
	WRANGLER_SEND_METRICS=false npx --yes wrangler@4.166.0 deploy --config Support/wrangler.toml
	@echo "The page is on $(FEED)"

page: ## Assemble the landing page in .build/site, to open locally before make site
	mkdir -p $(SITE)/snapshots
	cp site/* $(SITE)/
	for s in $(SNAPSHOTS); do cp docs/snapshots/$$s-light.png docs/snapshots/$$s-dark.png $(SITE)/snapshots/; done

# Only the key's value changes in Info.plist: PlistBuddy would rewrite the whole file and drop its comments.
update-key: ## Once: create the key that signs updates (in the login keychain) and put its public half in Info.plist
	@$(TOOLS)/generate_keys --account pith > /dev/null
	@key=$$($(TOOLS)/generate_keys --account pith -p) && \
	perl -0pi -e "s|(<key>SUPublicEDKey</key>\\s*<string>)[^<]*(</string>)|\$${1}$$key\$${2}|" Support/Info.plist && \
	echo "Support/Info.plist now checks updates against $$key"

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
