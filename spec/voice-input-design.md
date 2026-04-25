# Yowee — Voice Input Design (Phase 2)

> **Status: Implemented.** This document reflects the delivered implementation. The original design (archived below in §8) specified push-to-talk via CGEventTap; the actual implementation uses press-to-start/stop via Carbon `RegisterEventHotKey`.

---

## 1. Overview

Phase 2 adds voice input to Yowee. Pressing `⌥R` starts recording; pressing `⌥S` stops it. WhisperKit transcribes the audio on-device, and the result is either inserted verbatim at the cursor or routed through a user-selected LLM pipeline — matching the text-selection UX from Phase 1.

---

## 2. UX Flow

### Step 1 — Press `⌥R` to start

A floating recording panel appears near the cursor. The user speaks.

```
┌─────────────────────────────────────┐
│  🎙  Recording                     ✕ │
│                                     │
│   ▁ ▃ ▇ █ ▅ ▂ ▄  (waveform bars)  │
│                                     │
│   Press ⌥S to stop                 │
└─────────────────────────────────────┘
```

- Microphone icon (pulsing) + "Recording" label.
- Seven animated capsule bars reflecting live microphone amplitude (20 Hz via `AVAudioRecorder` metering).
- Hint: "Press ⌥S to stop".
- ✕ button (or `⌥Esc`) cancels immediately; panel closes; original app regains focus.
- Panel is draggable by clicking any non-interactive area (`isMovableByWindowBackground = true`).

---

### Step 2 — Press `⌥S` to stop → transcription begins

Recording stops. Panel transitions immediately without closing.

#### State 2a — Model download (first use only)

```
┌─────────────────────────────────────┐
│  ⬇  Downloading speech model…     ✕ │
│                                     │
│  ████████░░░░░░░  63%              │
│  First use only — this may take     │
│  a few minutes                      │
└─────────────────────────────────────┘
```

Shown only on first run while WhisperKit downloads the model (~600–900 MB depending on device). Progress bar is determinate (real 0→1 from `WhisperKit.download` progress callback). Subsequent runs skip this state (model is cached in `~/.cache/huggingface/hub/`).

#### State 2b — Transcribing

```
┌─────────────────────────────────────┐
│  〜  Transcribing…                  ✕ │
│                                     │
│  ─────────────────── (spinner bar)  │
│                                     │
└─────────────────────────────────────┘
```

Indeterminate progress bar while WhisperKit loads CoreML models into memory and runs inference.

---

### Step 3 — Transcription complete → pipeline selection

```
┌─────────────────────────────────────┐
│  ✓  Done                           ✕ │
│                                     │
│  [  Direct (no LLM)            ▾ ] │
│                                     │
│  [         Process          ]       │
└─────────────────────────────────────┘
```

- Green checkmark icon + "Done" label.
- Picker (centred) listing "Direct (no LLM)" and all user-configured pipelines.
- Picker receives keyboard focus automatically.
- Keyboard shortcuts: `⌥↓` / `⌥↑` cycles options without opening the dropdown; `↩` (Return) confirms; `⌥Esc` cancels.
- "Process" button has the same effect as `↩`.
- Panel becomes the key window so keyboard input is captured.

---

### Step 4 — Output insertion

#### "Direct (no LLM)" selected

Panel closes immediately. The transcription text is pasted at the cursor in the original app (`originalApp.activate()` + 300 ms delay + `TextReplacer.pasteViaCmdV(text)`).

#### LLM pipeline selected

```
┌─────────────────────────────────────┐
│  ⚙  Running "Improve Grammar"…    ✕ │
│                                     │
│  ─────────────────── (spinner bar)  │
│                                     │
└─────────────────────────────────────┘
```

Indeterminate progress bar while `PipelineRunner.run` executes. On completion, panel closes and result is pasted.

If cancelled (`⌥Esc` or ✕): the HTTP request is cancelled, nothing is inserted, original app regains focus.

---

### Error states

#### Microphone permission denied
`ErrorBanner` shown: "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone." Panel does not open.

#### Transcription error / no speech detected
Error message shown in panel for 4 seconds, then panel auto-dismisses. Failure resets the transcriber to allow retry (no app restart required).

```
┌─────────────────────────────────────┐
│  ⚠  No speech detected — try       ✕ │
│     speaking more clearly.          │
└─────────────────────────────────────┘
```

---

## 3. Architecture

### Components

#### GlobalShortcutManager (extended from Phase 1)

Registers `⌥R` (ID 2, voice start — user-configurable) and `⌥S` (ID 3, voice stop — fixed) via `RegisterEventHotKey`. Fires `onVoiceStart` / `onVoiceStop` closures on the main thread. No Input Monitoring or Accessibility permission required.

