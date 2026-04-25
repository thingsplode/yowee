# Yowee — Developer Reference

This document describes the shell scripts used to develop, build, and publish Yowee, the order in which they should be used, and when to reach for each one.

---

## Script overview

| Script | When to run | Requires |
|---|---|---|
| `build_run.sh` | Every development iteration | Xcode, optional tools |
| `notarizer.sh` | Before publishing a release | Developer ID cert, Apple credentials |
| `publisher.sh` | After notarizer, to ship the release | Notarized app, `gh`, `create-dmg` |

---

## `build_run.sh` — daily development loop

**Purpose**: lint → test → static analysis → build → sign → launch. The single command for day-to-day development. Run it instead of using Xcode's ⌘R when you want the full quality gate.

```bash
./build_run.sh                # full pipeline + launch
./build_run.sh --no-launch    # full pipeline, don't open the app
./build_run.sh --fast         # skip static analysis and coverage
./build_run.sh --no-test      # skip unit tests
./build_run.sh --fast --no-launch   # quick build only
```

### What it does, in order

| Step | Tool | Skip flag |
|---|---|---|
| Preflight | Xcode version check; auto-fixes DVTDownloads plugin mismatch | — |
| Git hooks | Ensures `.githooks/` is active (GitLeaks pre-commit) | — |
| Dependencies | Checks SwiftLint, SwiftFormat, Periphery, GitLeaks, Ollama; offers `brew install` for each | — |
| SwiftLint | Style and correctness rules | tool not installed |
| SwiftFormat | Formatting drift check (`--lint` mode — does not modify files) | tool not installed |
| Unit tests | `swift run TestRunner` (YoweeCore only, no Xcode needed) | `--no-test` |
| Static analysis | `xcodebuild analyze` (Clang analyzer) | `--fast` |
| Dead code | Periphery unused-declaration scan | `--fast` or not installed |
| Build | `xcodebuild build` Debug configuration | — |
| Coverage | `xcodebuild test -enableCodeCoverage` + `xcrun xccov` | `--fast` |
| Assemble + sign | Copies binary + `Info.plist` to `~/Desktop/yowee.app`; ad-hoc codesigns | build must pass |
| Launch | `open ~/Desktop/yowee.app` | `--no-launch` |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All hard checks passed (warnings allowed) |
| `1` | Build failed, a test failed, or static analysis reported errors |

Warnings from SwiftLint, SwiftFormat, Periphery, and coverage do **not** block the build.

### When to use which flags

- **Normal work** — `./build_run.sh`. Gets you a freshly-signed app on the Desktop and the full quality report.
- **Quick compile check** — `./build_run.sh --fast --no-launch`. Runs lint + tests + build; skips the slow analysis and coverage passes. Use this when iterating on a specific function and you just want to know if it compiles and tests pass.
- **CI / pre-commit sanity** — `./build_run.sh --no-launch`. Full gate without opening the app.
- **Test-only** — `swift run TestRunner` directly. Faster than the full script when you only want test feedback.

### Notes

- The assembled app lands at `~/Desktop/yowee.app`, **not** in the project's `build/` directory. The `build/` directory is reserved for release artifacts produced by `notarizer.sh`.
- The ad-hoc signature (`codesign --sign -`) is intentional during development. It changes with every rebuild, which is why `AppDelegate.warmUpKeychain()` fires at startup — it pre-authorises the new identity before any pipeline runs.
- If you see an "Allow" dialog for Keychain on launch after a rebuild, click Allow. The item was saved under the old identity's ACL. Once you re-enter the API key in Settings → Providers it will be written with the open-access ACL and the dialog will not appear again.

---

## `notarizer.sh` — release signing and notarization

**Purpose**: produce a Developer ID–signed, Apple-notarized, stapled `.app` in `build/yowee.app`. This is a prerequisite for `publisher.sh`. Do **not** use this for development builds — it targets the Release configuration and requires real Apple credentials.

```bash
export NOTARIZE_TEAM_ID="XXXXXXXXXX"       # 10-char Apple Developer team ID
export NOTARIZE_APPLE_ID="you@example.com"
export NOTARIZE_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # app-specific password

./notarizer.sh
```

Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords.

### What it does, in order

| Step | Detail |
|---|---|
| Preflight | Verifies Developer ID cert is in the keychain; checks `xcrun notarytool` is available; checks `Info.plist` is present |
| Build | `xcodebuild build` Release, signing with the Developer ID cert and `--options runtime` (hardened runtime, required by notary) |
| Assemble | Creates `build/yowee.app` with the Release binary, `Info.plist`, and icon |
| Sign | `codesign --force --deep --timestamp --options runtime` with the Developer ID cert |
| Zip | `ditto` zip of the `.app` (preserves macOS metadata; required by notary service) |
| Notarize | `xcrun notarytool submit --wait`; prints full Apple response |
| Staple | `xcrun stapler staple` — attaches the notarization ticket to the bundle |
| Verify | `xcrun stapler validate` + `spctl --assess --type open` |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All steps passed; `build/yowee.app` is ready to ship |
| `1` | Any step failed (see summary table output) |

