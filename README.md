# Yowee

A native macOS menu bar utility that runs LLM pipelines on selected text. Press **⌥Space** with text selected in any app — a floating menu lists your pipelines; choosing one sends the text through the pipeline and replaces it with the result.

```
Select text → ⌥Space → pick "Improve Grammar" → text is rewritten in place
```

No Electron. No browser extension. Works in every app that exposes selected text through the macOS Accessibility API.

Installation:
```bash
 brew install --cask thingsplode/yowee/yowee
```
---

## Requirements

| Tool | Version |
|---|---|
| macOS | 14 Sonoma or later |
| Xcode | 15.2 or later (for SwiftData macros) |
| Swift | 6.2 (bundled with Xcode 16+) |
| Command Line Tools | Xcode CLT — for `swift run TestRunner` |

The app requires **Accessibility permission** (to read and replace selected text). It does **not** need Input Monitoring, Microphone, or any other entitlement for Phase 1.

---

## Quick start

```bash
git clone <repo-url> yowee
cd yowee
open Package.swift          # opens in Xcode
```

In Xcode:
1. Select the **yowee** scheme (top-left dropdown).
2. Set the run destination to **My Mac**.
3. Press **⌘R** to build and run.

The yowee icon appears in your menu bar.

---

## Project structure

```
yowee/
├── Package.swift                      # SPM manifest (two targets: YoweeCore + TestRunner)
├── Info.plist                         # Bundle metadata (LSUIElement=true hides Dock icon)
├── Sources/
│   ├── YoweeCore/                      # Pure Swift library — no SwiftData/SwiftUI macros
│   │   ├── Keychain/KeychainStore.swift
│   │   ├── Models/LLMProvider.swift
│   │   └── PipelineEngine/
│   │       ├── LLMClient/             # AnthropicClient, OpenAIClient, OllamaClient
│   │       ├── LLMClientFactory.swift
│   │       ├── PipelineRunner.swift   # Swift actor; runs steps sequentially
│   │       ├── PromptRenderer.swift   # {{input}} substitution
│   │       └── StepData.swift         # Sendable value type for cross-actor passing
│   ├── yowee/                         # macOS app target (Xcode only — SwiftData macros)
│   │   ├── App/                       # YoweeApp, AppDelegate, YoweeOrchestrator
│   │   ├── Models/                    # Pipeline, PromptStep (@Model)
│   │   ├── Shortcut/                  # GlobalShortcutManager, HotKey, AccessibilityReader,
│   │   │                              #   TextReplacer, AccessibilityPermissionGuard
│   │   ├── StatusBar/                 # StatusBarController, YoweeMenu
│   │   ├── UI/                        # ConfigurationView, PipelineListView,
│   │   │                              #   PipelineEditorView, StepEditorView,
│   │   │                              #   ProviderSettingsView, ShortcutSettingsView
│   │   │   └── Components/            # LoadingHUD, ErrorBanner
│   │   ├── DefaultPipelines.swift
│   │   └── PipelineEngine/StepDataExtension.swift
│   └── TestRunner/                    # CLI test executable (see Testing section)
│       ├── main.swift
│       └── *.swift → symlinks to Tests/YoweeTests/
├── Tests/
│   └── YoweeTests/                     # Test source (also referenced by TestRunner via symlinks)
│       ├── PipelineRunnerTests.swift
│       ├── PromptRendererTests.swift
│       ├── LLMClientFactoryTests.swift
│       └── KeychainStoreTests.swift
└── spec/                              # Design documents
    ├── requirements.md
    ├── solution-design.md
    ├── architecture.md
    └── tasks.md
```

### Why two source targets?

`YoweeCore` is a plain Swift library with no macro dependencies. It compiles with `swift build` from the command line and is independently testable.

`Sources/yowee/` contains the app target. It uses `@Model` (SwiftData), `@Observable`, and other macro-based features that require Xcode's compiler plugin infrastructure. **Do not add SwiftData or SwiftUI macro imports to `YoweeCore`.**

---

## Building

### From Xcode (full app)

```bash
open Package.swift
# Select scheme "yowee" → My Mac → ⌘B
```

The build produces a `.app` bundle inside the DerivedData directory. Xcode runs it directly from there when you press ⌘R.

### build_run.sh (recommended for development)

`build_run.sh` is the all-in-one development pipeline. It lints, tests, statically analyses, builds, signs, and launches the app in one command.

```bash
./build_run.sh                # full pipeline + launch
./build_run.sh --no-launch    # full pipeline, don't open the app
./build_run.sh --fast         # skip analysis and coverage (quick iteration)
./build_run.sh --no-test      # skip unit tests
```

Flags can be combined: `./build_run.sh --fast --no-launch`

#### Pipeline steps

