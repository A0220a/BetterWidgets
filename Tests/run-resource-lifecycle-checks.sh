#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /tmp/BetterWidgets-resource-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
sources=()
for source in "$repo_dir"/BetterWidgets/*.swift; do
    if [[ "$(basename "$source")" != "BetterWidgetsApp.swift" ]]; then
        sources+=("$source")
    fi
done
xcrun swiftc -swift-version 5 -module-cache-path "$check_dir/ModuleCache" \
    -parse-as-library "${sources[@]}" "$repo_dir/Tests/ResourceLifecycleChecks.swift" \
    -o "$check_dir/check"
cp "$repo_dir/BetterWidgets/BetterWidgets.entitlements" "$check_dir/check.entitlements"
if [[ "${BETTERWIDGETS_CHECK_LEAKS:-0}" == 1 ]]; then
    /usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool true' "$check_dir/check.entitlements"
fi
codesign --force --sign - --identifier Amantaev.BetterWidgets.ResourceChecks \
    --entitlements "$check_dir/check.entitlements" "$check_dir/check"
check_args=("$check_dir")
if [[ "${BETTERWIDGETS_CHECK_BASELINE:-0}" == 1 ]]; then
    check_args+=(--baseline)
fi
if [[ "${BETTERWIDGETS_CHECK_LEAKS:-0}" == 1 ]]; then
    MallocStackLogging=1 leaks --atExit -- "$check_dir/check" "${check_args[@]}"
else
    "$check_dir/check" "${check_args[@]}"
fi
