# Visual Assistant for the Visually Impaired

A voice-first mobile app that lets visually impaired users point their phone camera at anything, ask a question out loud, and get a spoken answer back in seconds. Zero screen interaction required.

## Demo

1. Press the volume button or tap the mic
2. Ask: *"What's in front of me?"*
3. The app captures the scene, sends it to GPT-4o Vision, and speaks the answer aloud

**[Download APK](https://github.com/Prakharr05/visual-assistant/releases)**

## How It Works

```
Volume button / Mic tap
        ↓
  Camera captures image instantly (pre-capture)
        ↓
  On-device speech recognition listens for question
        ↓
  Image (base64) + question → GPT-4o Vision API
        ↓
  Response → Text-to-Speech → spoken aloud
        ↓
  Ready for next question
```

The camera captures the image **the moment you activate** — not after you finish speaking. This concurrent pipeline cuts end-to-end latency by ~40% compared to sequential processing.

## Use Cases

- **Reading labels** — medicine bottles, food packaging, expiry dates
- **Navigation** — street signs, bus numbers, menus in foreign languages
- **Daily tasks** — identifying currency, checking if the stove is on, picking clothes
- **Documents** — reading letters, receipts, forms aloud
- **Social awareness** — how many people are in a room, what expression someone has

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| UI | Flutter (Dart) | Cross-platform mobile app |
| Vision | Camera plugin + image package | Silent rear camera capture, JPEG encoding, base64 conversion |
| STT | speech_to_text | On-device speech recognition |
| LLM | GPT-4o Vision API | Scene understanding + question answering |
| TTS | flutter_tts | Speaks responses using device TTS engine |
| Activation | Custom Android EventChannel | Hardware volume button interception for hands-free use |

## Project Structure

```
lib/
├── main.dart                          # App entry point, dotenv + wakelock setup
├── screens/
│   └── assistant_screen.dart          # Main UI + pipeline orchestration
├── services/
│   ├── hotword_service.dart           # Porcupine wake word (optional)
│   ├── stt_service.dart               # Speech-to-text wrapper
│   ├── vision_service.dart            # Camera capture + base64 encoding
│   ├── llm_service.dart               # GPT-4o Vision API calls
│   ├── tts_service.dart               # Text-to-speech wrapper
│   └── audio_feedback_service.dart    # Beep/chime audio cues
└── widgets/
    └── status_indicator.dart          # Visual state indicator
```

## Accessibility Design

This app is built **blind-first** — not as a sighted tool that helps blind people, but as something a blind person can use independently:

- **No screen interaction needed** — activate with hardware volume button
- **All state communicated via audio** — TTS announces every status change
- **Camera pre-capture** — image is taken the instant you activate, while you're still pointing the phone
- **5-second silence detection** — waits patiently for you to finish speaking
- **Concurrent processing** — STT and camera run simultaneously, not sequentially

## Setup

### Prerequisites

- Flutter SDK (3.2+)
- Android Studio (for Android SDK)
- An OpenAI API key with GPT-4o access

### Installation

```bash
git clone https://github.com/Prakharr05/visual-assistant.git
cd visual-assistant
```

Create a `.env` file in the project root:

```
OPENAI_API_KEY=your-openai-key-here
PICOVOICE_ACCESS_KEY=
```

Add permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

Set minimum SDK in `android/app/build.gradle`:

```
minSdk = 23
```

Install dependencies and run:

```bash
flutter pub get
flutter run
```

### Build APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Architecture Decisions

**Why pre-capture?** A blind user holds up their phone while asking a question. If we capture after STT finishes, they've already lowered the phone. Pre-capture grabs the frame instantly on activation.

**Why volume button?** A blind user can't find an on-screen button. The volume button is a physical key they can locate by touch, every time, on any phone.

**Why `detail: 'low'` on GPT-4o?** Faster response + lower cost. For fine print reading (medicine labels), change to `'high'` in `llm_service.dart`.

**Why no Whisper?** Flutter's `speech_to_text` uses the device's built-in speech engine (Google STT on Android), which is already fast and accurate. Whisper would require recording audio, saving a file, and running inference — adding latency for no benefit on mobile.

## License

MIT