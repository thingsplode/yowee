# Yowee — Implementation Task Checklist

Legend: `[ ]` = todo · `[x]` = done · `[~]` = done with deviation · AC = Acceptance Criteria

---

## Phase 1 — Core (Keyboard Shortcut Pipeline Engine)

### M1: Project Scaffold
- [x] **T-01** Create project scaffold (macOS App, SwiftUI, SwiftData, minimum deployment macOS 14)
  - AC: Project builds clean; `YoweeApp.swift` is the `@main` entry point.
  - *Note: SPM package opened as an Xcode project (`open Package.swift`); no separate `.xcodeproj`.*
- [~] **T-02** Register `⌥Space` as the default global hotkey; log callback to console
  - AC: Pressing `⌥Space` in any app prints "yowee triggered" to console with Accessibility granted.
  - *Deviation: `KeyboardShortcuts` SPM package rejected — its `Recorder.swift` uses `#Preview` macro unavailable in CLI builds. Replaced with a custom Carbon `RegisterEventHotKey` implementation (`GlobalShortcutManager` + `HotKey`). Fully functional; user-configurable via `ShortcutSettingsView`.*
- [~] **T-03** Set up SwiftData stack with `Pipeline` and `PromptStep` models and V1 schema
  - AC: Unit test creates, persists, and fetches a Pipeline with two steps.
  - *Deviation: SwiftData not used — `@Model` macro requires Xcode's compiler plugin infrastructure and breaks `swift build` / `swift run TestRunner`. Implemented as `@Observable final class` with JSON persistence to `~/.config/yowee/pipelines.json` via private `PipelineRecord`/`StepRecord` DTOs. `PipelineRecord.version` field handles future migrations. Persistence verified via `PipelineStore` round-trip.*
- [x] **T-04** Add `KeychainStore` with read/write/delete for string secrets keyed by provider
  - AC: Unit test round-trips an API key through Keychain without storing it on disk.

### M2: Menu Bar App Shell
- [x] **T-05** Implement `StatusBarController` with NSStatusItem and a static NSMenu
  - AC: yowee icon appears in menu bar; menu shows "Configure yowee…" and "Quit".
- [x] **T-06** Implement `YoweeMenu` that builds the dynamic pipeline sub-menu from SwiftData
  - AC: Adding a Pipeline in SwiftData causes it to appear in the menu bar menu on next open.
- [~] **T-07** Seed default pipelines (Improve Grammar, Make Concise, Translate to English, Professional Tone) on first launch
  - AC: Fresh install shows 4 pipelines in menu; re-launch does not duplicate them.
  - *Deviation: Initial implementation seeded only 1 default pipeline. Corrected during refactoring — `PipelineStore.makeDefaultPipelines()` now returns all 4. `restoreDefaults()` is additive (re-adds any missing defaults without touching custom pipelines).*

### M3: Global Shortcut + Accessibility
- [x] **T-08** Implement `GlobalShortcutManager`: register/update the yowee trigger shortcut; expose `onTrigger` callback
  - AC: Changing the shortcut in settings takes effect immediately without restarting the app.
  - *Implemented with Carbon `RegisterEventHotKey`; shortcut persists to `UserDefaults`.*
- [x] **T-09** Implement `AccessibilityReader.selectedText()`: use `AXUIElementCreateSystemWide` to find the focused element and return `kAXSelectedTextAttribute`, or nil
  - AC: Pressing `⌥Space` with text selected in TextEdit logs the selected string; with no selection logs nil.
- [x] **T-10** On trigger with selected text: show `YoweeMenu` near cursor; on trigger with no selection: show `ErrorBanner`
  - AC: Pressing `⌥Space` over selected text in any AppKit or Electron app shows the yowee pipeline menu; native right-click menu is completely unaffected.
- [x] **T-11** Implement `AccessibilityPermissionGuard`: detect missing Accessibility permission; show onboarding with deep link to System Settings
  - AC: App launched without Accessibility permission shows onboarding; button opens correct System Settings pane.

