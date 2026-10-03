#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /tmp/BetterWidgets-login-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$check_dir/ModuleCache" \
    -parse-as-library "$repo_dir/BetterWidgets/LaunchAtLoginManager.swift" \
    "$repo_dir/Tests/LaunchAtLoginChecks.swift" -o "$check_dir/check"
"$check_dir/check"
