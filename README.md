# E-Book Reader — Module 4

This zip contains the `lib/` source files, `pubspec.yaml`, and
`analysis_options.yaml` through Module 4 (Home Screen + Import Book +
Reader Screen with actual book content AND working Play/Pause/Stop
text-to-speech). It is **not** a full `flutter create` output — you need
to generate the native Android/iOS scaffolding yourself, then drop these
files in.

## What's new since Module 3
- Added `flutter_tts: ^4.2.5` to `pubspec.yaml` — run `flutter pub get`
  after copying these files in.
- **Required Android configuration** — see `ANDROID_SETUP_MODULE4.md` in
  this zip. One change (`AndroidManifest.xml`) is almost certainly not
  already present in your project; the other two are worth a quick check.
- The Reader screen now shows a Play / Pause / Stop control bar at the
  bottom whenever a `.txt` book's content is loaded, and reads it aloud
  using the device's native TTS engine.
- Word/sentence highlighting is intentionally NOT part of this module —
  that's Module 5.

## How to run this on your machine

1. Make sure the Flutter SDK is installed: `flutter --version`
2. Create a fresh Flutter project:
   ```
   flutter create ebook_reader
   ```
3. From this zip, copy into the newly created `ebook_reader/` folder,
   overwriting when prompted:
   - `pubspec.yaml`
   - `analysis_options.yaml`
   - the entire `lib/` folder
   - the entire `assets/` folder
4. Apply the Android changes described in `ANDROID_SETUP_MODULE4.md`.
5. Install dependencies:
   ```
   cd ebook_reader
   flutter pub get
   ```
6. Run it on an emulator or a plugged-in Android device:
   ```
   flutter run
   ```

Import the included sample book, then use the Play/Pause/Stop bar at the
bottom of the Reader screen to hear it read aloud.
