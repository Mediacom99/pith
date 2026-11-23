# Every command goes through here; `make` lists the targets.

APP_NAME := Pith
CONFIG   ?= release
APP      := .build/$(APP_NAME).app
BINARY   := $(APP)/Contents/MacOS/$(APP_NAME)
# Where the installer and the Terminal install put it (decisions 56, 57), so a branch build replaces that copy.
INSTALLED := /Applications/$(APP_NAME).app
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
# The installer (decision 56): a disk image to drag Pith into Applications from. Built with dmgbuild, pinned by hash in
# Support/dmgbuild-requirements.txt, which lays out the window without opening Finder.
DMG      = .build/$(APP_NAME)-$(VERSION).dmg
DMGBUILD := .build/dmgbuild/bin/dmgbuild
# What the Worker serves (Support/wrangler.toml): the landing page and its snapshots, the feed and the builds.
SITE     := .build/site
SNAPSHOTS := recent search actions clipboard-text long-names

.DEFAULT_GOAL := help
.PHONY: help build app icon package dmg publish site page update-key certificate run install uninstall stop logs stats test bench snapshots lint format clean

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
	mkdir -p $(APP)/Contents/Resources
	cp Support/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Support/Assets.car $(APP)/Contents/Resources/Assets.car
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

# The icon's source is Support/AppIcon.svg (decision 54). Chrome draws it at 1024 px on a transparent canvas; sips and
# iconutil make the sizes macOS wants, and actool compiles the same sizes into Assets.car, the asset catalog macOS 26
# apps name their icon in (CFBundleIconName). The installer's
# background (decision 56) is drawn at 1x and 2x. All are committed, so building doesn't need Chrome.
CHROME := /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
icon: ## Redraw Support/AppIcon.icns and the installer's background from their SVGs (needs Google Chrome)
	@[ -x "$(CHROME)" ] || { echo "make icon draws the SVG with Google Chrome, which isn't installed"; exit 1; }
	@work=$$(mktemp -d); trap 'rm -rf "$$work"' EXIT; \
	"$(CHROME)" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$$work/chrome" \
		--default-background-color=00000000 --window-size=1024,1024 --screenshot="$$work/1024.png" \
		"file://$(CURDIR)/Support/AppIcon.svg" > /dev/null 2>&1 && \
	mkdir "$$work/AppIcon.iconset" && \
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size "$$work/1024.png" --out "$$work/AppIcon.iconset/icon_$${size}x$${size}.png" > /dev/null && \
		sips -z $$((size * 2)) $$((size * 2)) "$$work/1024.png" --out "$$work/AppIcon.iconset/icon_$${size}x$${size}@2x.png" > /dev/null; \
	done && \
	iconutil -c icns "$$work/AppIcon.iconset" -o Support/AppIcon.icns && echo "Support/AppIcon.icns redrawn" && \
	mkdir -p "$$work/Assets.xcassets/AppIcon.appiconset" && \
	cp "$$work/AppIcon.iconset/"*.png "$$work/Assets.xcassets/AppIcon.appiconset/" && \
	cp Support/AppIconSet.json "$$work/Assets.xcassets/AppIcon.appiconset/Contents.json" && \
	xcrun actool "$$work/Assets.xcassets" --compile "$$work" --platform macosx --minimum-deployment-target 26.0 \
		--app-icon AppIcon --output-partial-info-plist "$$work/partial.plist" > /dev/null && \
	cp "$$work/Assets.car" Support/Assets.car && echo "Support/Assets.car redrawn" && \
	for scale in 1 2; do \
		"$(CHROME)" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$$work/chrome" \
			--window-size=640,400 --force-device-scale-factor=$$scale --screenshot="$$work/background-$$scale.png" \
			"file://$(CURDIR)/Support/DMGBackground.svg" > /dev/null 2>&1 || exit 1; \
	done && \
	cp "$$work/background-1.png" Support/DMGBackground.png && cp "$$work/background-2.png" Support/DMGBackground@2x.png && \
	echo "Support/DMGBackground.png and @2x redrawn"

