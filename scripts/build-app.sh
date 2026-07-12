#!/bin/bash
# Builds a double-clickable "Podcast Transcript Studio.app" from the SwiftPM package, so it can
# be launched from Finder/Dock without the terminal. Output: dist/Podcast Transcript Studio.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_DISPLAY_NAME="Podcast Transcript Studio"
BIN_NAME="PodcastTranscriptStudio"
BUNDLE_ID="dk.netsi.podcasttranscriptstudio"
# Version comes from one source: the git tag. Prefer an explicit $VERSION (CI passes the tag),
# else the latest tag, else a dev marker. A leading "v" is stripped.
_candidate="${VERSION:-}"
_candidate="${_candidate#v}"
if [[ "$_candidate" =~ ^[0-9] ]]; then
    VERSION="$_candidate"
else
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
    VERSION="${VERSION:-0.0.0-dev}"
fi
echo "▶︎ Version: $VERSION"

BUILD_DIR="$ROOT/.build/release"
DIST="$ROOT/dist"
APP="$DIST/$APP_DISPLAY_NAME.app"
CONTENTS="$APP/Contents"

echo "▶︎ Building release binary…"
swift build -c release

echo "▶︎ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# Executable
cp "$BUILD_DIR/$BIN_NAME" "$CONTENTS/MacOS/$BIN_NAME"

# SwiftPM resource bundle (default prompts, used via Bundle.module). Placed in Resources so
# Bundle.main.resourceURL resolves it inside the .app.
for bundle in "$BUILD_DIR/"*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$CONTENTS/Resources/"
done

# Icon: reuse the app's own drawing to generate an .icns.
echo "▶︎ Generating icon…"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
"$CONTENTS/MacOS/$BIN_NAME" --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$BIN_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key><string>© Sten Hougaard (netsi1964)</string>
</dict>
</plist>
PLIST

# Classic package marker.
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Ad-hoc code signature so macOS treats it as a stable app identity (no Developer ID required
# for personal/local use).
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (ad-hoc signing skipped)"
fi

echo "✅ Built: $APP"
echo "   Double-click it in Finder, or run: open \"$APP\""
