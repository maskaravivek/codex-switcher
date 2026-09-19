#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SRC=Sources
APP="build/CodexSwitcher.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build

SHARED=(
  "$SRC/Providers.swift"
  "$SRC/KeychainStore.swift"
  "$SRC/ConfigManager.swift"
  "$SRC/AppState.swift"
  "$SRC/SwitcherCore.swift"
)

# Menu bar app
swiftc -O -swift-version 5 -parse-as-library \
  "${SHARED[@]}" "$SRC/CodexSwitcherApp.swift" \
  -o "$APP/Contents/MacOS/CodexSwitcher"

# CLI (same core logic)
swiftc -O -swift-version 5 \
  "${SHARED[@]}" "$SRC/main.swift" \
  -o build/codex-switcher

cp Assets/deepseek-models.json "$APP/Contents/Resources/deepseek-models.json"
cp Assets/menu-bar-icon.png "$APP/Contents/Resources/menu-bar-icon.png"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexSwitcher</string>
  <key>CFBundleIdentifier</key>
  <string>com.vivek.codexswitcher</string>
  <key>CFBundleName</key>
  <string>CodexSwitcher</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built:"
echo "  $APP"
echo "  build/codex-switcher"

# Sign with a stable self-signed identity when available so Keychain entries
# survive rebuilds; otherwise fall back to ad-hoc signing.
if security find-certificate -c "CodexSwitcher Dev" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  echo "Signing with identity: CodexSwitcher Dev"
  codesign --force --sign "CodexSwitcher Dev" "$APP"
  codesign --force --sign "CodexSwitcher Dev" --identifier "com.vivek.codexswitcher" build/codex-switcher
else
  echo "Note: 'CodexSwitcher Dev' identity not found — ad-hoc signing (run scripts/setup-signing.sh once)."
  codesign --force --sign - "$APP"
  codesign --force --sign - --identifier "com.vivek.codexswitcher" build/codex-switcher
fi
