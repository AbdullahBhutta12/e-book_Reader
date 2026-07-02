# E-Book Reader — Module 1

This zip contains the `lib/` source files, `pubspec.yaml`, and
`analysis_options.yaml` for Module 1 only (the Home Screen UI shell).
It is **not** a full `flutter create` output — you need to generate the
native Android/iOS scaffolding yourself, then drop these files in.

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
4. Install dependencies:
   ```
   cd ebook_reader
   flutter pub get
   ```
5. Run it on an emulator or a plugged-in Android device:
   ```
   flutter run
   ```

You should see the Home Screen: an AppBar titled "E-Book Reader", a
circular book icon, a welcome heading, and a large "Import Book" button
that shows a SnackBar when tapped.