| Step | Tool | Skipped by |
|---|---|---|
| Preflight | `xcodebuild -version` — detects Xcode plugin mismatch, offers `sudo xcodebuild -runFirstLaunch` | — |
| Dependency check | Checks each tool below; offers `brew install` for any that are missing | — |
| Lint | SwiftLint | tool not installed |
| Format check | SwiftFormat `--lint` | tool not installed |
| Unit tests | `swift run TestRunner` | `--no-test` |
| Static analysis | `xcodebuild analyze` (Clang analyzer) | `--fast` |
| Dead code | Periphery | `--fast` or tool not installed |
| Build | `xcodebuild build` | — |
| Coverage | `xcodebuild test -enableCodeCoverage` + `xcrun xccov` | `--fast` |
| Assemble + sign | Ad-hoc codesign (keeps TCC Accessibility permission valid after rebuild) | — |
| Launch | `open yowee.app` | `--no-launch` |

#### Optional tools

The script checks these at startup and offers to install any that are missing via Homebrew:

| Tool | Purpose | Install |
|---|---|---|
| SwiftLint | Style and correctness rules | `brew install swiftlint` |
| SwiftFormat | Formatting consistency | `brew install swiftformat` |
| Periphery | Unused declaration detection | `brew install peripheryapp/periphery/periphery` |
| Ollama | Local LLM service (needed if any pipeline uses the Ollama provider) | `brew install ollama` |

#### Summary table

Every run prints a two-section summary at the end:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step                      Details
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Dependencies & services
  ────────────────────────────────────────────────────────────────────────
  Homebrew               ✓  5.1.7
  SwiftLint              ✓  0.57.0
  SwiftFormat            ?  not installed
  Periphery              ?  not installed
  Ollama                 ✓  0.20.2 — running (7 models)

  Analysis
  ────────────────────────────────────────────────────────────────────────
  SwiftLint              ✓  0 issues
  SwiftFormat            ○  not installed
  Unit tests             ✓  110 tests passed  (12 suites)
  Static analysis        ✓  0 issues
  Periphery              ○  not installed
  Build                  ✓  succeeded
  Coverage               ✓  85.2% overall  (lowest: PipelineRunner.swift 62%)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Icons: `✓` pass · `⚠` warnings · `✗` failed · `○` skipped · `?` not installed

The script exits non-zero only on hard failures (build error, test failure, static analysis error). Warnings do not block the build.

#### Exit codes

| Code | Meaning |
|---|---|
| `0` | All hard checks passed (warnings allowed) |
| `1` | Build failed, a test failed, or static analysis reported errors |

### From the command line (library only)

```bash
swift build --target YoweeCore
```

This compiles `YoweeCore` and its transitive Swift dependencies. It does not build the app UI, models, or shortcut machinery.

---

## Running the app

### From Xcode

Press **⌘R**. The app starts as a menu bar item (no Dock icon). Look for the ●● icon in the top-right of your menu bar.

### From a built `.app`

After an Archive build or direct build, find the app in DerivedData:

```bash
# Find the most recent build
find ~/Library/Developer/Xcode/DerivedData -name "yowee.app" -maxdepth 6 | head -1
```

Copy it to `/Applications` and open it:

```bash
cp -R /path/to/yowee.app /Applications/
open /Applications/yowee.app
```

### Grant Accessibility permission (required)

On first launch, yowee shows an onboarding prompt. Click **Open System Settings** and enable the toggle next to Yowee under:

> System Settings → Privacy & Security → Accessibility

If the prompt does not appear, open System Settings manually and add Yowee to the list. Without this permission, ⌥Space will show an error rather than reading the selected text.

---

## First run

After launching and granting Accessibility permission, four pipelines are seeded automatically:

| Pipeline | What it does |
|---|---|
| **Improve Grammar** | Corrects grammar and clarity |
| **Make Concise** | Shortens and tightens the text |
| **Translate to English** | Translates from any language |
| **Professional Tone** | Rewrites in a formal business style |

All four default pipelines use **Anthropic** (`claude-sonnet-4-6`). To use them you need to add your Anthropic API key:

1. Click the ●● menu bar icon → **Configure yowee…**
2. Navigate to **Providers** in the sidebar.
3. Paste your API key in the Anthropic field. It is saved to the system Keychain immediately.

---

## Configuring pipelines

Open **Configure yowee…** from the menu bar.

### Add a pipeline