### M4: LLM Client Layer
- [x] **T-12** Define `LLMClient` protocol and implement `AnthropicClient` (Messages API, non-streaming)
  - AC: Unit test verifies correct client type returned; integration test (gated behind `YOWEE_INTEGRATION_TESTS=1`) sends a prompt and receives a response.
- [x] **T-13** Implement `OpenAIClient` (Chat Completions API)
  - AC: Same client factory test passes; configurable base URL supports OpenAI-compatible endpoints.
- [x] **T-14** Implement `OllamaClient` (local endpoint, configurable base URL)
  - AC: Integration test against a local Ollama instance returns a response.
- [x] **T-15** Implement `LLMClientFactory`: given a `LLMProvider`, return the correct client with API key from Keychain
  - AC: Unit test verifies correct client type is returned for each provider enum case. ✓ (`swift run TestRunner`)

### M5: Pipeline Runner
- [x] **T-16** Implement `PromptRenderer.render(template:input:)` — replaces `{{input}}`; throws `missingPlaceholder` if absent
  - AC: 4 unit tests cover normal case, missing placeholder, multiple occurrences, whitespace preservation. ✓
- [x] **T-17** Implement `PipelineRunner` actor with `run(steps:input:) async throws -> String`
  - AC: Integration test with 2-step pipeline (mock LLM) passes output of step 1 as input to step 2. ✓
- [x] **T-18** Wire pipeline selection in `YoweeMenu` → `PipelineRunner.run` → `TextReplacer`
  - AC: Selecting "Improve Grammar" on selected text in TextEdit replaces the text with the LLM response.

### M6: Text Replacement
- [x] **T-19** Implement `TextReplacer`: AX write primary path; Cmd+V paste fallback
  - AC: Text replacement works in TextEdit (AX path) and Electron apps (paste path).
- [x] **T-20** Implement `LoadingHUD`: small overlay near cursor during pipeline execution; auto-dismissed on completion or error
  - AC: HUD appears within 50ms of pipeline start and disappears on completion.
- [x] **T-21** Implement `ErrorBanner`: non-blocking error notification on pipeline failure; original text unchanged
  - AC: Triggering a 401 API error shows an error notification; source text is not modified.

### M7: Configuration UI
- [x] **T-22** Implement `ConfigurationView` root (sidebar: Pipelines, Providers, Shortcuts)
  - AC: "Configure yowee…" menu item opens a SwiftUI window with sidebar navigation showing all three sections.
- [x] **T-23** Implement `PipelineListView`: list pipelines, add/delete/reorder, navigate to editor
  - AC: User can create, reorder, and delete pipelines.
- [x] **T-24** Implement `PipelineEditorView` + `StepEditorView`: edit name, add/remove/reorder steps, set system prompt, user template, provider, model
  - AC: Saving a pipeline with one step immediately reflects in the menu bar menu.
- [x] **T-25** Implement `ProviderSettingsView`: text fields for API keys; save to Keychain on change
  - AC: Entering an API key and reopening settings shows the key (masked); key survives app restart.
- [x] **T-26** Add input validation: pipeline must have a name; each step template must contain `{{input}}`; model field non-empty
  - AC: Attempting to save an invalid pipeline shows inline error; save button is disabled.
- [x] **T-26b** Implement `ShortcutSettingsView`: custom recorder button for the yowee trigger shortcut; display current binding; allow reset to `⌥Space`
  - AC: User can rebind the yowee trigger; new binding takes effect immediately and persists.

### M8: Quality & Distribution
- [~] **T-27** Write test suite covering pipeline engine with mock LLM clients
  - AC: 110 tests across 12 suites pass (`swift run TestRunner`).
  - *Deviation: `swiftpm_testing_helper` is absent from Command Line Tools, so `swift test` can build but not run. Tests use a `TestRunner` executable target that calls `Testing.__swiftPMEntryPoint()` directly. `xcodebuild test` works normally from Xcode. Test count grew from the original 16 to 110 across 12 suites as coverage was expanded to all LLM clients, pipeline engine edge cases, prompt renderer, Keychain, client factory, and menu proxy.*
