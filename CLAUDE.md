# Yowee — Claude Context

## TDD Workflow (mandatory for new features)

Any feature implementation that adds new behavior must follow the red → green cycle using the `/tdd` skill. The TDD agent owns the acceptance criteria and test files. The main agent owns the implementation.

### When to invoke `/tdd write <feature>`

Invoke before writing any implementation code when:
- Implementing a task marked `[ ]` in `spec/tasks.md`
- Adding a new type, actor, or protocol to `YoweeCore`
- Implementing a new Phase (Phase 3 Notepad or beyond)
- Adding a new LLM provider client
- Changing the `PipelineRunner` execution model or `TextReplacer` strategy

Do **not** invoke for: bug fixes to existing behavior, refactors with no observable behavior change, config or tooling changes.

### Mandatory workflow

1. **Before implementation**: call `/tdd write <feature>`. Do not write a single line of feature code until the TDD agent reports the red phase is complete (failing tests + contract written).
2. **During implementation**: implement only what is needed to make the contracted tests pass. Do not add untested behavior.
3. **After implementation**: call `/tdd verify <feature>`. Do not report work as done until the TDD agent confirms all acceptance criteria pass.
4. **If a test is in the way**: call `/tdd review` and present the proposed change. Do not modify a test file unilaterally. If the TDD agent rejects the change, fix the implementation instead.

### Protected test files

Any test file whose first line is `// TDD-CONTRACT: …` is owned by the TDD agent. The main agent must **never** edit such a file without an explicit `/tdd review` approval recorded in `.claude/tdd-contracts/`. Violating this rule invalidates the acceptance criteria for that feature.

### Contract files

The TDD agent writes contracts to `.claude/tdd-contracts/<feature-slug>.md`. Each contract lists:
- Acceptance criteria (AC-xx) with spec traceability (FR-xx / NFR-xx)
- Which test functions cover which criteria
- Current status (`failing` → `passing` after `/tdd verify`)

These contracts are the authoritative definition of "done" for each feature.

---

## Code Quality Skill

After completing any significant change — a new feature, a refactor spanning multiple files, a new actor or protocol, new UI views, or changes to the pipeline engine — invoke `/swift-analyze` before reporting the work as done.

Significant changes include (non-exhaustive):
- Adding or removing a file in `Sources/`
- Restructuring actor isolation or `@MainActor` boundaries
- Changing a public API (protocol, initializer signature, published property)
- Adding a new SwiftUI view or AppKit panel
- Any change to `PipelineRunner`, `LLMClient`, or `TextReplacer`

Small, targeted fixes (single-line typo, comment update, config tweak) do not require a lint pass.

## What This Project Is

**Yowee** is a native macOS menu bar utility (⌥Space trigger) that reads selected text from any app via AXUIElement, runs it through a user-configured LLM pipeline, and replaces the selection with the result. Future phases: Phase 2 — voice transcription (Whisper), Phase 3 — Markdown notepad.

## Project Phases

| Phase | Status | Scope |
|---|---|---|
| 1 — Core | Complete | Global hotkey, pipeline engine, SwiftUI config, 4 default pipelines |
| 2 — Voice | Complete | AVFoundation → WhisperKit (⌥R/⌥S), VoiceRecordingPanel, Cmd+V insertion |
| 3 — Notepad | Planned | TextKit 2 Markdown editor + pipeline integration |

Specs: `spec/requirements.md`, `spec/solution-design.md`, `spec/architecture.md`, `spec/tasks.md`

## Tech Stack

| Concern | Technology |
|---|---|
| Language | Swift 6, strict concurrency |
| UI | SwiftUI (config) + AppKit (menu bar, menus, panels) |
| Persistence | `@Observable final class` + JSON (`~/.config/yowee/`) |
| Secrets | Security.framework Keychain only |
| Global shortcut | Carbon `RegisterEventHotKey` (no Accessibility needed) |
| Text read/write | AXUIElement + CGEvent fallback (Cmd+V) |
| LLM APIs | URLSession async/await — Anthropic, OpenAI, Ollama |
| Voice (Ph 2) | WhisperKit (CoreML/ANE) + AVFoundation |
| Markdown (Ph 3) | Ink + TextKit 2 |

