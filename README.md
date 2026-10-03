<p align="center">
  <img src="BetterWidgets/Assets.xcassets/AppIcon.appiconset/128.png" width="96" height="96" alt="BetterWidgets icon">
</p>

<h1 align="center">BetterWidgets</h1>

<p align="center">Images, animated GIFs, and looping videos on your Mac desktop.</p>

[![Build and checks](https://github.com/A0220a/BetterWidgets/actions/workflows/ci.yml/badge.svg)](https://github.com/A0220a/BetterWidgets/actions/workflows/ci.yml)

**macOS 14+ · Apple silicon & Intel · SwiftUI + AppKit · Local media**

[Build and run](#build-and-run) · [Privacy](#authentication-and-privacy) · [Distribution](#distribution) · [Contributing](CONTRIBUTING.md) · [Changelog](RELEASE_NOTES.md)

A native macOS menu bar app that puts images, animated GIFs, and looping videos on your desktop. Built with SwiftUI, AppKit, AVFoundation, and ImageIO.

## Features

- Add a media file, drop it onto Add Widget, or browse a folder in the media library.
- Move and resize widgets in Edit Widgets mode while preserving their proportions.
- Show, hide, replace, and delete widgets; mute or unmute videos.
- Restore media references, desktop positions, sizes, and enabled states after restarting.
- Follow moved files using macOS bookmarks and keep unavailable widgets available for replacement.
- Launch at login, reopen from the menu bar, and switch between desktop and manager windows.

Supported library formats: PNG, JPEG, HEIC, GIF, MP4, and MOV. Media stays in its original location.

## Build and run

The app targets **macOS 14 or later**. Development and local checks were verified with **Xcode 27.0** on Apple silicon. Use a recent full Xcode installation; Command Line Tools alone are insufficient. There are no third-party packages or services to configure.

Open `BetterWidgets.xcodeproj`, select the BetterWidgets scheme and My Mac, then run. The project uses local ad-hoc signing and does not require a developer team for this workflow. If Xcode has a different signing identity selected locally, choose Sign to Run Locally.

To build from Terminal:

```sh
xcodebuild -project BetterWidgets.xcodeproj -scheme BetterWidgets \
  -configuration Debug -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
open build/DerivedData/Build/Products/Debug/BetterWidgets.app
```

The manager opens on the first manual launch. Use the menu bar icon to reopen it afterward. Choose Add Widget or Add Folder, then Edit Widgets to arrange your desktop and Done to finish. Launch at Login is in the menu bar menu; macOS may require approval in System Settings → General → Login Items.

## Authentication and privacy

BetterWidgets has **no account login, backend, HTTP request flow, API keys, OAuth, or bearer tokens**. File access is authorized by macOS App Sandbox when you select media. The app persists read-only security-scoped bookmarks and holds file access while a widget or folder needs it. In-memory UUIDs track ownership of that access; they are not authentication credentials.

Saved state contains file URLs, folder names, bookmarks, and widget settings in `widgets.json` beneath the app's Application Support directory. In a sandboxed build this directory is inside the app container. The JSON is not encrypted by the app. Diagnostic output can also contain local paths. Treat saved state and logs as private when sharing bug reports.

See [authentication and file-access architecture](docs/AUTHENTICATION.md) for the components and complete flow, and [security reporting](SECURITY.md) for handling sensitive reports.

## Verification

Run the existing checks on a Mac with a graphical desktop session:

```sh
bash Tests/run-persistence-checks.sh
bash Tests/run-launch-at-login-checks.sh
bash Tests/run-release-readiness-checks.sh
bash Tests/run-app-window-activation-checks.sh
bash Tests/run-resource-lifecycle-checks.sh
```

These scripts create temporary stores and generated test media. Login-item checks use a fake service and do not change your Login Items. Activation checks briefly open temporary windows and affect focus. See [RELEASE.md](RELEASE.md) and [AUDIT.md](AUDIT.md) for coverage and device-testing limitations.

GitHub Actions builds a universal Release app and runs the isolated login-item checks. Interactive AppKit checks remain local. Check the workflow result before treating a revision as verified in CI.

## Distribution

```sh
bash scripts/build-release.sh
```

This creates a universal Apple silicon / Intel app, DMG, ZIP, checksums, and build reports in ignored `dist/`. The default package is ad-hoc signed and **not notarized**. Source publication is separate from a signed, notarized application release. [RELEASE.md](RELEASE.md) explains Developer ID signing and Keychain-based notarization.

macOS 14 and Intel runtime compatibility still require device testing. See [RELEASE_NOTES.md](RELEASE_NOTES.md) for the current feature list.

## Repository layout

| Path | Purpose |
| --- | --- |
| `BetterWidgets/` | App lifecycle, UI, desktop panels, playback, bookmarks, and persistence |
| `BetterWidgets.xcodeproj/` | Xcode project and shared scheme |
| `Tests/` | Standalone Swift checks and shell runners |
| `scripts/` | Release packaging and repository hygiene checks |
| `docs/` | Authentication, file access, and publication notes |

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and verification guidance. No open-source license has been selected; existing copyright notices apply.