1. Click **+** in the Pipelines sidebar.
2. Give it a name.
3. Click **+** in the step list to add a step.
4. Choose a provider and model, then write a user template. The template **must** contain `{{input}}` — that placeholder is replaced with the selected text (or the previous step's output in a multi-step pipeline).
5. Optionally add a system prompt.

### Multi-step pipelines

Add multiple steps. Each step receives the previous step's output as `{{input}}`. Example two-step pipeline:

```
Step 1 template:  Translate the following to English: {{input}}
Step 2 template:  Improve the grammar and clarity: {{input}}
```

### Change the trigger shortcut

In **Configure yowee… → Shortcuts**, click the shortcut button and press your desired key combination. The default is **⌥Space**. The new binding takes effect immediately and persists across restarts.

---

## API keys and Ollama

| Provider | Where to get a key |
|---|---|
| Anthropic | console.anthropic.com |
| OpenAI | platform.openai.com |
| Ollama | No key needed — runs locally |
| Tavily | app.tavily.com (required for Research steps) |

For Ollama, the default base URL is `http://localhost:11434`. Change it in Providers settings if you run Ollama on a different host or port.

### Tavily API key (Web Search / Research steps)

Tavily is used by **Research** pipeline steps to search the web and fetch page content. It is only needed if you add a Research step to a pipeline.

1. Go to [app.tavily.com](https://app.tavily.com) and create a free account.
2. Your API key is displayed on the dashboard — it starts with `tvly-`.
3. In **Configure yowee… → Providers**, paste the key in the **Tavily (Web Search)** field and click **Save Tavily Key**.

The free tier includes **1 000 searches per month**, which is sufficient for personal use. The key is stored in the macOS Keychain and never written to disk.

---

## Testing

Command Line Tools ship without `swiftpm_testing_helper`, so `swift test` builds but does not run tests. Use the `TestRunner` executable instead:

```bash
swift run TestRunner
```

Expected output:

```
Test run started.
Suite PipelineRunnerTests started.
Suite PromptRendererTests started.
Suite KeychainStoreTests started.
Suite LLMClientFactoryTests started.
...
Test run with 16 tests in 4 suites passed after 0.067 seconds.
```

From Xcode, `⌘U` runs the `YoweeTests` test target normally.

### Integration tests (real API calls)

Real API calls are gated and off by default:

```bash
YOWEE_INTEGRATION_TESTS=1 swift run TestRunner
```

This requires `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and a running Ollama instance to be in the environment.

---

## Architecture notes

### Global shortcut

The hotkey is registered with Carbon's `RegisterEventHotKey`. This API does **not** require Accessibility or Input Monitoring permission. The `KeyboardShortcuts` SPM package was evaluated but rejected because its recorder UI uses the `#Preview` macro, which fails in CLI builds.

### Concurrency model

- `PipelineRunner` is a Swift `actor` — LLM calls are serialised within a pipeline but the actor is non-blocking to the main thread.
- All AX reads/writes and UI calls are `@MainActor`.
- `StepData` is a `Sendable` value type. `@Model` objects (Pipeline, PromptStep) never cross actor boundaries — their `UUID` is passed and re-fetched instead.

### Text replacement

`TextReplacer` tries `AXUIElementSetAttributeValue(kAXSelectedTextAttribute)` first. If the AX write is rejected (common in some Electron apps), it writes to the pasteboard and simulates **⌘V** via `CGEvent`.

### Persistence

- **Pipelines / steps** — SwiftData with `VersionedSchema`. Increment the schema version for any model change.
- **API keys** — Keychain only (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Never UserDefaults, never files.
- **Shortcut binding** — `UserDefaults` (Carbon key code + modifier mask).

---

## Adding a new LLM provider

1. Add a case to `LLMProvider` in `Sources/YoweeCore/Models/LLMProvider.swift`.
2. Implement `LLMClient` in `Sources/YoweeCore/PipelineEngine/LLMClient/`.
3. Add a case to `LLMClientFactory.client(for:)`.
4. Add a text field for the API key in `ProviderSettingsView`.
5. Add a test case to `LLMClientFactoryTests`.

---

## Installation

```bash
brew tap thingsplode/yowee
brew install --cask yowee
```

Grant Accessibility permission on first launch (System Settings → Privacy & Security → Accessibility).

---

## Distribution

Releases are built, notarized, and published using two scripts:

| Script | Purpose |
|---|---|
| `notarizer.sh` | Builds a Release binary, assembles the `.app`, signs with Developer ID, notarizes with Apple, and staples the ticket |
| `publisher.sh` | Wraps the stapled app in a DMG, publishes a GitHub Release, and updates the Homebrew tap formula |

### Release workflow

```bash
# 1. Set notarization credentials
export NOTARIZE_TEAM_ID="XXXXXXXXXX"
export NOTARIZE_APPLE_ID="you@example.com"
export NOTARIZE_PASSWORD="xxxx-xxxx-xxxx-xxxx"

# 2. Build, sign, notarize, and staple
./notarizer.sh

# 3. Package as DMG, publish GitHub Release, update tap
./publisher.sh
```

`publisher.sh` checks for required tools (`create-dmg`, `gh`) at startup and offers to install them via Homebrew if they are missing.

### Code signing

The app must be signed with a **Developer ID Application** certificate (not App Store). It is distributed as a notarized DMG. The App Store sandbox is incompatible with `AXUIElement` — the app is intentionally non-sandboxed.
