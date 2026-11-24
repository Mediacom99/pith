#!/bin/sh
# Installs Pith, a keyboard launcher for the Mac: https://pith.edoardobertoli.xyz
#
#   curl -fsSL https://pith.edoardobertoli.xyz/install.sh | sh
#
# It downloads the newest Pith.dmg, checks that the Pith inside is signed with Pith's own certificate, copies it into
# /Applications (~/Applications if that isn't writable) and opens it. A file curl downloads isn't marked as coming
# from the internet, so macOS doesn't stop Pith the first time it opens: no Open Anyway (decision 57). A Pith already
# there is quit and replaced; its settings and history stay. PITH_DIR=<folder> installs somewhere else.
set -eu

site="https://pith.edoardobertoli.xyz"
# The certificate every Pith build is signed with (decision 41): anything else isn't installed.
requirement='identifier "dev.edoardo.pith" and certificate leaf = H"0e63e9c279e89ea9c2cefa6ac1aff525d6925218"'

fail() {
    printf 'Pith: %s\n' "$1" >&2
    exit 1
}

[ "$(uname -s)" = Darwin ] || fail "it runs on macOS only."
[ "$(uname -m)" = arm64 ] || fail "it needs a Mac with Apple Silicon."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ] || fail "it needs macOS 26 Tahoe or later."

dir=${PITH_DIR:-/Applications}
if [ -z "${PITH_DIR:-}" ] && [ ! -w /Applications ]; then dir="$HOME/Applications"; fi
mkdir -p "$dir" || fail "can't create $dir."
app="$dir/Pith.app"

work=$(mktemp -d)
mount="$work/mount"
cleanup() {
    hdiutil detach -quiet "$mount" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

printf 'Downloading Pith…\n'
curl -fsSL --proto '=https' -o "$work/Pith.dmg" "$site/Pith.dmg" || fail "couldn't download $site/Pith.dmg."
mkdir "$mount"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$work/Pith.dmg" || fail "couldn't open the download."
codesign --verify --deep --strict -R="$requirement" "$mount/Pith.app" 2>/dev/null ||
    fail "the download isn't signed with Pith's certificate, so it wasn't installed."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mount/Pith.app/Contents/Info.plist")

# An update this Pith downloaded waits to install as soon as Pith quits, even when it's stopped: it's dropped first,
# so it can't put an older build over this one. Sparkle downloads the newest again on its next check.
if [ -d "$app" ]; then
    launchctl remove dev.edoardo.pith-sparkle-updater 2>/dev/null || true
    launchctl remove dev.edoardo.pith-sparkle-progress 2>/dev/null || true
    pkill -f "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null || true
    rm -rf "$HOME/Library/Caches/dev.edoardo.pith/org.sparkle-project.Sparkle"
fi
if pkill -f "$app/Contents/MacOS/Pith" 2>/dev/null; then
    tries=0
    while pgrep -f "$app/Contents/MacOS/Pith" >/dev/null && [ "$tries" -lt 50 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
fi
rm -rf "$app"
ditto "$mount/Pith.app" "$app" || fail "couldn't copy Pith into $dir."
printf 'Pith %s is in %s.\n' "$version" "$dir"

# Only a copy in an Applications folder starts at login and updates itself.
case "$dir" in
/Applications | "$HOME/Applications")
    open "$app"
    printf 'Press ⌘P to open it. The first paste from the clipboard history asks for Accessibility.\n'
    ;;
*)
    printf 'It starts at login and updates itself only from an Applications folder.\n'
    ;;
esac
