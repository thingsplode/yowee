# Yowee — Requirements

## 1. Functional Requirements

### 1.1 Global Keyboard Shortcut Trigger (FR-01)
- The app MUST register a system-wide keyboard shortcut (default: `⌥Space`) that activates the yowee pipeline picker from any application.
- When the shortcut is pressed, the app MUST read the currently selected text from the focused element via the Accessibility API.
- If no text is selected, the app MUST show a brief notification and take no further action.
- When text is selected, the app MUST display a floating yowee pipeline menu near the current cursor/caret position listing all user-configured pipelines.
- The shortcut MUST be user-configurable from the app's settings panel.
- The native right-click context menu of the host application MUST always remain fully intact and unmodified.
- Shortcut registration uses Carbon `RegisterEventHotKey`; no Input Monitoring or Accessibility permission is required for hotkey capture alone.

### 1.2 Pipeline Execution (FR-02)
- A pipeline MUST consist of: a name, a selected LLM model/provider, and one or more ordered prompt steps.
- Each prompt step MUST have: a template string with a `{{input}}` placeholder and an optional system prompt.
- The pipeline MUST execute steps sequentially: the output of step N is the `{{input}}` of step N+1.
- The final step output MUST replace the original text selection in the source application.
- The app MUST show a loading indicator (menu bar spinner) during pipeline execution.
- On API error, the app MUST surface the error to the user without modifying the selection.
- Text replacement uses the AXUIElement API as the primary path, with CGEvent `Cmd+V` paste as an automatic fallback for apps that ignore AX writes (e.g. Notes).

### 1.3 Pipeline Configuration (FR-03)
- The app MUST provide a SwiftUI configuration panel accessible via the menu bar icon.
- Users MUST be able to create, edit, reorder, and delete pipelines.
- Users MUST be able to add, reorder, and remove prompt steps within a pipeline.
- The app MUST support at minimum these LLM providers: Anthropic (Claude), OpenAI (GPT), and local Ollama endpoint.
- API keys and provider base URLs MUST be stored in the macOS Keychain.
- The OpenAI model list MUST be fetched dynamically from `GET /v1/models` and filtered to chat-capable models; a static fallback list is used when no key is set or the request fails.

### 1.4 Built-in Default Pipelines (FR-04)
- On first launch, the app MUST seed the following default pipelines:
  - **Improve Grammar** — system: "You are a writing assistant.", user: "Improve the grammar and clarity of the following text. Return only the corrected text:\n\n{{input}}"
  - **Make Concise** — "Rewrite the following text to be more concise. Return only the rewritten text:\n\n{{input}}"
  - **Translate to English** — "Translate the following text to English. Return only the translation:\n\n{{input}}"
  - **Change Tone: Professional** — "Rewrite the following text in a professional tone. Return only the rewritten text:\n\n{{input}}"

### 1.5 Voice Input Mode (FR-05, Phase 2 — Implemented)

#### 1.5.1 Activation and Recording
- The app MUST register two system-wide hotkeys for voice mode via Carbon `RegisterEventHotKey`: `⌥R` to start recording and `⌥S` to stop recording.
- Both hotkeys require no Input Monitoring or Accessibility permission.
- The `⌥R` trigger is user-configurable from the Shortcut settings panel; `⌥S` (stop) is fixed.
- When `⌥R` is pressed, the app MUST request microphone permission if not yet granted (system dialog), or immediately begin recording if already authorized.
- While recording, the app MUST display a floating non-activating panel near the mouse cursor showing:
  - A pulsing microphone icon and "Recording" label.
  - An animated waveform that reflects the live audio input level (updated at ~20 Hz).
  - A hint label: "Press ⌥S to stop".
- The panel MUST be draggable by clicking and dragging any non-interactive area.
- An `✕` button on the panel MUST cancel the recording session immediately.
- Pressing `⌥Esc` at any time during a voice session MUST cancel and dismiss the panel.
- The panel MUST position itself near the mouse cursor at the moment `⌥R` is pressed, constrained to the visible screen area.

