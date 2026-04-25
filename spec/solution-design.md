# Yowee — Solution Design

## 1. Tech Stack Decision

### Primary Language: Swift 6
**Rationale:** Native macOS system APIs (Accessibility, CGEvent, Keychain, CoreML) are first-class citizens in Swift. SwiftUI provides a modern declarative UI. Swift concurrency (async/await, actors) maps cleanly onto the pipeline execution model.

### Key Libraries & Frameworks

| Concern | Technology | Rationale |
|---------|-----------|-----------|
| UI | SwiftUI + AppKit (where needed) | SwiftUI for config panel; AppKit for NSStatusItem, NSMenu, NSPanel overlays |
| Global shortcut | Carbon `RegisterEventHotKey` (custom `GlobalShortcutManager`) | Handles keyDown for all hotkeys; no Accessibility or Input Monitoring permission required; user-configurable |
| Text read | AXUIElement (`AccessibilityReader`) | Reads selected text + range without touching other apps' menus |
| Text write | AXUIElement + CGEvent Cmd+V fallback (`TextReplacer`) | AX write is instant and clipboard-safe; Cmd+V covers apps that ignore AX writes |
| LLM API calls | URLSession + async/await (custom thin wrappers) | Avoids heavy SDK dependencies; all providers share similar REST shapes |
| API key storage | Security framework (Keychain) | OS-enforced, encrypted at rest; open-access ACL survives ad-hoc re-signing |
| Voice transcription (Ph 2) | WhisperKit (argmaxinc/WhisperKit, ≥0.9.0) | Swift-native, CoreML/ANE-optimised, fully on-device |
| Audio capture (Ph 2) | AVFoundation | Native, no extra deps; 16 kHz mono M4A optimal for Whisper |
| Markdown editor (Ph 3) | Ink (parsing) + custom TextKit 2 view | Lightweight, no Electron |
| Persistence | `@Observable` models + JSON files (`~/.config/yowee/`) | Simple, no separate DB process, schema-version field for migrations |
| Logging | OSLog + thread-safe file sink (`AppLogger`) | Zero overhead when not capturing; Console.app visible; in-app LogView tails the file |
| Testing | Swift Testing framework via `TestRunner` executable | `swift run TestRunner` works without Xcode's `swiftpm_testing_helper` |

### Rejected Alternatives
- **Electron/Tauri**: Heavy, poor Accessibility API support, worse system integration.
- **Python**: Fragile macOS interop, requires runtime distribution, slower startup.
- **Rust + objc2**: High complexity for marginal gain; Swift is sufficiently fast.
- **SwiftData**: Considered for pipeline persistence; rejected because `@Model` macro requires Xcode's compiler plugin infrastructure (breaks `swift build` / `swift run TestRunner`). `@Observable` + JSON DTOs provide equivalent reactivity with simpler tooling.
- **KeyboardShortcuts SPM** (Sindre Sorhus): Rejected — its `Recorder.swift` uses `#Preview` macro unavailable in CLI builds; also depends on the same Xcode plugin infrastructure. Replaced with a custom Carbon `RegisterEventHotKey` implementation that covers all three hotkeys (text trigger, voice start, voice stop) in a single manager.

---

## 2. Global Keyboard Shortcut Trigger

### Approach Decision

| Approach | Mechanism | Verdict |
|----------|-----------|---------|
| A | CGEventTap (intercept events) → suppress native behaviour → show custom UI | ❌ Rejected for trigger: destroys native context menu; requires Accessibility permission; fragile across apps |
| B | macOS Services (NSServices) | ❌ Poor discoverability; buried under Services submenu |
| C | Global keyboard shortcut → floating yowee menu | ✅ Chosen |
| D | SIMBL/code injection | ❌ Requires SIP disable; not acceptable |

### Chosen Approach: Carbon `RegisterEventHotKey`

`GlobalShortcutManager` registers up to three simultaneous hotkeys via `RegisterEventHotKey` with numeric IDs:
- **ID 1**: Text pipeline trigger (default `⌥Space`, user-configurable)
- **ID 2**: Voice recording start (default `⌥R`, user-configurable)
- **ID 3**: Voice recording stop (fixed `⌥S`)