- [ ] **T-28** Configure code signing, notarization, and create a distributable DMG
  - AC: DMG can be opened on a fresh macOS 14 machine without Gatekeeper warnings.
- [x] **T-29** Write developer README with build instructions, permission setup guide, and pipeline authoring guide
  - AC: A developer can follow the README to build, run, and test the app from scratch.

---

## Phase 2 — Voice Input

### M9: Trigger & Recording
- [x] **T-30** Add WhisperKit SPM dependency (argmaxinc/WhisperKit, ≥0.9.0) to Package.swift and yowee target
  - AC: `import WhisperKit` compiles in Sources/yowee without errors.
- [~] **T-31** Implement VoiceShortcutManager: CGEventTap at .cgSessionEventTap intercepting ⌃Space keyDown/keyUp/flagsChanged; fires onRecordStart/onRecordStop closures; suppresses the event
  - AC: Pressing `⌥R` prints "record start" and pressing `⌥S` prints "record stop" in the log.
  - *Deviation: `VoiceShortcutManager.swift` not created. CGEventTap not used for voice. Push-to-talk (⌃Space hold/release) requires `keyUp` detection, which Carbon `RegisterEventHotKey` cannot provide; CGEventTap can detect `keyUp` but requires Accessibility permission and event-suppression logic to prevent the input-source switcher. Instead, `GlobalShortcutManager` was extended with two additional `RegisterEventHotKey` registrations: ID 2 = `⌥R` (voice start, user-configurable) and ID 3 = `⌥S` (voice stop, fixed). Fires `onVoiceStart` / `onVoiceStop` closures on the main thread. No additional permissions required.*
- [x] **T-32** Implement AudioRecorder: AVAudioRecorder to temp M4A (16kHz mono); exposes normalized audioLevel; startRecording() → URL, stopRecording() → URL?
  - AC: stopRecording() returns a playable M4A file; audioLevel reflects actual microphone input.
  - *Note: `stopRecording()` uses `defer { outputURL = nil }` to make repeated calls idempotent (returns nil on second call). Timer callback uses `MainActor.assumeIsolated` instead of `Task { @MainActor in }` to avoid 20 Task allocations/second.*
- [x] **T-33** Add NSMicrophoneUsageDescription to Info.plist; request microphone permission via AVCaptureDevice.requestAccess on first use; show error banner if denied
  - AC: First voice trigger shows macOS permission dialog; denial shows ErrorBanner "Microphone permission denied".

### M10: Transcription
- [~] **T-34** Implement WhisperTranscriber actor: loads WhisperKit lazily; exposes downloadProgress: Double? during first-use download; transcribe(audioURL:) → String
  - AC: transcribe() returns accurate text from a test recording; second call is fast (model cached).
  - *Deviation: Model name is NOT hardcoded as `"openai/whisper-large-v3-turbo"`. WhisperKit's download cache uses folder names with a date suffix (e.g. `openai_whisper-large-v3-v20240930_626MB`); hardcoding fails glob matching. `WhisperKit.recommendedModels().default` is called at runtime to get the correct name for the current device and WhisperKit version. `downloadProgress` exposed via `OSAllocatedUnfairLock<Double?>` (not `AsyncStream`) — the download callback fires on an arbitrary background thread while the actor executor is suspended, making lock-based access necessary. Concurrent callers during load park on `withCheckedThrowingContinuation` (not recursive calls); on failure, `state` resets to `.unloaded` so the next call retries without an app restart.*
- [x] **T-35** Surface model download progress in VoiceRecordingPanel: "Downloading speech model (first time only)… X%" with progress bar
  - AC: First voice trigger shows download progress; subsequent triggers skip download state entirely.

