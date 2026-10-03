#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${BETTERWIDGETS_RELEASE_DIR:-$repo_dir/dist}"
sign_identity="${BETTERWIDGETS_SIGN_IDENTITY:--}"
notary_profile="${BETTERWIDGETS_NOTARY_PROFILE:-}"
sign_team=''
if [[ "$sign_identity" == 'Developer ID Application:'* ]]; then
    sign_team="${sign_identity##*\(}"
    sign_team="${sign_team%\)}"
fi
work_dir="$(mktemp -d /tmp/BetterWidgets-release.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT

if [[ "$sign_identity" != - && "$sign_identity" != 'Developer ID Application:'* ]]; then
    echo 'Use a Developer ID Application identity for distribution, or leave the identity unset for a local build.' >&2
    exit 1
fi
if [[ -n "$notary_profile" && "$sign_identity" == - ]]; then
    echo 'Notarization requires BETTERWIDGETS_SIGN_IDENTITY with a Developer ID Application certificate.' >&2
    exit 1
fi

mkdir -p "$output_dir"
xcodebuild -project "$repo_dir/BetterWidgets.xcodeproj" -scheme BetterWidgets \
    -configuration Release -derivedDataPath "$work_dir/DerivedData" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="$sign_identity" DEVELOPMENT_TEAM="$sign_team" CODE_SIGNING_ALLOWED=YES \
    build > "$output_dir/build.log" 2>&1 || {
        tail -n 60 "$output_dir/build.log" >&2
        exit 1
    }
app_dir="$work_dir/DerivedData/Build/Products/Release/BetterWidgets.app"
info_plist="$app_dir/Contents/Info.plist"
release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
release_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")"
release_name="BetterWidgets-$release_version"
package_dir="$work_dir/package"
mkdir -p "$package_dir"
ditto "$app_dir" "$package_dir/BetterWidgets.app"
ln -s /Applications "$package_dir/Applications"
cat > "$package_dir/Read Me.txt" <<TXT
BetterWidgets $release_version (build $release_build)
Requires macOS $minimum_macos or later. Supports Apple silicon and Intel Macs.

Installation: drag BetterWidgets to Applications, then open it.
The manager opens on the first manual launch. Later, use the menu bar icon.
Add images, GIFs, and videos with Add Widget, or browse a folder with Add Folder.
Choose Edit Widgets to move or resize desktop widgets, then click Done.
If a file becomes unavailable, use Replace File in its saved card.
Launch at Login is available in the menu bar menu.
TXT
signature_status='Developer ID signed; not notarized'
if [[ "$sign_identity" == - ]]; then
    signature_status='Local build with an ad-hoc signature; not notarized'
    printf '\nThis local build has not been notarized by Apple.\n' >> "$package_dir/Read Me.txt"
fi

codesign --verify --deep --strict "$package_dir/BetterWidgets.app"
for architecture in arm64 x86_64; do
    /usr/bin/lipo "$package_dir/BetterWidgets.app/Contents/MacOS/BetterWidgets" -verify_arch "$architecture"
done
zip_file="$output_dir/$release_name.zip"
dmg_file="$output_dir/$release_name.dmg"
ditto -c -k --sequesterRsrc --keepParent "$package_dir/BetterWidgets.app" "$zip_file"
if [[ -n "$notary_profile" ]]; then
    xcrun notarytool submit "$zip_file" --keychain-profile "$notary_profile" --wait --output-format json > "$output_dir/notarization-app.json"
    plutil -extract status raw -o - "$output_dir/notarization-app.json" | /usr/bin/grep -qx Accepted || {
        echo 'App notarization was not accepted. See notarization-app.json.' >&2
        exit 1
    }
    xcrun stapler staple "$package_dir/BetterWidgets.app"
    ditto -c -k --sequesterRsrc --keepParent "$package_dir/BetterWidgets.app" "$zip_file"
fi
hdiutil create -volname "BetterWidgets $release_version" -srcfolder "$package_dir" \
    -format UDZO -ov "$dmg_file" > "$output_dir/dmg-build.log"
if [[ "$sign_identity" != - ]]; then
    codesign --sign "$sign_identity" --timestamp "$dmg_file"
fi
if [[ -n "$notary_profile" ]]; then
    xcrun notarytool submit "$dmg_file" --keychain-profile "$notary_profile" --wait --output-format json > "$output_dir/notarization-dmg.json"
    plutil -extract status raw -o - "$output_dir/notarization-dmg.json" | /usr/bin/grep -qx Accepted || {
        echo 'Disk image notarization was not accepted. See notarization-dmg.json.' >&2
        exit 1
    }
    xcrun stapler staple "$dmg_file"
    xcrun stapler validate "$dmg_file"
    spctl --assess --type execute --verbose=2 "$package_dir/BetterWidgets.app"
    signature_status='Developer ID signed and notarized by Apple'
fi
cat > "$output_dir/RELEASE.txt" <<TXT
BetterWidgets $release_version (build $release_build)
Minimum macOS: $minimum_macos
Architectures: arm64, x86_64
Signature: $signature_status
Artifacts: $release_name.dmg, $release_name.zip
TXT
(cd "$output_dir" && shasum -a 256 "$release_name.dmg" "$release_name.zip" > SHA256SUMS.txt)
printf 'Created %s\nSignature: %s\n' "$dmg_file" "$signature_status"
