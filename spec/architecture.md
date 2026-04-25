# Yowee — Software Architecture

## 1. Module Map

```
Yowee (SPM package)
│
├── Sources/YoweeCore/                   # Pure-logic library — builds with `swift build`; no SwiftUI/AppKit/SwiftData
│   ├── Keychain/
│   │   └── KeychainStore.swift         # Generic Keychain save/load/delete for API keys
│   ├── Models/
│   │   └── LLMProvider.swift           # enum LLMProvider: anthropic | openai | ollama
│   └── PipelineEngine/
│       ├── PipelineRunner.swift        # Swift actor: sequential step execution
│       ├── PromptRenderer.swift        # {{input}} template substitution
│       ├── StepData.swift              # Sendable snapshot for actor-boundary crossing
│       └── LLMClient/
│           ├── LLMClientProtocol.swift # protocol LLMClient + LLMError enum
│           ├── LLMClientFactory.swift  # Provider → concrete client router
│           ├── AnthropicClient.swift   # Anthropic Messages API
│           ├── OpenAIClient.swift      # OpenAI Chat Completions + fetchModels()
│           └── OllamaClient.swift      # Ollama /api/chat endpoint
│
└── Sources/yowee/                       # macOS app — requires Xcode (no SwiftData macros used)
    ├── App/
    │   ├── YoweeApp.swift               # @main SwiftUI entry point; AppDelegate adaptor
    │   ├── AppDelegate.swift           # NSApplicationDelegate lifecycle; store init; Keychain warmup
    │   ├── AppLogger.swift             # Centralised OSLog + thread-safe file sink (/tmp/yowee_debug.log)
    │   └── YoweeOrchestrator.swift      # Wires trigger → menu → PipelineRunner → TextReplacer
    │
    ├── StatusBar/
    │   ├── StatusBarController.swift   # NSStatusItem owner; NSMenu builder; settings window lifecycle
    │   └── YoweeMenu.swift              # NSMenu.popUp modal loop for pipeline selection
    │
    ├── Shortcut/
    │   ├── GlobalShortcutManager.swift # Carbon RegisterEventHotKey; IDs 1=text, 2=voice-start, 3=voice-stop
    │   ├── HotKey.swift                # Codable keyCode+modifiers struct; Carbon ↔ CGEventFlags conversion
    │   ├── AccessibilityReader.swift   # AXUIElement: read selected text + focused element + range
    │   ├── TextReplacer.swift          # AX write primary; Cmd+V paste fallback (shared by voice path)
    │   └── AccessibilityPermissionGuard.swift  # AXIsProcessTrusted check + system prompt
    │
    ├── Models/
    │   ├── Pipeline.swift              # @Observable final class; sortedSteps computed property
    │   └── PromptStep.swift            # @Observable final class; provider bridged via providerRaw string
    │
    ├── Store/
    │   ├── PipelineStore.swift         # @Observable @MainActor; JSON persistence; sortedPipelines; restoreDefaults()
    │   └── ShortcutStore.swift         # @Observable @MainActor; JSON persistence; legacy UserDefaults migration
    │
    ├── PipelineEngine/
    │   └── StepDataExtension.swift     # PromptStep → StepData conversion
    │
    ├── UI/
    │   ├── ConfigurationView.swift     # TabView root: Pipelines | Providers | Shortcuts | Log
    │   ├── PipelineListView.swift      # CRUD list; drag-to-reorder; Restore Default Pipelines
    │   ├── PipelineEditorView.swift    # HSplitView: step list + name editor + validation
    │   ├── StepEditorView.swift        # Provider/model picker; dynamic OpenAI model list; template editor
    │   ├── ProviderSettingsView.swift  # API key SecureFields; Keychain save; masked display
    │   ├── ShortcutSettingsView.swift  # Custom NSViewRepresentable hotkey recorder button
    │   ├── LogView.swift               # Tails /tmp/yowee_debug.log; 1.5 s poll; auto-scroll
    │   └── Components/
    │       ├── ErrorBanner.swift       # NSPanel overlay at .popUpMenu level; 4 s auto-dismiss
    │       ├── LoadingHUD.swift        # Spinner NSPanel at .popUpMenu level during pipeline execution
    │       └── FloatingPanelSupport.swift  # NSPanel.positionNear() shared extension
    │
    └── VoiceInput/                     # Phase 2 (implemented)
        ├── VoiceSessionState.swift     # VoiceState enum + @Observable VoiceSessionState
        ├── VoiceInputCoordinator.swift # @MainActor state machine: idle→recording→transcribing→selecting→inserting
        ├── AudioRecorder.swift         # AVAudioRecorder 16kHz mono M4A; normalized audioLevel at 20 Hz
        ├── WhisperTranscriber.swift    # actor; two-phase download+load; OSAllocatedUnfairLock progress
        ├── VoiceRecordingPanel.swift   # NSPanel wrapper; keyboard handling (⌥Esc, ↩, ⌥↑↓)
        └── VoiceRecordingView.swift    # SwiftUI content: all VoiceState cases + WaveformView

MarkdownEditor/ (Phase 3 — planned)
    MarkdownEditorView.swift
    MarkdownRenderer.swift
    DocumentStore.swift
```

