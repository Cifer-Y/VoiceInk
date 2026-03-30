# VoiceInk

A macOS menu bar app for voice-to-text transcription powered by [Whisper](https://github.com/ggerganov/whisper.cpp). Runs entirely on-device — no cloud, no subscription.

## Features

- Global hotkey to start/stop recording
- On-device speech recognition via Whisper
- Auto-paste transcribed text into any app
- Optional LLM post-processing for grammar correction
- Composing mode with live waveform visualization
- Usage statistics tracking

## Requirements

- macOS 14.0+
- Swift 5.9+
- A Whisper model file (GGML format)

## Build & Install

```bash
# Clone the repo
git clone https://github.com/Cifer-Y/VoiceInk.git
cd VoiceInk

# Build and create .app bundle
make app

# Install to /Applications
make install
```

## Usage

1. Launch VoiceInk — it runs as a menu bar app (no dock icon)
2. Grant microphone and accessibility permissions when prompted
3. Download a Whisper model from Settings
4. Press the global hotkey (default: Right Option) to start recording
5. Release to transcribe and paste

## License

MIT