The Carbon event handler dispatches to Swift closures (`onTrigger`, `onVoiceStart`, `onVoiceStop`) via `DispatchQueue.main.async`. No Input Monitoring or Accessibility permission is required for hotkey registration.

**Text pipeline flow:**
1. `⌥Space` fires `onTrigger` → `YoweeOrchestrator.handleTrigger()`
2. Read selected text via `AXUIElementCopyAttributeValue` on the system-focused element.
3. If empty: show `ErrorBanner`; abort.
4. If non-empty: display `YoweeMenu` (NSMenu modal loop) near cursor with all pipelines.
5. On selection: run pipeline asynchronously; replace text via `TextReplacer`.
6. Host application's native right-click menu is **never touched**.

### Text Replacement Strategy (in priority order)
1. `AXUIElementSetAttributeValue(kAXSelectedTextAttribute, newText)` — instant, no clipboard side-effects; works in most AppKit/SwiftUI fields.
2. `NSPasteboard` write + CGEvent `Cmd+V` via `.cgSessionEventTap` — fallback for apps that ignore AX writes (e.g. Notes, Electron apps); clipboard is restored to its previous contents after 500 ms.

Verification of AX write uses a before/after snapshot of `kAXSelectedTextAttribute`: if the selected text changes (even to `""` as the selection collapses), the write succeeded. This correctly handles Notes, which returns `kAXErrorSuccess` but silently ignores the write.

---

## 3. Pipeline Execution Model

```
Selected Text (String)
        │
        ▼
┌──────────────────────────────────────┐
│  Pipeline                            │
│  ┌────────────────────────────────┐  │
│  │ Step 1: PromptStep             │  │
│  │  systemPrompt: "..."           │  │
│  │  userTemplate: "... {{input}}" │  │
│  │  model: claude-sonnet-4-6      │  │
│  └───────────────┬────────────────┘  │
│                  │ LLM response      │
│  ┌───────────────▼────────────────┐  │
│  │ Step 2: PromptStep             │  │
│  │  userTemplate: "... {{input}}" │  │
│  └───────────────┬────────────────┘  │
│                  │                   │
└──────────────────┼───────────────────┘
                   │
                   ▼
         Replacement Text (String)
```

### Data Models

```swift
// @Observable for reactive SwiftUI binding; persisted as JSON (not SwiftData)
@Observable final class Pipeline {
    var id: UUID
    var name: String
    var steps: [PromptStep]
    var sortOrder: Int
    var createdAt: Date
}

@Observable final class PromptStep {
    var id: UUID
    var systemPrompt: String?
    var userTemplate: String       // must contain {{input}}
    var providerRaw: String        // raw LLMProvider enum value
    var modelID: String            // e.g. "claude-sonnet-4-6"
    var sortOrder: Int
}
```

Steps are never passed directly across actor boundaries. `StepData` (a `Sendable` value type) snapshots a `PromptStep` before crossing from `@MainActor` into the `PipelineRunner` actor.

---

## 4. Menu Bar App Architecture

```
NSStatusItem (menu bar icon)
    └── NSMenu
        ├── "Pipelines  (⌥Space)" (disabled header)
        │   ├── [Pipeline 1]   (display only; execution via ⌥Space, not menu click)
        │   └── [Pipeline 2]
        ├── ─────────────────
        ├── "Configure yowee…"  → opens SwiftUI settings window (⌘,)
        └── "Quit yowee"        (⌘Q)
```

The configuration window is managed manually via `NSWindowController` (not a SwiftUI `Settings` scene) because the app runs as `.accessory` (no Dock icon) and needs precise control over activation policy transitions:
- `.accessory` at rest (no Dock icon, no App Switcher entry)
- `.regular` while settings window is open (enables standard window management)
- Back to `.accessory` on window close

Window is created once and reused (`isReleasedWhenClosed = false`, `collectionBehavior = [.moveToActiveSpace]`).

Settings tabs: **Pipelines** | **Providers** | **Shortcuts** | **Log**

---

## 5. Voice Input Architecture (Phase 2)

