# Security and privacy

BetterWidgets uses macOS App Sandbox and read-only access to user-selected media. The current app has no account system, backend, analytics SDK, or network API client. See [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md) for authorization and persistence details.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** option when private vulnerability reporting is enabled. If it is unavailable, create an issue requesting a private reporting channel and include no sensitive details until a private channel has been arranged.

Include the revision/version, macOS and Xcode versions, reproduction steps, and expected versus actual behavior. Use generated sample media and redact logs. Never publish passwords, signing keys, certificates, local file paths, real media, or `widgets.json`; snapshots contain bookmarks and private paths.

There is no promised support window or response SLA. Reports against the current default branch are the most useful.

## Keeping publication clean

- Keep signing certificates and notarization credentials in the macOS Keychain.
- Keep generated packages, logs, local media, runtime state, and Xcode user settings outside tracked source.
- Run `python3 scripts/check-repository.py` against the staged files before publishing.
- Review the complete diff and all commits being pushed. Ignore rules do not remove data from old commits.
- If a real credential is published, revoke or rotate it before addressing repository history.
