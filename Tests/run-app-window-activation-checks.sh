#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /tmp/BetterWidgets-activation-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
app_dir="$check_dir/BetterWidgets Menu Checks.app"
mkdir -p "$app_dir/Contents/MacOS"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>ActivationChecks</string>
    <key>CFBundleIdentifier</key><string>Amantaev.BetterWidgets.ActivationChecks</string>
    <key>CFBundleName</key><string>BetterWidgets Menu Checks</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun swiftc -swift-version 5 -module-cache-path "$check_dir/ModuleCache" \
    -parse-as-library "$repo_dir/BetterWidgets/AppWindowPresenter.swift" \
    "$repo_dir/Tests/AppWindowActivationChecks.swift" \
    -o "$app_dir/Contents/MacOS/ActivationChecks"
codesign --force --sign - "$app_dir"
# LaunchServices must register the bundle before the process can own the menu
# bar. Running the binary directly cannot exercise that macOS behavior.
open -n -W --stdout "$check_dir/output.log" --stderr "$check_dir/output.log" "$app_dir"
cat "$check_dir/output.log"
rg -q '^PASS: minimize, About, last-window close, deferred close, and reopen$' "$check_dir/output.log"
