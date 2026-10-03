# Source publication review — 2026-10-04

## Scope and findings

The publication snapshot includes the app source, Xcode project and shared scheme, app icons, existing standalone checks, release scripts, and documentation. App state and user-selected media are stored outside the source tree.

- Removed developer-team settings from the published project and set local ad-hoc signing as the default. Developer ID distribution still uses the release script's explicit signing override.
- Removed Xcode `xcuserdata` from the publication index while preserving the local file.
- Excluded `.DS_Store`, build products, `dist/`, runtime `widgets.json`, private media, logs, environment files, and signing material. The existing local `dist/` remains available but is not source-controlled.
- Inspected the app icons' embedded EXIF metadata: it contains only color-space and pixel-dimension fields, with no personal metadata. The icons are the only binary assets in the source snapshot.
- Scanned the prepared source snapshot with Gitleaks 8.30.1: no secrets found. The repository hygiene script separately checks tracked paths, common credential patterns, personal email addresses, local home paths, and hard-coded developer teams. These checks do not prove that every possible secret format is absent.
- The old local initial commit contains personal author metadata and user-specific Xcode state. It is not an ancestor of the publication commit. It remains on the original local branch. The publication uses the new GitHub repository's initial commit as its parent and a GitHub noreply author/committer address.

## Verification

All five existing check scripts passed on the reviewed local source with Xcode 27.0:

- Widget persistence and fresh-process restoration, including read/write failure protection.
- Fake-service login-item registration, approval, errors, and repeated toggles.
- Media metadata, replacement, file movement/availability, resizing, and launch policy.
- App activation, menu ownership, minimizing, About, closing, and reopening.
- Resource lifecycle, GIF/video teardown, thumbnail concurrency/cache behavior, folder scopes, removal races, and duplicate-identity protection.

The universal Release build and the package script passed, including signature and arm64/x86_64 verification. The generated distribution package is ad-hoc signed and not notarized. The checks above do not replace macOS 14/Intel device testing or the manual Spaces gesture check documented in [RELEASE.md](../RELEASE.md).

## Repository and remaining choices

The source repository is intended to be public. GitHub Actions has read-only contents permission, a pinned checkout action, and no signing/notarization credentials. It builds the universal app and runs fake-service login-item checks; interactive window checks run locally. Verify the actual workflow result after publication.

No open-source license has been selected, and no signed/notarized application release is claimed. Choose a license before describing the project as licensed for open-source reuse. Keep future commits and any branches pushed to GitHub under review; `.gitignore` cannot remove information from historical commits.
