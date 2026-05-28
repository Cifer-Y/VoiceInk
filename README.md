# VoiceInk

A macOS menu bar app for voice-to-text input. Choose between Apple's on-device Speech engine or any OpenAI-compatible transcription API — no clipboard pollution, no lock-in.

[中文文档](README_CN.md)

---

## Features

### Dual Transcription Engine

- **Apple Speech** — on-device, zero-setup, real-time, free
- **OpenAI-compatible API** — `/audio/transcriptions` against any OpenAI-compatible endpoint (OpenAI `gpt-4o-mini-transcribe` / `whisper-1`, Groq, self-hosted, etc.)
- Choose engine independently for short sentence and long text (composing) modes

### LLM Error Correction

- Fix homophones using context (配森→Python, 模形→模型, 因该→应该)
- Remove filler words (嗯/啊/呃/那个)
- Convert Chinese phonetic transcriptions of English terms to English
- Works with OpenAI, Ollama, or any OpenAI-compatible API

### Context-Aware Refinement

- Maintains a rolling buffer of recent outputs as context for the next LLM call
- If you manually correct a result, the corrected version replaces the original in the buffer
- The more you use it, the more accurate it gets — a positive feedback loop

### Composing Mode

- Double-tap to enter composing mode for multi-segment dictation
- Record multiple paragraphs, review and edit before confirming
- Separate LLM config handles self-corrections, reorganizes into clear paragraphs
- Dynamic floating panel with real-time waveform visualization

### Correction History & Few-Shot Learning

- Short-tap after dictation to manually correct any errors
- Corrections are saved and used as few-shot examples for future LLM calls
- Bigram similarity matching selects the most relevant examples
- Up to 200 correction entries with full ASR → LLM → Corrected progression

### User Dictionary

- Add domain-specific terms, product names, proper nouns
- Terms bias the transcription engine via its initial prompt (OpenAI `prompt` parameter)
- Terms are injected into LLM system prompt as preferred vocabulary

### Zero Clipboard Pollution

- Text is injected via simulated keystrokes (CGEvent), not clipboard
- Your clipboard contents are never overwritten during normal use
- Smart CJK input method detection — auto-switches to ASCII before injection, restores after

### Multi-Language Support

Simplified Chinese · English · Traditional Chinese · Japanese · Korean

### Other

- **Menu bar app** — no dock icon, minimal footprint
- **Real-time waveform** — live RMS visualization during recording
- **Usage statistics** — track recordings, duration, corrections, and composing sessions
- **Structured logging** — debug with `log stream` using os.Logger categories

---

## Requirements

- macOS 14.0+
- Microphone & Accessibility permissions
- (Optional) OpenAI-compatible API key for transcription — only required if you choose the OpenAI engine; Apple Speech works offline with no setup
- (Optional) OpenAI-compatible API for LLM correction

---

## Build & Install

```bash
git clone https://github.com/Cifer-Y/VoiceInk.git
cd VoiceInk

swift build -c release
cp .build/arm64-apple-macosx/release/VoiceInk VoiceInk.app/Contents/MacOS/VoiceInk
cp -R VoiceInk.app /Applications/
```

---

## Usage

1. Launch VoiceInk — it appears in the menu bar
2. Grant microphone and accessibility permissions when prompted
3. In Settings, pick an engine — Apple Speech needs nothing; OpenAI needs a base URL + API key
4. **Hold Right Option** to record, release to transcribe
5. **Short tap** after transcription to correct errors
6. **Double tap** to enter composing mode for long text

---

## License

MIT