---

## 2. Data Flow: Keyboard Shortcut Pipeline Execution

```
User presses ⌥Space (or configured shortcut) in any app
          │
          ▼
GlobalShortcutManager (Carbon RegisterEventHotKey callback → DispatchQueue.main.async)
  └─ YoweeOrchestrator.handleTrigger()
      ├─ [pipeline already running] → ignore (re-entrancy guard)
      ├─ [no Accessibility permission] → ErrorBanner; abort
      └─ AccessibilityReader.selectedText()
          ├─ [empty] → ErrorBanner "No text selected"; abort
          └─ [has text] ──────────────────────────────────────────►
              │
              ▼
          YoweeMenu.show(pipelines:at:)   ← NSMenu.popUp modal loop near cursor
            └─ User picks pipeline (or dismisses)
                    │
                    ▼
              LoadingHUD.show()
                    │
                    ▼
              PipelineRunner.run(steps:input:)   ← Swift actor; URLSession async/await
                │
                ├─ For each step:
                │     PromptRenderer.render(template, input)
                │     LLMClient.complete(system, user, model)
                │     output → next step's input
                │
                └─ Returns final String
                    │
                    ▼
              LoadingHUD.hide()
              originalApp.activate(.activateIgnoringOtherApps)
              Task.sleep(300 ms)
                    │
                    ▼
              TextReplacer.replace(in:range:with:)
                ├─ AXUIElementSetAttributeValue(kAXSelectedTextAttribute)  [primary]
                └─ NSPasteboard + CGEvent Cmd+V                            [fallback]
```

---

## 3. Data Flow: Voice Input (Phase 2)

```
User presses ⌥R
          │
          ▼
GlobalShortcutManager.onVoiceStart → VoiceInputCoordinator.beginRecording()
  ├─ [session active] → ignore
  └─ AVCaptureDevice permission check
      ├─ [denied] → ErrorBanner; abort
      └─ [authorized] → AudioRecorder.startRecording()
                              VoiceRecordingPanel.show()
                              State: .recording (waveform animates)
                                    │
                          User presses ⌥S
                                    │
                                    ▼
                        AudioRecorder.stopRecording() → audioURL
                        State: .modelLoading or .transcribing
                                    │
                                    ▼
                        WhisperTranscriber.transcribe(audioURL:)
                          ├─ prepare(): download model if not cached (real 0→1 progress)
                          └─ WhisperKit.transcribe() → String
                                    │
                                    ▼
                        State: .pipelineSelection(transcribedText:)
                        User selects pipeline (⌥↑↓ or dropdown); presses ↩
                                    │
                        ┌───────────┴────────────┐
                        │ Direct (no LLM)        │ Pipeline selected
                        │                        ▼
                        │              PipelineRunner.run(steps:input:)
                        │              State: .processingPipeline(name:)
                        │                        │
                        └───────────┬────────────┘
                                    │
                                    ▼
                        originalApp.activate()
                        Task.sleep(300 ms)
                        TextReplacer.pasteViaCmdV(text)
                        State: .idle; panel dismissed
```

---

## 4. Concurrency Model