### Trigger Mechanism

`⌥R` (press once to start) / `⌥S` (press once to stop) — both registered via Carbon `RegisterEventHotKey` in `GlobalShortcutManager`. This is a **press-to-start / press-to-stop** model, not push-to-talk. `⌥R` is user-configurable; `⌥S` is fixed.

No CGEventTap is used for voice. The earlier design specified CGEventTap for push-to-talk keyUp detection, but Carbon `RegisterEventHotKey` with two separate keys is simpler, requires no permissions, and avoids event suppression complexity.

### State Machine

`VoiceInputCoordinator` owns `VoiceState` (defined in `VoiceSessionState.swift`) as the single source of truth. A `VoiceSessionState` `@Observable` object bridges the state to SwiftUI.

```
         ⌥R pressed
.idle ─────────────────► .recording
  ▲                           │
  │  cancel (⌥Esc or ✕)      │ ⌥S pressed
  │◄──────────────────────────┤
  │                           ▼
  │                      .modelLoading  (first use: model downloading)
  │                           │  or
  │                      .transcribing  (model cached)
  │  cancel                   │ transcription complete
  │◄──────────────────────────┤
  │                           ▼
  │                  .pipelineSelection(transcribedText:)
  │  cancel                   │ ↩ or "Process" clicked
  │◄──────────────────────────┤
  │              ┌────────────┴──────────────┐
  │         Direct (no LLM)           Pipeline selected
  │              │                           │
  │              │                  .processingPipeline(name:)
  │  (auto)      │  (auto)                   │  (auto)
  │◄─────────────┴───────────────────────────┘
  │
  │  auto-dismiss after 4 s
  │◄── .error(String)
```

### Key Design Decisions

**Press-to-start/stop vs push-to-talk:** Push-to-talk (hold-to-record) requires `keyUp` detection, which Carbon `RegisterEventHotKey` cannot provide (keyDown only). CGEventTap can detect `keyUp` but requires Accessibility permission and suppression logic. Two separate hotkeys (`⌥R`/`⌥S`) are simpler, work without any permissions beyond what Phase 1 already requires, and are friendlier for longer dictation sessions.

**Pipeline selection after (not during) transcription:** The earlier design showed the pipeline picker during transcription so the user could pre-select. This was not implemented — the transcription UI is a spinner-only state, and the picker appears only after the transcript is ready, because the transcribed text is needed to populate the preview context.

**On-device model selection:** `WhisperKit.recommendedModels().default` is called at runtime rather than hardcoding a model name. This returns the best model for the device (e.g. `openai_whisper-large-v3-v20240930_626MB` on Apple Silicon). Hardcoded names fail glob matching in the WhisperKit download cache.

**Two-phase WhisperKit load:** `WhisperKit.download(variant:progressCallback:)` downloads model files with real 0→1 progress (for the determinate bar); then `WhisperKit(modelFolder:download:false,load:true)` loads CoreML models into memory (fast, indeterminate state). Progress is exposed via `OSAllocatedUnfairLock<Double?>` because the download callback fires on an arbitrary background thread while the actor executor is suspended.

---

## 6. Security & Privacy

- Accessibility permission requested at launch with a guided prompt pointing to System Settings.
- Microphone permission requested only when voice feature is first used (`⌥R` first press).
- All API keys written to Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and an open-access ACL so items remain readable across ad-hoc rebuilds.
- Global hotkeys use Carbon `RegisterEventHotKey` — no CGEventTap, no Input Monitoring permission.
- Voice transcription is fully on-device (WhisperKit / CoreML / ANE). No audio or transcript is transmitted externally except as directed by a user-configured LLM pipeline step.
- No telemetry, no network calls except user-initiated LLM API requests.

---

## 7. Phase Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| 1 — Core | Global hotkey, pipeline engine, config UI, 4 default pipelines | Complete |
| 2 — Voice | ⌥R/⌥S recording, WhisperKit transcription, pipeline selection panel, Cmd+V insertion | Complete (implemented; deviates from original design — see §5) |
| 3 — Notepad | TextKit 2 Markdown editor, pipeline integration in editor | Planned |