### Notes

- The notarization upload can take 1–5 minutes depending on Apple's queue. The script uses `--wait` and blocks until Apple responds.
- If notarization fails, the script fetches and prints the detailed rejection log automatically.
- **Never run `notarizer.sh` for development.** The Release build is slower, and the Developer ID signature is bound to the certificate — it will cause Keychain prompts unless your Keychain items were saved with the open-access ACL pattern.
- The output app at `build/yowee.app` is what `publisher.sh` picks up. Do not move or rename it between the two scripts.

---

## `publisher.sh` — DMG packaging, GitHub release, Homebrew tap

**Purpose**: take the stapled `build/yowee.app` from `notarizer.sh`, wrap it in a DMG, publish a GitHub Release, and push the updated Homebrew cask formula to `thingsplode/homebrew-yowee`.

```bash
./publisher.sh
```

No environment variables required. All configuration (GitHub user, repo names, tap repo) is hardcoded at the top of the script.

### Prerequisites

- `build/yowee.app` exists and passes `xcrun stapler validate` (i.e. `notarizer.sh` completed successfully)
- `gh` CLI installed and authenticated (`gh auth login`)
- `create-dmg` installed

The script checks both tools at startup and offers to `brew install` them interactively if they are missing.

### What it does, in order

| Step | Detail |
|---|---|
| Preflight | Checks `create-dmg`, `gh`, `gh auth status`, `build/yowee.app`, `stapler validate` |
| Create DMG | `create-dmg` with drag-to-Applications layout → `build/yowee-<VERSION>.dmg` |
| SHA256 | `shasum -a 256` on the DMG — digest written into the cask formula |
| GitHub Release | `gh release create v<VERSION>` with the DMG attached; skips gracefully if the tag already exists |
| Tap update | Clones `thingsplode/homebrew-yowee` (creates the repo if it doesn't exist), writes `Casks/yowee.rb`, commits, and pushes |

### Re-running

The script is safe to re-run. If the GitHub release already exists it warns and skips that step but still updates the tap formula. If the tap formula is already at the current version it warns and skips the commit.

### Version

The version string is read from `Info.plist` (`CFBundleShortVersionString`). To ship a new version:
1. Bump `CFBundleShortVersionString` in `Info.plist`.
2. Run `notarizer.sh`.
3. Run `publisher.sh`.

---

## Recommended workflows

### Starting a new feature

```bash
./build_run.sh --fast          # confirm baseline compiles and tests pass
# ... edit code ...
./build_run.sh                 # full gate before committing
```

### Iterating on a bug fix

```bash
./build_run.sh --fast --no-launch    # tight loop: lint + tests + build
# When satisfied:
./build_run.sh --no-launch           # full gate + no distracting launch
```

### Publishing a release

```bash
# 1. Bump CFBundleShortVersionString in Info.plist
# 2. Run the full dev gate one last time
./build_run.sh --no-launch

# 3. Notarize (requires Apple credentials)
export NOTARIZE_TEAM_ID=... NOTARIZE_APPLE_ID=... NOTARIZE_PASSWORD=...
./notarizer.sh

# 4. Publish
./publisher.sh
```

### Running tests only (no build)

```bash
swift run TestRunner
```

Runs the YoweeCore test suite without Xcode. Required when you only have Command Line Tools installed (no full Xcode), or want sub-second feedback during TDD cycles.

---

## Script relationships

```
build_run.sh
  └── builds to ~/Desktop/yowee.app   (development, ad-hoc signed)

notarizer.sh
  └── builds to build/yowee.app       (release, Developer ID signed + notarized)
        │
        └── publisher.sh
              ├── build/yowee-<VERSION>.dmg
              ├── GitHub Release  (thingsplode/yowee)
              └── Homebrew tap    (thingsplode/homebrew-yowee → Casks/yowee.rb)
```

`build_run.sh` and `notarizer.sh` are fully independent — they write to different locations and use different signing identities. Never use `build_run.sh`'s output for distribution, and never use `notarizer.sh` for development.

---

## Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Keychain "Allow" dialog on every launch | API key saved under old restrictive ACL | Re-enter API key in Settings → Providers |
| Text not replaced after pipeline runs | Focus loss or AX write silently ignored | See `CLAUDE.md` — Common Regression section |
| `notarizer.sh` preflight: cert not found | Developer ID cert not in login keychain | Open Xcode → Settings → Accounts and download it |
| `notarizer.sh` notarize: Rejected | Hardened runtime or entitlements issue | Check Apple's rejection log (printed automatically) |
| `publisher.sh` tap clone fails | `homebrew-yowee` repo doesn't exist yet | Script creates it automatically via `gh repo create` |
| `build_run.sh` DVTDownloads mismatch | Xcode updated without running first launch | Script prompts to run `sudo xcodebuild -runFirstLaunch` |
