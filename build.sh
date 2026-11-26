#!/bin/bash
# Builds "Usage Monitor.app" (menu bar app + desktop widget) into ./build.
# Pass --install to copy it to /Applications and launch it (needed for the widget to show up).
set -euo pipefail
cd "$(dirname "$0")"

# WidgetKit needs a real signing identity; use the first Developer ID / Apple Development one.
IDENTITY=$(security find-identity -v -p codesigning | grep -Eo '"(Developer ID Application|Apple Development): [^"]+"' | head -1 | tr -d '"' || true)
TEAM=$(sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p' <<<"$IDENTITY")
if [[ -z "$TEAM" ]]; then
    echo "warning: no signing identity found; signing ad hoc (the desktop widget may not load)" >&2
    IDENTITY="-"; TEAM="LOCAL"
fi
BUNDLE_ID="dev.usagemonitor.app"
GROUP="$TEAM.$BUNDLE_ID"
VERSION=$(date +%s) # fresh build number so WidgetKit picks up new widget code

swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP="build/Usage Monitor.app"
APPEX="$APP/Contents/PlugIns/UsageWidget.appex"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS"
cp "$BIN/UsageMonitor" "$APP/Contents/MacOS/"
cp "$BIN/UsageWidget" "$APPEX/Contents/MacOS/"

plist() { # path, bundle id, executable, package type, extra xml
    cat > "$1" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Usage Monitor</string>
    <key>CFBundleDisplayName</key><string>Usage Monitor</string>
    <key>CFBundleIdentifier</key><string>$2</string>
    <key>CFBundleExecutable</key><string>$3</string>
    <key>CFBundlePackageType</key><string>$4</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>UsageAppGroup</key><string>$GROUP</string>
    $5
</dict>
</plist>
PLIST
}
plist "$APP/Contents/Info.plist" "$BUNDLE_ID" UsageMonitor APPL \
    '<key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/>'
plist "$APPEX/Contents/Info.plist" "$BUNDLE_ID.widget" UsageWidget 'XPC!' \
    '<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>'

entitlements() { # path, sandboxed
    cat > "$1" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><$2/>
    <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict>
</plist>
PLIST
}
mkdir -p build/entitlements
entitlements build/entitlements/widget.plist true
entitlements build/entitlements/app.plist false

codesign --force --sign "$IDENTITY" --entitlements build/entitlements/widget.plist "$APPEX"
codesign --force --sign "$IDENTITY" --entitlements build/entitlements/app.plist "$APP"
echo "Built $APP (signed: $IDENTITY)"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x UsageMonitor 2>/dev/null || true
    rm -rf "/Applications/Usage Monitor.app"
    cp -R "$APP" /Applications/
    open "/Applications/Usage Monitor.app"
    echo "Installed to /Applications — add the widget via right-click on the desktop → Edit Widgets"
fi
