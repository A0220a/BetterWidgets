# Contributing

Use a Mac with a recent full Xcode installation. Open `BetterWidgets.xcodeproj` and the shared BetterWidgets scheme. The app has no third-party dependencies. See [README.md](README.md) for the build command and [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md) for the file-access boundary.

Describe the problem and the resulting behavior in a pull request. Keep media originals untouched and preserve saved widgets when access or decoding fails. Balance successful security-scoped access starts and stops; cancel background work when its owner disappears. Do not introduce private fixtures, developer teams, credentials, or local paths into tracked files.

Run checks relevant to the changed behavior. For changes to persistence, windows, media, or resource lifetime, use the scripts listed in [RELEASE.md](RELEASE.md). AppKit activation checks need a graphical desktop and briefly affect window focus. Login-item checks use a fake service. macOS 14 and Intel runtime compatibility require device checks.

Before pushing:

```sh
git diff --check
git add <reviewed-files>
python3 scripts/check-repository.py
git diff --cached --stat
git diff --cached
```

The hygiene script checks staged paths and common credential patterns; it is not a complete secret scanner or a substitute for reviewing media and history. Use a GitHub noreply commit email when personal email privacy matters.

No open-source license has been selected. Discuss licensing with the owner before relying on reuse rights.