#### AudioRecorder

`@MainActor final class`. `AVAudioRecorder` writes to a temp file: `FileManager.default.temporaryDirectory/yowee_voice_<UUID>.m4a`. Settings: 16 kHz mono AAC (optimal Whisper input). Exposes `audioLevel: Float` (0–1, normalised from `averagePower(forChannel:0)`) updated at 20 Hz via `Timer` (fires on main run loop; uses `MainActor.assumeIsolated` — no Task allocation per tick).

`stopRecording() -> URL?` returns the URL and resets the stored path to `nil` (idempotent — repeated calls return nil).

#### WhisperTranscriber

Swift `actor` singleton. Two-phase lazy initialisation:

1. **Download** — `WhisperKit.download(variant: WhisperKit.recommendedModels().default, progressCallback:)`. Progress is exposed via `OSAllocatedUnfairLock<Double?>` (thread-safe; the callback fires on a background thread while the actor executor is suspended).
2. **Memory load** — `WhisperKit(modelFolder:download:false,load:true)`. Loads CoreML models into the ANE; no download-style progress.

Concurrent callers during load park on `withCheckedThrowingContinuation` and are all resumed when loading completes (or fails). On failure, `state` resets to `.unloaded` so the next `transcribe()` call retries — no app restart required.

`warmUp()` is called at launch in a background Task to pre-load the model so first use is instant.

#### VoiceSessionState

`@Observable @MainActor final class` — owns all panel-bound state:

```swift
var voiceState: VoiceState    // .idle | .recording | .modelLoading | .transcribing |
                               // .pipelineSelection(transcribedText:) | .processingPipeline(name:) | .error(String)
var audioLevel: Float          // 0–1, updated at 20 Hz during recording
var selectedPipelineID: UUID?  // nil = Direct; set by picker or ⌥↑↓
var loadingProgress: Double?   // 0–1 during model download; nil otherwise
```

#### VoiceInputCoordinator

`@MainActor final class`, owned by `AppDelegate`. Single source of truth is `sessionState.voiceState`; the `isActive: Bool` anti-pattern was eliminated. Guards at method entry pattern-match the `VoiceState` enum.

Tracks `transcriptionTask` and `pipelineTask` (`Task<Void, Never>?`); both are cancelled in `cancel()` so HTTP requests do not run to completion after the user aborts.

#### VoiceRecordingPanel

`@MainActor final class`. Wraps an `NSPanel` (`borderless`, `nonactivatingPanel`, level `.popUpMenu`, `isMovableByWindowBackground = true`). Uses `NSPanel.positionNear(_:width:height:)` (shared `FloatingPanelSupport` extension) to position near cursor within the visible screen area.

Local `NSEvent` monitor captures `⌥Esc` (cancel), `↩` (confirm), `⌥↓`/`⌥↑` (cycle pipeline). All actions that modify app-level state are dispatched via `Task { @MainActor in }` to defer past the current event-dispatch cycle, ensuring `originalApp.activate()` fires after the system finishes processing the key event.

`reflow()` recalculates panel height from SwiftUI `fittingSize` and adjusts the frame (keeping the top edge fixed) on each state transition.

#### VoiceRecordingView / WaveformView

SwiftUI `View` in `VoiceRecordingView.swift`. Switches on `session.voiceState` to render each panel state. `WaveformView` uses `TimelineView(.animation(minimumInterval: 1/20.0))` with 7 sine-offset capsule bars driven by `AudioRecorder.audioLevel`.

---

## 4. State Machine

```
         ⌥R pressed (mic authorized)
.idle ──────────────────────────────► .recording
  ▲                                        │
  │  cancel (⌥Esc / ✕)                    │ ⌥S pressed
  │◄───────────────────────────────────────┤
  │                                        ▼
  │                              .modelLoading  ← first use only
  │  cancel                          │  (model cached on subsequent runs)
  │◄─────────────────────────────────┤
  │                                  ▼
  │                            .transcribing
  │  cancel                          │ WhisperKit completes
  │◄─────────────────────────────────┤
  │                                  ▼
  │                    .pipelineSelection(transcribedText:)
  │  cancel                          │ ↩ or "Process"
  │◄─────────────────────────────────┤
  │               ┌──────────────────┴──────────────────┐
  │        Direct (no LLM)                    pipeline selected
  │               │                                      │
  │               │                       .processingPipeline(name:)
  │  (auto)       │  (auto)                              │  (auto)
  │◄──────────────┴──────────────────────────────────────┘
  │
  │  auto-dismiss after 4 s
  │◄──────────────── .error(String)
```

