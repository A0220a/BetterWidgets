# Building BetterWidgets 1.0

Version: **1.0**, build **1**. Deployment target: **macOS 14.0**.

## Checks

```sh
bash Tests/run-persistence-checks.sh
bash Tests/run-launch-at-login-checks.sh
bash Tests/run-release-readiness-checks.sh
bash Tests/run-app-window-activation-checks.sh
bash Tests/run-resource-lifecycle-checks.sh
```

These checks use temporary media, stores, and preferences. Login-item checks use a fake service and do not alter the user's Login Items.

Activation checks use a temporary agent app to verify focus, system menu ownership, reopening, and the return to background mode. For the gesture-specific check, open the manager, switch to another app's fullscreen Space, and return: BetterWidgets and its menu must reappear without first clicking another app. The Dock icon stays while the manager or About window is open and disappears after both close.

Resource checks cover animated GIF teardown, 80 window creation/closure cycles, valid and corrupt video playback, thumbnail request coalescing and concurrency, moved folder bookmarks, balanced access ownership, and corrupt saves with duplicate identities. Media and stores are temporary; sandbox ownership uses an injected start/stop implementation so it can be counted exactly.

To inspect allocations, run both the workload and an empty AppKit baseline:

```sh
BETTERWIDGETS_CHECK_LEAKS=1 bash Tests/run-resource-lifecycle-checks.sh
BETTERWIDGETS_CHECK_LEAKS=1 BETTERWIDGETS_CHECK_BASELINE=1 bash Tests/run-resource-lifecycle-checks.sh
```

Leak mode enables debugging only on the temporary test executable and preserves the analyzer's exit status and all findings. On the audited macOS 27 build, both runs report the same three system AppIntents/LinkServices XPC root cycles and exit with status 1. Compare the root stacks before attributing those findings to the application. See [AUDIT.md](AUDIT.md) for results and limitations.

## Local release package

```sh
bash scripts/build-release.sh
```

The script builds a universal app for Apple silicon and Intel, verifies its signature and architectures, and creates `dist/BetterWidgets-1.0.dmg`, `dist/BetterWidgets-1.0.zip`, checksums, and a release report. The DMG contains the app and an Applications shortcut. By default, the build has an ad-hoc signature and has not been notarized by Apple.

## Public distribution outside the Mac App Store

Install a **Developer ID Application** certificate and create a notarization Keychain profile with `xcrun notarytool store-credentials`. Keep passwords and API keys out of this repository.

```sh
BETTERWIDGETS_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAM ID)' \
BETTERWIDGETS_NOTARY_PROFILE='YOUR_KEYCHAIN_PROFILE' \
bash scripts/build-release.sh
```

The script submits the app and DMG to Apple's notary service, requires an Accepted result, staples the tickets, and validates the result. `dist/RELEASE.txt` records the actual signing and notarization status. An Apple Development certificate cannot replace Developer ID for this distribution flow.

Apple documentation: https://developer.apple.com/developer-id/

## Final device checks

The deployment target and universal binary are verified during compilation. Before promising runtime compatibility with every supported Mac, check the app on macOS 14 and an Intel Mac, including first launch, media playback, desktop editing, restart, and login launch. These device checks cannot be substituted by building on a newer Apple silicon Mac.
