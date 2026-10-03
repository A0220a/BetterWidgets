# Resource and bug audit — 2026-10-02

Environment: Apple silicon, macOS 27.0 (26A428), Xcode 27.0 (27A266a). The release remains compatible at build time with macOS 14 and includes arm64 and x86_64 binaries.

## Fixed findings

| Finding | Change |
| --- | --- |
| Closing a widget could leave its hosted media alive while the panel remained referenced. | Closing detaches the hosting view, stops video, and clears callbacks. GIF teardown clears its timer, source, and decoded frame. |
| GIF decoding could accumulate cached frames; detached or single-frame GIFs could schedule unnecessary work. | Disable ImageIO frame caching and schedule animation only while attached, with more than one frame. A failed GIF replacement clears the previous frame. |
| Video errors were observed on the looper's template rather than its playing replicas. | Observe the current player item and the looper; invalidate observations and disable looping before removing items. Stopping is idempotent. |
| Thumbnail storage and asynchronous generation were unbounded; duplicate requests repeated work and changed files could retain stale previews. | Set cache limits of 128 images and 32 MiB of decoded-image cost, coalesce requests, allow two active generators, and include file revision/type in cache keys. |
| Folder scans and image metadata could block the UI; a removed folder could receive a late scan result. | Move scans and image metadata off the main thread. Cancel obsolete scans and publish only the current operation for an existing folder. |
| A directory named with a media extension appeared as a file. | Require a regular file during folder scans. |
| Repeated folder moves could prevent security-scoped access from being released because a bookmarked URL's path can change. Failed scope acquisition was also counted as a successful start. | Track each owner with a stable token, retain the exact successfully acquired URL, retry acquisition when a usable bookmark arrives, and stop only successful starts at the final release. |
| Duplicate saved identities could overwrite dictionaries while leaving windows/access owners alive. | Reject such saves before restoring resources; retain the original save file on failure. |
| Background launch constructed an unused manager; the system Settings command opened an empty view and About bypassed the custom window presenter. | Construct the manager on demand, remove the Settings command, and route About through the presenter. |

## Verification

- Persistence checks: creation, bookmark restoration, frame saving, enabled state, deletion, legacy saves, and read/write failure protection.
- Launch-at-login checks: status updates, registration, approval, errors, idempotence, and repeated toggles using a fake service.
- Release-readiness checks: image/GIF/orientation metadata, resizing and replacement, missing/returned/moved files, metadata arriving after user interaction, restoration, and launch policy.
- Activation checks: actual system menu ownership, reactivation, minimizing, About, final-window close, deferred close/reopen, and modal windows.
- Resource checks: GIF frame advancement, valid/corrupt replacement, teardown while the panel is retained, deallocation of all 80 repeatedly opened/closed panels, corrupt video reporting, eight valid video start/stop cycles, controller deallocation, native GIF/video thumbnails, coalescing 40 duplicate preview requests, two-generator concurrency, file revision changes, repeated folder moves, access balancing, removal races, and duplicate-save protection.
- Universal Release build, signature/architecture verification, and DMG/ZIP checksum verification.

## Memory analyzer result

The unfiltered `leaks --atExit` workload and the empty AppKit baseline both report three `NSXPCConnection` root cycles for `com.apple.linkd.autoShortcut`. Their allocation stacks originate in Apple's `LNProcessInstanceRegistryClient.makeXPCConnection` and `NSXPCConnection(ApplicationService).ln_applicationServiceWithError:`. The baseline reports 411 allocations / 26,224 bytes; workload runs report approximately 416–417 allocations / 26,400–26,496 bytes, all beneath those same three system roots. These framework findings remain visible and cause the analyzer to exit with status 1. No exclusion or suppression is applied.

Application window/controller deallocation and sandbox start/stop balancing pass in the exercised scenarios. This does not establish that every possible long-running workload is leak-free. Raw reports are retained in `dist/audit/resource-leaks.log` and `dist/audit/baseline-leaks.log`.

The temporary test executable receives `get-task-allow` only for memory inspection; production entitlements are unchanged. Native bookmark moves are exercised with injected, countable scope acquisition. Actual sandbox prompts, extended playback with large media/cloud folders, macOS 14 and Intel runtime behavior, and genuine trackpad fullscreen-Space gestures still require device testing.