#### 1.5.2 Transcription
- Pressing `⌥S` stops recording and immediately begins transcription; the panel transitions to a transcription state without closing.
- Transcription is performed entirely on-device using WhisperKit (CoreML / Apple Neural Engine).
- The model used is selected via `WhisperKit.recommendedModels().default` (e.g., `openai_whisper-large-v3-v20240930_626MB`).
- At app launch, the app MUST initiate a background warm-up of the Whisper model to minimise first-use latency.
- **Model download state** (first use only): if the model files are not yet cached on disk, the panel MUST show a determinate linear progress bar with a percentage readout and a "First use only — this may take a few minutes" subtitle. The download uses `WhisperKit.download(variant:progressCallback:)` for real 0–1 progress reporting.
- **Transcribing state**: once model files are present, the panel MUST show an indeterminate progress bar with a "Transcribing…" label while the CoreML models are loaded into memory and inference runs.
- If transcription produces empty output, the app MUST show a human-readable error: "No speech detected — try speaking more clearly."
- If transcription fails (model unavailable, network error during download, load failure), the app MUST show a plain-English error message in the panel for 4 seconds, then dismiss automatically.

#### 1.5.3 Pipeline Selection
- After successful transcription, the panel transitions to a pipeline selection state showing:
  - A green checkmark icon and "Done" label.
  - A centred dropdown picker listing "Direct (no LLM)" and all user-configured pipelines.
  - A centred "Process" button.
- The dropdown MUST receive keyboard focus automatically when the selection view appears.
- The panel MUST become the key window (receives keyboard input) at this point.
- The user MUST be able to cycle through pipeline options using `⌥↓` (next) and `⌥↑` (previous) without opening the dropdown.
- Pressing `↩` (Return, no modifiers) MUST activate the "Process" button and confirm the selection.
- Pressing `⌥Esc` MUST cancel and dismiss the panel.
- Clicking the "Process" button has the same effect as pressing `↩`.

#### 1.5.4 Output Insertion
- If "Direct (no LLM)" is selected, the transcribed text is inserted at the cursor position immediately without any LLM call.
- If a pipeline is selected, the transcribed text is passed through the pipeline steps; the panel shows a "Running \"{name}\"…" indeterminate progress indicator.
- Once output is ready, the panel dismisses, the original application is re-activated, and the result text is inserted via `Cmd+V` (CGEvent `Cmd+V` via `.cgSessionEventTap`).
- The previous clipboard contents MUST be restored 0.5 s after insertion to avoid polluting the user's clipboard.
- If pipeline execution fails, the app MUST show the error message in the panel for 4 seconds, then dismiss.

### 1.6 Markdown Notepad (FR-06, Phase 3 — Planned)
- The app MUST include an integrated notepad window backed by Markdown files.
- The editor MUST support standard Markdown syntax with live preview.
- Pipeline actions MUST be available within the notepad via toolbar or right-click.

---

## 2. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | End-to-end latency (trigger → text replaced) MUST be ≤ LLM/transcription round-trip + 300 ms activation overhead |
| NFR-02 | The app MUST NOT require disabling System Integrity Protection |
| NFR-03 | API keys MUST be stored exclusively in the macOS Keychain (never in plain files or UserDefaults) |
| NFR-04 | The app MUST request only the minimum required permissions: Accessibility (for AX text read/write) and Microphone (for voice recording, Phase 2 only); no Input Monitoring permission is required |
| NFR-05 | The app MUST support macOS 15 (Sequoia) and later; macOS 14 compatibility is not guaranteed due to WhisperKit / SwiftData API usage |
| NFR-06 | On-device Whisper inference MUST run on Apple Silicon Neural Engine via CoreML; audio processing MUST NOT be sent to any remote server |
| NFR-07 | The app MUST NOT be sandboxed — AXUIElement and Carbon `RegisterEventHotKey` are incompatible with the App Store sandbox; distribution is via notarized DMG or Homebrew cask |
| NFR-08 | Cold-start time (launch to menu bar ready) MUST be < 2 seconds; Whisper model warm-up runs in background and MUST NOT block startup |
| NFR-09 | All voice data MUST remain on-device; no audio or transcription text is transmitted externally except as explicitly directed by a user-configured LLM pipeline step |
| NFR-10 | The floating panel MUST appear above all application windows regardless of the host app's window level; `NSPanel` level is set to `.popUpMenu` (101) |

---

## 3. Constraints

- macOS only (no cross-platform requirement).
- Must work system-wide without browser extensions or per-app plugins.
- LLM calls are cloud-based in Phase 1; on-device LLM is out of scope for text pipelines.
- Voice transcription (Phase 2) is exclusively on-device via WhisperKit / CoreML.
- No server-side component — all orchestration runs locally on the user's machine.
- The app requires Accessibility permission for text read/write; this is granted once by the user in System Settings and must survive code-signing identity changes (open-access Keychain ACL pattern required).
- The app must be re-signed after every rebuild (`codesign --force --deep --sign -`) to keep the TCC accessibility permission hash valid.
