# E-Book Reader — Module 3

This zip contains the `lib/` source files, `pubspec.yaml`, and
`analysis_options.yaml` through Module 3 (Home Screen + Import Book +
Reader Screen that now displays actual book content for `.txt` files).
It is **not** a full `flutter create` output — you need to generate the
native Android/iOS scaffolding yourself, then drop these files in.

## What's new since Module 2
- Added `provider: ^6.1.5+1` to `pubspec.yaml` — run `flutter pub get`
  after copying these files in.
- The Reader screen now extracts and displays a `.txt` book's actual
  text instead of only showing its metadata. File metadata moved to an
  on-demand "book details" sheet (tap the ⓘ icon in the Reader screen's
  AppBar).
- `.pdf` and `.epub` files still import successfully (Module 2), but the
  Reader screen now shows an honest "not supported for reading yet"
  state for them — full support is planned for a later version.
- A sample file is included at `sample_books/the_lighthouse_keepers_notebook.txt`
  — import that one first to see the reading view working immediately.

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
