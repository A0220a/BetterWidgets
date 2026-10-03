#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /tmp/BetterWidgets-persistence-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
sources=()
for source in "$repo_dir"/BetterWidgets/*.swift; do
    if [[ "$(basename "$source")" != "BetterWidgetsApp.swift" ]]; then
        sources+=("$source")
    fi
done
xcrun swiftc -swift-version 5 -module-cache-path "$check_dir/ModuleCache" \
    -parse-as-library "${sources[@]}" "$repo_dir/Tests/WidgetPersistenceChecks.swift" \
    -o "$check_dir/check"
codesign --force --sign - --identifier Amantaev.BetterWidgets.PersistenceChecks \
    --entitlements "$repo_dir/BetterWidgets/BetterWidgets.entitlements" "$check_dir/check"
"$check_dir/check" write "$check_dir"
"$check_dir/check" read "$check_dir"
"$check_dir/check" compatibility "$check_dir"
