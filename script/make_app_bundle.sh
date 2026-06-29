#!/usr/bin/env bash
# make_app_bundle.sh — wrap the swift binary into a real .app bundle.
#
# Produces: ~/{DEST}/HarnessApp.app
# Default DEST: ~/Applications/harness-app/
#
# Optional: codesign with an ad-hoc Apple Developer ID when
# $HARNESS_APP_IDENTITY is set. Otherwise signs adhoc.
#
# Usage:
#   script/make_app_bundle.sh                 # build + bundle + sign
#   script/make_app_bundle.sh --release       # release config + bundle + sign

set -euo pipefail

CONFIG="debug"
RELEASE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) CONFIG="release"; RELEASE=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${HOME}/Applications/harness-app"
APP_NAME="HarnessApp"
BUNDLE_ID="com.rasputinkaiser.harnessapp"
MIN_SYS_VERSION="14.0"

echo "=== building ($CONFIG) ==="
cd "$REPO_ROOT"
if [ "$RELEASE" -eq 1 ]; then
  swift build -c release 2>&1 | sed 's/^/  /'
  BUILD_DIR=".build/release"
else
  swift build 2>&1 | sed 's/^/  /'
  BUILD_DIR=".build/debug"
fi

BIN_SRC="$BUILD_DIR/$APP_NAME"
if [ ! -x "$BIN_SRC" ]; then
  echo "ERR: executable not found at $BIN_SRC" >&2
  exit 1
fi

echo
echo "=== building .app bundle ==="
mkdir -p "$DEST_DIR"
APP_ROOT="$DEST_DIR/$APP_NAME.app"
rm -rf "$APP_ROOT"

# Standard macOS bundle layout
mkdir -p "$APP_ROOT/Contents/MacOS"
mkdir -p "$APP_ROOT/Contents/Resources"

# Copy executable
cp "$BIN_SRC" "$APP_ROOT/Contents/MacOS/$APP_NAME"
chmod +x "$APP_ROOT/Contents/MacOS/$APP_NAME"

# Write Info.plist
cat > "$APP_ROOT/Contents/Info.plist" <<PLIST_END
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Harness App</string>
  <key>CFBundleDisplayName</key>
  <string>Harness App</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key>
  <string>0.7.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.7.0-dev</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYS_VERSION</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMainNibFile</key>
  <string></string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST_END

# PkgInfo — 8 bytes for ancient compatibility
echo -n "APPL????" > "$APP_ROOT/Contents/PkgInfo"

echo
echo "=== codesigning ==="
IDENTITY="${HARNESS_APP_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  # Ad-hoc sign if no Developer ID configured. Works locally; not distributable.
  IDENTITY="-"
fi
ENTITLEMENTS_FILE="$(mktemp "${TMPDIR:-/tmp}/harness-app-entitlements.XXXXXX.plist")"
trap 'rm -f "$ENTITLEMENTS_FILE"' EXIT
cat > "$ENTITLEMENTS_FILE" <<ENT_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <true/>
  <key>com.apple.security.automation.apple-events</key>
  <true/>
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
</dict>
</plist>
ENT_EOF
set +e
codesign --force --deep --sign "$IDENTITY" \
  --options runtime \
  --entitlements "$ENTITLEMENTS_FILE" \
  "$APP_ROOT"

SIGN_RC=$?
set -e

if [ "$SIGN_RC" -ne "0" ]; then
  echo "WARN: codesign exit $SIGN_RC — entitlements signing failed."
  echo "Falling back to plain ad-hoc signature (no entitlements)."
  codesign --force --deep --sign - "$APP_ROOT" 2>/dev/null || true
fi

# Verify
echo
echo "=== verifying ==="
codesign -dv --verbose=1 "$APP_ROOT" 2>&1 | head -6
file "$APP_ROOT/Contents/MacOS/$APP_NAME"

echo
echo "=== bundle ready: $APP_ROOT ==="
echo "Open with: open \"$APP_ROOT\""
echo "(If macOS blocks it due to Gatekeeper — 'right-click → Open' to add the developer trust exception.)"