## Architecture Principles

- **No sandbox** — Accessibility (AXUIElement) is incompatible with App Store sandbox. Distribute as notarized DMG / Homebrew cask.
- **Actor isolation** — `PipelineRunner` is a Swift actor; all AX/UI code is `@MainActor`.
- **Protocol-based LLM clients** — all providers implement `LLMClient`. Never call provider APIs directly from `PipelineRunner`.
- **Keychain only for secrets** — `KeychainStore` is the only read/write point for API keys; never UserDefaults or files.
- **Non-destructive on failure** — original text is never modified if any pipeline step throws.
- **URLSession injection** — LLM clients accept `session: URLSession = .shared`; tests inject a `MockURLProtocol`-backed session.

## Key Files

```
Sources/
  YoweeCore/                        # Pure-logic library — testable without Xcode
    Keychain/KeychainStore.swift
    Models/LLMProvider.swift
    PipelineEngine/
      PipelineRunner.swift         # Swift actor
      PromptRenderer.swift
      StepData.swift               # Sendable value type (crosses actor boundary)
      LLMClient/
        LLMClientProtocol.swift
        LLMClientFactory.swift
        AnthropicClient.swift
        OpenAIClient.swift         # also exposes fetchModels() → GET /v1/models
        OllamaClient.swift
  yowee/                           # macOS app — requires Xcode (AppKit/SwiftUI)
    App/{YoweeApp,AppDelegate,AppLogger,YoweeOrchestrator}.swift
    StatusBar/{StatusBarController,YoweeMenu}.swift
    Shortcut/{GlobalShortcutManager,AccessibilityReader,TextReplacer,HotKey}.swift
    Models/{Pipeline,PromptStep}.swift
    Store/{PipelineStore,ShortcutStore}.swift
    UI/{ConfigurationView,PipelineListView,PipelineEditorView,StepEditorView,
        ProviderSettingsView,ShortcutSettingsView,LogView}.swift
    UI/Components/{ErrorBanner,LoadingHUD,FloatingPanelSupport}.swift
    VoiceInput/{VoiceSessionState,VoiceInputCoordinator,AudioRecorder,
                WhisperTranscriber,VoiceRecordingPanel,VoiceRecordingView}.swift
Tests/YoweeTests/                   # Symlinked into Sources/TestRunner/
Sources/TestRunner/                # `swift run TestRunner` — no Xcode needed
build_run.sh                       # xcodebuild + sign + launch
```

## Swift 6 / Concurrency Patterns

```swift
// Actors for shared mutable state
actor PipelineRunner {
    func run(steps: [StepData], input: String) async throws -> String { ... }
}

// Structured concurrency — no DispatchQueue.async, no callbacks
Task {
    let result = try await runner.run(steps: steps, input: text)
    await MainActor.run { textReplacer.replace(in: element, range: range, with: result) }
}

// @MainActor for everything that touches UI or AX APIs
@MainActor func handleTrigger() { ... }

// Pass only Sendable value types across actor boundaries (never @Observable class instances)
struct StepData: Sendable { let userTemplate: String; let provider: LLMProvider; ... }
// Snapshot @Observable objects into Sendable structs (StepData) before crossing actor boundaries

// URLSession async — no completion handlers
let (data, response) = try await session.data(for: request)
```

## macOS Accessibility Patterns