| Component | Execution Context | Notes |
|-----------|------------------|-------|
| `GlobalShortcutManager` | Carbon event thread → `DispatchQueue.main.async` | All callbacks land on main thread |
| `YoweeOrchestrator` | `@MainActor` | Re-entrancy guard via `pipelineTask != nil` check |
| `PipelineRunner` | Swift actor | Serialises pipeline runs |
| `LLMClient.complete` | Structured concurrency (async/await) | URLSession already async; 30 s timeout |
| `WhisperTranscriber` | Swift actor | Two-phase load; `OSAllocatedUnfairLock` for progress polling |
| `VoiceInputCoordinator` | `@MainActor` | Single source of truth: `VoiceState` enum |
| UI / AX calls | `@MainActor` | All SwiftUI state and AXUIElement calls |
| `AppLogger` file writes | Serial `DispatchQueue` (utility QoS) | Prevents interleaved lines from concurrent callers |

---

## 5. Persistence

**No SwiftData.** Models use `@Observable final class` for reactive UI updates, with JSON files for persistence.

| Data | Location | Format |
|---|---|---|
| Pipelines + steps | `~/.config/yowee/pipelines.json` | JSON via private `PipelineRecord`/`StepRecord` DTOs; `version` field for future migrations |
| Shortcut bindings | `~/.config/yowee/shortcuts.json` | JSON `HotKey` struct (keyCode + modifiers) |
| API keys | macOS Keychain | Open-access ACL survives ad-hoc re-signing |
| Ollama base URL | `UserDefaults` | Non-sensitive; no Keychain needed |

Schema model:
```
PipelineStore.pipelines: [Pipeline]
Pipeline            1 ──── N    PromptStep
─────────────────                ──────────────────────
id: UUID                         id: UUID
name: String                     name: String
sortOrder: Int                   sortOrder: Int
createdAt: Date                  systemPrompt: String?
                                 userTemplate: String     ← must contain {{input}}
                                 providerRaw: String      ← raw LLMProvider enum value
                                 modelID: String
```

Versioning: `PipelineRecord.version` defaults to `0` for legacy files; bumped to `1` on write. Future schema changes increment `PipelineStore.storageVersion` and add migration functions in `load()`.

---

## 6. LLM Client Interface

```swift
protocol LLMClient {
    func complete(
        system: String?,
        user: String,
        model: String,
        maxTokens: Int
    ) async throws -> String
}
```

Provider endpoints:

```
AnthropicClient:
  POST https://api.anthropic.com/v1/messages
  Headers: x-api-key, anthropic-version: 2023-06-01, content-type
  Body: { model, max_tokens, system?, messages: [{role:"user", content}] }
  Response: content[0].text

OpenAIClient:
  POST https://api.openai.com/v1/chat/completions
  Headers: Authorization: Bearer <key>
  Body: { model, max_completion_tokens, messages }   ← NOT max_tokens (deprecated)
  Response: choices[0].message.content
  Also: GET /v1/chat/models → dynamic model list (filtered to chat-capable)

OllamaClient:
  POST http://localhost:11434/api/chat   (configurable base URL)
  Body: { model, messages, stream: false }
  Response: message.content
```

---

## 7. Permissions & Entitlements

```
Required at runtime (not entitlements):
  - Accessibility (AXUIElement read/write) — prompted at launch via AXIsProcessTrustedWithOptions
  - Microphone (voice recording) — prompted on first ⌥R press via AVCaptureDevice.requestAccess

NOT required:
  - Input Monitoring — Carbon RegisterEventHotKey does not need it
  - com.apple.security.device.microphone entitlement — NSMicrophoneUsageDescription plist key suffices
```

The app is **not sandboxed** — `AXUIElement` is incompatible with the App Store sandbox. Distribution: notarized DMG / Homebrew cask.

Re-sign after every rebuild (`codesign --force --deep --sign -`) to keep the TCC accessibility hash valid.

---

## 8. Error Handling Strategy

| Error Source | Handling |
|---|---|
| No Accessibility permission | `ErrorBanner` with System Settings deep-link message |
| LLM API error (4xx/5xx) | `ErrorBanner` overlay; original text unchanged |
| LLM API timeout (>30 s) | URLSession cancellation; `ErrorBanner` |
| Empty LLM response | `ErrorBanner`; original text unchanged |
| AX write silently ignored (e.g. Notes) | Detected via before/after snapshot comparison; falls back to Cmd+V |
| AX write rejected | Falls back to Cmd+V |
| No microphone permission | `ErrorBanner` with System Settings deep-link message |
| Whisper model download failure | User-friendly message in voice panel; `state` reset to `.unloaded` for retry |
| Empty transcription | Error message "No speech detected"; panel auto-dismisses after 4 s |