### M11: Panel UI
- [x] **T-36** Implement WaveformView: 7 animated capsule bars driven by AudioRecorder.audioLevel; animation uses TimelineView at 20Hz with sine-wave phase offsets per bar
  - AC: Bars visually respond to voice amplitude with smooth animation; idle shows minimal movement.
  - *Note: Uses `TimelineView(.animation(minimumInterval: 1/20.0))` rather than a Timer, which is idiomatic SwiftUI for animation-driven views.*
- [x] **T-37** Implement VoiceRecordingView (SwiftUI): renders all panel states (recording, transcribing, modelDownload, processing, error); pipeline picker using PipelineStore pipelines + "Direct" option; ✕ cancel button
  - AC: All states are visually distinct and render without layout issues.
  - *Note: Implemented in `VoiceRecordingView.swift` (split from `VoiceRecordingPanel.swift` during refactoring). Includes `.idle` case rendered as `EmptyView()`.*
- [x] **T-38** Implement VoiceRecordingPanel: borderless nonactivatingPanel at .popUpMenu level; positioned near cursor; wraps VoiceRecordingView; auto-sized to content
  - AC: Panel appears above all windows of the frontmost app; does not steal keyboard focus from the source text field.
  - *Note: Panel positioning shared via `NSPanel.positionNear(_:width:height:)` extension in `FloatingPanelSupport.swift`. `reflow()` recalculates panel height from SwiftUI `fittingSize` on each state transition, keeping the top edge fixed. Keyboard shortcuts (⌥Esc cancel, ↩ confirm, ⌥↑↓ cycle pipeline) handled via local `NSEvent` monitor.*

### M12: Orchestration & Insertion
- [~] **T-39** Implement VoiceInputCoordinator: @MainActor class; state machine idle→recording→transcribing→processing→idle; captures originalApp at trigger
  - AC: Full voice-to-text flow works end-to-end: press ⌥R, speak, press ⌥S, text appears at cursor.
  - *Deviation: Trigger changed from ⌃Space push-to-talk to ⌥R/⌥S press-to-toggle (see T-31). Does NOT own `VoiceShortcutManager` (removed); instead receives `onVoiceStart`/`onVoiceStop` callbacks via `GlobalShortcutManager`. State machine uses `VoiceState` enum in `VoiceSessionState` as single source of truth — `isActive: Bool` anti-pattern eliminated. `transcriptionTask` and `pipelineTask` tracked as `Task<Void, Never>?` so `cancel()` cancels in-flight HTTP requests. Transcribed text stored in `.pipelineSelection(transcribedText:)` enum case (not a separate stored property).*
- [x] **T-40** "Direct" pipeline path: transcription result pasted via Cmd+V after originalApp re-activation + 300ms delay; panel closes automatically
  - AC: Voice input inserts transcription at cursor in TextEdit, Notes, and Electron apps.
  - *Note: Uses `TextReplacer.pasteViaCmdV` (shared with text pipeline path; made `internal` during refactoring).*
- [x] **T-41** LLM pipeline path: transcription fed into PipelineRunner; result pasted; panel shows "Processing…" state during LLM call
  - AC: Selecting "Improve Grammar" pipeline processes speech through the LLM and inserts corrected text.
- [x] **T-42** Wire VoiceInputCoordinator into AppDelegate.applicationDidFinishLaunching alongside YoweeOrchestrator
  - AC: Voice feature activates on app launch without interfering with ⌥Space text pipeline.
  - *Note: `voiceCoordinator?.setup()` called after `GlobalShortcutManager.shared.register(with:)` so voice hotkeys are registered in the same Carbon event handler.*

---

## Phase 3 — Markdown Notepad

- [ ] **T-43** Add Ink SPM dependency for Markdown parsing
- [ ] **T-44** Implement `MarkdownEditorView` using TextKit 2 NSTextView with syntax highlighting
- [ ] **T-45** Implement split-pane live preview using Ink
- [ ] **T-46** Implement `DocumentStore`: open/save/create Markdown files; recent files list
- [ ] **T-47** Integrate pipeline actions into the editor toolbar and right-click menu