```swift
// Read selected text + range (capture range BEFORE Yowee steals focus)
let systemWide = AXUIElementCreateSystemWide()
var ref: CFTypeRef?
AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &ref)
let element = ref as! AXUIElement
// Read kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute

// Write replacement — full sequence required for reliable replacement:
// 1. Restore original app focus (.activateIgnoringOtherApps is required; plain [] is too weak)
originalApp?.activate(options: [.activateIgnoringOtherApps])
// 2. Wait for the app to become key so its text field accepts AX writes
try? await Task.sleep(nanoseconds: 300_000_000)  // 300 ms
// 3. Re-focus the element (it defocused when Yowee's menu stole keyboard focus)
AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
// 4. Restore the original selection range
var mutableRange = range
if let axRange = AXValueCreate(.cfRange, &mutableRange) {
    AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
}
// 5. Snapshot selected text BEFORE write (used to detect silent ignores, e.g. Notes)
var beforeRef: CFTypeRef?
AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &beforeRef)
let textBefore = beforeRef as? String
// 6. AX write
let axResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
// 7. Verify by comparing before vs after (NOT by comparing to replacement text —
//    selection ALWAYS collapses after a write, so textAfter will be "" not text)
var afterRef: CFTypeRef?
AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &afterRef)
let textAfter = afterRef as? String
if axResult == .success && textAfter != textBefore {
    return  // write verified — selection changed (collapsed to "")
}
pasteViaCmdV(text)  // fallback: CGEvent Cmd+V via .cgSessionEventTap

// Permission — prompt with system dialog; auto-adds current binary to TCC
let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
AXIsProcessTrustedWithOptions(opts)
// Re-sign after each rebuild so TCC hash stays valid:
// codesign --force --deep --sign - yowee.app
```

## AppKit + @MainActor Bridging

AppKit calls `performSelector:` via the ObjC runtime; if the target is `@MainActor`-isolated, the call may be swallowed silently. Fix: use a plain `NSObject` subclass as the menu item target.

```swift
// MenuItemProxy in StatusBarController.swift — bridges ObjC dispatch to a Swift closure
final class MenuItemProxy: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action; super.init() }
    @objc func fire(_ sender: Any?) { action() }
}

// In buildMenu():
let proxy = MenuItemProxy { [weak self] in Task { @MainActor in self?.openSettings() } }
configProxy = proxy  // retain via property — menu item does not retain its target
let item = NSMenuItem(title: "Configure yowee…", action: #selector(MenuItemProxy.fire(_:)), keyEquivalent: ",")
item.target = proxy
```

## Settings Window Conventions

```swift
// Full pattern for a manually-managed settings window in a menu-bar app:
let window = NSWindow(contentViewController: hostVC)
window.isReleasedWhenClosed = false        // don't deallocate on close
window.collectionBehavior = [.moveToActiveSpace]  // always appear on current Space

// Activation order matters — show window FIRST, then change policy:
settingsWindowController?.showWindow(nil)
settingsWindowController?.window?.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
DispatchQueue.main.async {
    NSApp.setActivationPolicy(.regular)    // deferred so window ordering isn't reset
}

// Restore on close:
@objc private func settingsWindowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
}
```

- `window.collectionBehavior = [.moveToActiveSpace]` is required — without it, `makeKeyAndOrderFront` brings the window to front on whatever Space it was last on, not the user's current Space.
- `setActivationPolicy(.regular)` must be deferred via `DispatchQueue.main.async`; calling it before presentation resets window ordering and hides the window behind other apps.

## Persistence Conventions (@Observable + JSON)

SwiftData is **not used** — `@Model` macro requires Xcode's compiler plugin infrastructure and breaks `swift build` / `swift run TestRunner`. Models use `@Observable final class` for reactive SwiftUI binding, with JSON files for persistence.

- `Pipeline` and `PromptStep` are `@Observable final class`; mutations on `@MainActor`.
- `PipelineStore` saves to `~/.config/yowee/pipelines.json` via private `PipelineRecord`/`StepRecord` DTOs.
- `PipelineRecord.version` field (Int, defaults to `0` for legacy files) gates future migrations.
- `PipelineStore.storageVersion = 1`; bump and add a migration block in `load()` for any schema change.
- Never pass `@Observable` class instances across actor boundaries — snapshot to `StepData` (Sendable) first.
- Call `store.save()` explicitly in `applicationWillTerminate` (no scene lifecycle to trigger auto-save).
- `restoreDefaults()` is additive — re-adds missing default pipelines without touching custom ones.

## Keychain Conventions