| Transition | Trigger | Side effect |
|---|---|---|
| `.idle` → `.recording` | `⌥R` pressed; mic authorized | Capture `originalApp`; show panel; start `AudioRecorder` |
| `.recording` → `.modelLoading` or `.transcribing` | `⌥S` pressed | `AudioRecorder.stopRecording()`; start `WhisperTranscriber.transcribe()` |
| `any` → `.idle` (cancel) | `⌥Esc`, ✕, or error auto-dismiss | Cancel `transcriptionTask` + `pipelineTask`; stop recorder; delete temp file; dismiss panel; re-activate original app |
| `.pipelineSelection` → `.idle` (direct) | `↩` with nil pipeline | Dismiss panel; `originalApp.activate()`; 300 ms; `TextReplacer.pasteViaCmdV()` |
| `.pipelineSelection` → `.processingPipeline` | `↩` with pipeline selected | `PipelineRunner.run()` in tracked `pipelineTask` |
| `.processingPipeline` → `.idle` | Pipeline completes | Paste result; dismiss panel |
| `any` → `.error` | Transcription or pipeline throws | Show message 4 s; auto-cancel |

---

## 5. Text Insertion

Voice output always uses the clipboard-paste path (not AX write) because there is no pre-existing selection to overwrite — the cursor is at an insertion point, not a text range.

1. `originalApp` captured at `⌥R` press time (before panel appears).
2. On insert: `originalApp?.activate(options: [.activateIgnoringOtherApps])`.
3. `Task.sleep(nanoseconds: 300_000_000)` — allows the app to become key.
4. `TextReplacer.pasteViaCmdV(text)` — writes to `NSPasteboard.general`, posts CGEvent `Cmd+V` via `.cgSessionEventTap`, restores previous clipboard after 500 ms.

`TextReplacer.pasteViaCmdV` is `internal` (not `private`) so both the text pipeline fallback and the voice path share the same implementation.

---

## 6. Permissions

### Microphone
- `NSMicrophoneUsageDescription` key in `Info.plist`.
- `AVCaptureDevice.requestAccess(for: .audio)` called on first `⌥R` press.
- If already authorized: synchronous path (avoids race where `⌥S` fires before permission is granted).
- If denied: `ErrorBanner` shown; recording does not start.

### Accessibility
- Already granted in Phase 1.
- **Not required** for hotkey registration (Carbon `RegisterEventHotKey` does not need it).
- Required only for the Phase 1 AX text read/write path.

---

## 7. Key Technical Decisions

### Press-to-start / press-to-stop instead of push-to-talk

Push-to-talk (hold-to-record) requires `keyUp` detection, which Carbon `RegisterEventHotKey` cannot provide. CGEventTap can detect `keyUp` but requires Accessibility permission and event-suppression logic (to prevent `⌃Space` from opening the input-source switcher).

Two separate press-once hotkeys (`⌥R` / `⌥S`) are simpler, require no additional permissions, and are more comfortable for longer dictation sessions.

### Runtime model selection via `recommendedModels().default`

Hardcoding a model name (e.g. `"openai/whisper-large-v3-turbo"`) fails because WhisperKit's download cache uses folder names like `openai_whisper-large-v3-v20240930_626MB` that contain a date suffix. `WhisperKit.recommendedModels().default` returns the correct folder name for the current device and WhisperKit version.

### `nonactivatingPanel` keeps original app focused

`NSPanel` with `.nonactivatingPanel` styleMask does not become the key window when shown. The original app's text field stays focused during recording. After the user interacts with the pipeline picker (which briefly activates Yowee via `makeKeyAndOrderFront`), `originalApp.activate(.activateIgnoringOtherApps)` explicitly restores focus before the paste.

### Temp file instead of streaming

WhisperKit's primary API operates on a recorded audio file, not a live stream. Recording to a temp M4A decouples recording from transcription cleanly, simplifies error handling (delete on cancel via `AudioRecorder.cleanUp(url:)`), and allows the full audio to be inspected for debugging.

---

## 8. Original Design (Archived)

The original design specified:
- **Trigger:** Hold `⌃Space` (push-to-talk) — suppressed via CGEventTap so macOS input-source switcher does not open.
- **Stop:** Release `⌃` (keyUp / flagsChanged via CGEventTap).
- **Component:** `VoiceShortcutManager` owning a `CGEventTap` at `.cgSessionEventTap` with `.defaultTap`.
- **Pipeline picker:** Shown during transcription (pre-selection before Whisper finishes).
- **Model:** Hardcoded `"openai/whisper-large-v3-turbo"`.
- **`downloadProgress`:** Published via `AsyncStream`.

All of these were changed during implementation. `VoiceShortcutManager.swift` was removed (replaced by `GlobalShortcutManager`). CGEventTap is not used anywhere in the voice path.