# A build that goes out comes from a commit, tagged v<version>; a version already tagged elsewhere has to be raised.
package: ## Zip the app for the update feed, make its installer and tag it v<version>: signed with the local certificate, not notarized
	@[ "$(SIGN_AS)" != "-" ] || { echo "Run make certificate first: an ad hoc signature loses their permissions at every update"; exit 1; }
	@[ -z "$$(git status --porcelain)" ] || { echo "Commit first: the build is tagged v$(VERSION)"; exit 1; }
	@tagged=$$(git rev-parse -q --verify "refs/tags/v$(VERSION)^{commit}"); \
	[ -z "$$tagged" ] || [ "$$tagged" = "$$(git rev-parse HEAD)" ] || { echo "v$(VERSION) is an earlier build: raise the version in Support/Info.plist"; exit 1; }
	$(MAKE) app
	rm -f $(PACKAGE)
	ditto -c -k --keepParent $(APP) $(PACKAGE)
	$(MAKE) dmg
	@git rev-parse -q --verify "refs/tags/v$(VERSION)" > /dev/null || git tag "v$(VERSION)"
	@echo "$(PACKAGE) and $(DMG), tagged v$(VERSION)"

dmg: $(DMGBUILD) ## Make the installer from the built app: a disk image to drag Pith into Applications from
	rm -f $(DMG)
	$(DMGBUILD) -s Support/dmg-settings.py -D app=$(APP) $(APP_NAME) $(DMG) > /dev/null
	@echo "$(DMG)"

$(DMGBUILD): Support/dmgbuild-requirements.txt
	rm -rf .build/dmgbuild
	/usr/bin/python3 -m venv .build/dmgbuild
	.build/dmgbuild/bin/pip install --quiet --disable-pip-version-check --require-hashes --only-binary=:all: \
		-r Support/dmgbuild-requirements.txt

# The feed lists only the newest build, as a zip; Pith.dmg is its installer at a fixed address, for a first install
# (decision 56). The private key leaves the keychain only for generate_appcast, in a temporary folder that's removed
# after.
publish: package ## Put the packaged build and its update feed on pith.edoardobertoli.xyz, for every copy to update to
	@[ -n "$$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Support/Info.plist)" ] || { echo "Run make update-key first"; exit 1; }
	rm -rf $(SITE) .build/feed
	mkdir -p $(SITE) .build/feed
	cp $(PACKAGE) .build/feed/
	@secret=$$(mktemp -d); trap 'rm -rf "$$secret"' EXIT; \
	$(TOOLS)/generate_keys --account pith -x "$$secret/key" > /dev/null && \
	$(TOOLS)/generate_appcast --ed-key-file "$$secret/key" --download-url-prefix $(FEED)/ --maximum-versions 1 .build/feed
	cp .build/feed/appcast.xml $(PACKAGE) $(SITE)/
	cp $(DMG) $(SITE)/$(APP_NAME).dmg
	$(MAKE) page
	WRANGLER_SEND_METRICS=false npx --yes wrangler@4.166.0 deploy --config Support/wrangler.toml
	@echo "Published $(VERSION): $(FEED)/$(APP_NAME).dmg"

# A deploy replaces everything the Worker serves, so the page goes out with the feed and builds `make publish` left.
site: page ## Put the landing page (site/) on pith.edoardobertoli.xyz, keeping the published feed and builds
	@[ -f $(SITE)/appcast.xml ] || { echo "Run make publish first: a deploy without the feed would take updates offline"; exit 1; }
	WRANGLER_SEND_METRICS=false npx --yes wrangler@4.166.0 deploy --config Support/wrangler.toml
	@echo "The page is on $(FEED)"

page: ## Assemble the landing page in .build/site, to open locally before make site
	mkdir -p $(SITE)/snapshots
	cp site/* $(SITE)/
	cp Support/AppIcon.svg $(SITE)/icon.svg
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

install: app stop ## Build, copy to /Applications and launch: the copy that starts at login
	rm -rf "$(INSTALLED)"
	cp -R $(APP) "$(INSTALLED)"
	open "$(INSTALLED)"

uninstall: stop ## Quit the app and remove the installed copy from /Applications
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