```swift
// Always save with an open-access ACL so items remain readable across ad-hoc rebuilds.
// Ad-hoc signing (codesign --sign -) changes the code identity each build; without an
// explicit ACL, macOS silently blocks reads from the new identity.
var access: SecAccess?
SecAccessCreate("Yowee \(key)" as CFString, nil, &access)  // nil = all apps trusted
var query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: key,
    kSecAttrService as String: "yowee",
    kSecValueData as String: data,
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
]
if let access { query[kSecAttrAccess as String] = access }
SecItemDelete(query as CFDictionary)
SecItemAdd(query as CFDictionary, nil)
```

- After changing the open-access pattern, existing items (saved under the old restrictive ACL) must be re-saved. Prompt the user to re-enter their API key once.
- Never log full API keys — log only `"sk-\(key.prefix(4))…"`.

## LLM Client Conventions

- Protocol: `complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String`
- Default `maxTokens`: 4096. Timeout: 30 s on `URLRequest`.
- HTTP 4xx/5xx → throw `LLMError.apiError(statusCode:body:)`. Always include the full response body in the thrown error; never discard it silently.
- **OpenAI**: use `max_completion_tokens`, NOT `max_tokens` — the latter is deprecated and rejected with 400 by GPT-5 and reasoning models (o1, o3, o4).
- Each client accepts `session: URLSession = .shared` for test injection.

### OpenAI dynamic model list

`OpenAIClient.fetchModels()` calls `GET /v1/models` and filters to chat-capable models:

```swift
// Filter: exclude embeddings, image, audio, legacy completion models
let exclude = ["text-embedding", "dall-e", "whisper", "tts-", "babbage", "davinci", "curie", "ada", "text-moderation"]
let include = ["gpt-", "o1", "o2", "o3", "o4", "o5", "chatgpt-"]
```

`StepEditorView` calls `fetchModels()` via `.task(id: step.provider)` when provider is `.openai` and an API key exists, falling back to `LLMProvider.openai.defaultModels` while loading or on error. Always insert the current `step.modelID` at the top of the picker list if it's not in the fetched list (backwards compat).

### Current default model IDs

| Provider | Default | Full static list |
|---|---|---|
| Anthropic | `claude-sonnet-4-6` | `claude-sonnet-4-6`, `claude-opus-4-7`, `claude-haiku-4-5-20251001` |
| OpenAI | `gpt-5` (static fallback) | `gpt-5`, `gpt-5-mini`, `gpt-5.4`, `gpt-4o`, `gpt-4o-mini`, `o4-mini`, `o3`, `o3-mini`, `o1`, `gpt-4-turbo` |
| Ollama | `llama3.2` | `llama3.2`, `mistral`, `codellama` |

OpenAI model IDs change rapidly — always prefer the live list from `fetchModels()` over the static fallback.

## UI / ErrorBanner Conventions

```swift
// WRONG — cursorPoint captured before async LLM call; mouse has moved by the time error fires
let cursorPoint = NSEvent.mouseLocation
Task {
    do { ... }
    catch { ErrorBanner.show(message: ..., near: cursorPoint) }  // ← stale position
}

// CORRECT — use current mouse position at show-time (default parameter)
catch { ErrorBanner.show(message: error.localizedDescription) }
```

- `ErrorBanner` uses `NSEvent.mouseLocation` as the default `near:` parameter, which evaluates at the call site — always pass no `near:` argument from async error handlers.
- The panel has `ignoresMouseEvents = false` to allow the ✕ close button to work.
- Dismiss after 4 seconds or on close button tap.

## Common Regression: Text Not Being Replaced

Two independent root causes; both must be present for replacement to work.

**Root cause 1 — API key unavailable (Keychain not warmed up)**

Keychain items saved with the old restrictive ACL (before open-access fix) are bound to the creating app's code identity. After a rebuild with a new ad-hoc signature, `KeychainStore.load` returns `nil`, `LLMClientFactory` falls back to `""`, and the provider returns 401. The pipeline errors before `TextReplacer.replace` is ever called.

Fix: `AppDelegate.applicationDidFinishLaunching` calls `warmUpKeychain()`, which reads each provider's Keychain slot at startup. This fires any system authorization dialog once, at launch, rather than mid-pipeline when a nil result would be silently swallowed.

```swift
private func warmUpKeychain() {
    for provider in LLMProvider.allCases where provider.requiresAPIKey {
        _ = KeychainStore.load(for: provider.keychainKey)
    }
}
```

If warm-up shows an "Allow" dialog, it means the item was saved under the old restrictive ACL. The user must re-save the key in Settings → Providers to write it with the open-access ACL.

**Root cause 2 — Focus loss + AX write verify logic (frequent regression)**

After Yowee's menu steals keyboard focus, the original text element is defocused. Three preconditions must be met before the AX write, in order:

1. **Re-activate original app** with `activate(options: [.activateIgnoringOtherApps])` — plain `activate(options: [])` is too weak; the target app may not regain keyboard focus in time.
2. **Wait 300 ms** (`Task.sleep(nanoseconds: 300_000_000)`) — the app needs time to become key so its text field accepts AX writes.
3. **Set `kAXFocusedAttribute`** on the element to `true` — explicitly refocuses the field that was defocused during menu interaction.

Then the correct verify pattern compares selected text *before* vs *after* the write:

```swift
// Re-focus element BEFORE range restore and write
AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)

// Restore original selection range
var mutableRange = range
if let axRange = AXValueCreate(.cfRange, &mutableRange) {
    AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
}

// Snapshot before write
var beforeRef: CFTypeRef?
AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &beforeRef)
let textBefore = beforeRef as? String

let axResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)

// Read after — if changed (even to ""), the write landed
var afterRef: CFTypeRef?
AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &afterRef)
let textAfter = afterRef as? String

if axResult == .success && textAfter != textBefore {
    return  // write verified — selection collapsed
}
pasteViaCmdV(text)  // fallback: AX write silently ignored
```

Three cases this must handle:
- **Normal apps** (TextEdit, Safari, etc.): AX write replaces text → selection collapses → `textAfter = ""` ≠ `textBefore = originalText` → verified ✓
- **Notes**: returns `kAXErrorSuccess` (0) but silently ignores the write → `textAfter = textBefore = originalText` → Cmd+V fallback ✓
- **Apps rejecting AX**: `axResult != .success` → Cmd+V fallback ✓

**Never** verify by `textAfter == replacementText` — selection is always collapsed after a write so this is always false, causing double-insertion.
**Never** trust `axResult == .success` alone — Notes lies.
**Never** use `activate(options: [])` — it does not reliably restore keyboard focus after a menu interaction.

**Root cause 3 — ErrorBanner not visible in accessory activation mode**

Two sub-issues, both required:

- `p.orderFront(nil)` respects the application's activation state. When yowee runs as `.accessory` (no Dock icon, no active window), the floating panel may not surface above other apps' windows. Fix: always use `p.orderFrontRegardless()`.
- `p.level = .floating` (3) may still be below some app windows. Fix: use `p.level = .popUpMenu` (101) to ensure the banner appears above all normal and floating windows of the frontmost app.
- `.regularMaterial` (NSVisualEffectView) requires an active/key window to render its blur; a non-activating floating panel shown via `orderFrontRegardless()` does not qualify. Fix: use a solid `Color(nsColor: .windowBackgroundColor)` fill instead of a material.

## LogView

`LogView` (tab in `ConfigurationView`) tails `/tmp/yowee_debug.log` — the same file both `YoweeOrchestrator` and `StatusBarController` write to. It polls every 1.5 s, auto-scrolls to the bottom, and provides Clear/Refresh buttons. Use the Log tab as the first debugging tool when investigating runtime errors.

## Testing Conventions

**Run tests**: `swift run TestRunner` (no Xcode needed — YoweeCore only).

```
Tests/YoweeTests/               ← single source of truth
  MockURLProtocol.swift        ← per-session URLProtocol mock (thread-safe, concurrent-safe)
  AnthropicClientTests.swift   ← HTTP request construction + response parsing + errors
  OpenAIClientTests.swift
  OllamaClientTests.swift
  LLMProviderTests.swift       ← displayName, keychainKey, defaultModels, requiresAPIKey
  LLMErrorTests.swift          ← all errorDescription cases
  PromptRendererTests.swift    ← replacement, multiple placeholders, missing placeholder
  PromptRendererEdgeCaseTests  ← edge cases: empty input, unicode, very long, nested placeholder
  PipelineRunnerTests.swift    ← single/multi-step, empty, error propagation
  PipelineRunnerEdgeCaseTests  ← invalid template, system prompt, model routing, chaining
  KeychainStoreTests.swift     ← save/load/delete/overwrite
  LLMClientFactoryTests.swift  ← provider→client routing
  MenuItemProxyTests.swift     ← ObjC dispatch mechanism
```

**MockURLProtocol** — handlers stored per-session (UUID in `httpAdditionalHeaders`); safe for concurrent tests:
```swift
// In test:
let client = AnthropicClient(apiKey: "k", session: MockURLProtocol.makeSession { request in
    // Inspect request, return (HTTPURLResponse, Data)
})
// Or convenience:
let client = AnthropicClient(apiKey: "k", session: MockURLProtocol.makeSession(json: "{...}", statusCode: 200))
```

**URLSession body stream**: URLSession promotes `httpBody` to `httpBodyStream` when passing to URLProtocol. `decodedJSONBody()` in tests must read from `httpBodyStream`, not `httpBody`.

- Integration tests gated behind `YOWEE_INTEGRATION_TESTS=1` env var.
- `GlobalShortcutManager` and `AccessibilityReader` require UI test targets on real hardware.

## Swift Best Practices (enforced in this codebase)

**Naming**
- Types: nouns (`PipelineRunner`, `StepData`). Functions: verb phrases (`fetchPipelines`, `replace(in:range:with:)`).
- One primary type per file, file named after that type.
- No abbreviations except well-known ones (URL, AX, HUD, LLM).

**Types & ownership**
- Default to `struct` (value semantics). Use `class` only when reference semantics or `NSObject` inheritance is required.
- Prefer `enum` for namespaced static functions over `struct` with all-static members.
- `final` on all classes unless subclassing is intentional.

**Error handling**
- Throw specific typed errors (`LLMError`, `PromptRendererError`) — never `Error` or `NSError` directly.
- Catch at boundaries (e.g. `handleTrigger`, `run(steps:input:)`), not inside helpers.
- No silent `try?` swallowing on paths where failure matters; use it only for cleanup (e.g. `try? fh.close()`).
- Always include the full API response body when surfacing HTTP errors — never discard it.

**Optionals**
- `guard let` at function entry for required values; `if let` for optional paths inside.
- No `!` force-unwrap except on values that are provably non-nil by construction (document why).

**Comments**
- Write comments only when the WHY is non-obvious: a subtle invariant, a workaround for a specific bug, or a constraint not visible in the code.
- No file headers, no inline restating of what the code does.

**Dependency injection**
- Inject external dependencies (URLSession, LLM client factory) via initializer parameters with sensible defaults.
- Never reach into globals (UserDefaults, Keychain, URLSession.shared) inside pure-logic functions — only in factories and entry points.

**AppKit integration**
- Every class that is the target of an AppKit selector or notification must inherit `NSObject`.
- For `@MainActor` classes, use `MenuItemProxy` pattern to decouple ObjC dispatch from Swift actor isolation.
- Always set `window.isReleasedWhenClosed = false` when managing window lifecycle manually.
- Always set `window.collectionBehavior = [.moveToActiveSpace]` on any manually-managed window that should appear on the user's current Space.

## Distribution

- Code-signed: Developer ID (not App Store). Notarized with `xcrun notarytool`.
- Distributed as DMG + Homebrew cask.
- Build: `./build_run.sh` — lint → unit tests → xcodebuild → assemble `.app` → ad-hoc sign → launch.
- **GitLeaks pre-commit hook** (`brew install gitleaks`) blocks any commit containing a secret. Hook lives in `.githooks/pre-commit` (version-controlled). Activated via `git config core.hooksPath .githooks` — done automatically by `./build_run.sh`. API keys belong in the Keychain only; never in source files or config.
- **Must re-sign after every rebuild** (`codesign --force --deep --sign -`) so TCC accessibility permission stays valid.
- After each rebuild the app has a new ad-hoc identity. Keychain items saved with the old open-access ACL pattern are still readable; items saved without it (old builds) require the user to re-enter their API key once.
