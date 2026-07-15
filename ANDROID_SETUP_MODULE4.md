# Module 4 — Required Android Configuration

`flutter_tts` needs three native Android changes. This project's zip only
ever contains `lib/`, `pubspec.yaml`, and similar generated-by-you-locally
files — the `android/` folder was created on your machine by
`flutter create` and isn't something this project ships a copy of, so
these changes need to be made by hand in your local project. None of them
are optional; skip any one and text-to-speech will either fail to build
or fail to detect an engine at runtime on real devices.

## 1. `android/app/src/main/AndroidManifest.xml` — REQUIRED

Add a `<queries>` block as a **sibling of `<application>`** (still inside
the top-level `<manifest>` tag, but after `</application>` closes):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="ebook_reader"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        ...
    </application>

    <queries>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
    </queries>
</manifest>
```

**Why:** Android 11 (API 30) introduced "package visibility" — by
default, an app can no longer see whether *other* apps (including TTS
engine apps) are installed on the device at all. Without declaring this
`<queries>` intent, `flutter_tts` can fail to detect any installed TTS
engine on Android 11+, even though one is genuinely present.

**Which Android versions require it:** Android 11 (API 30) and above.
Since current Play Store policy requires targeting recent API levels far
above 30, this is effectively mandatory for any real submission, not just
an edge case.

## 2. `android/app/build.gradle` — VERIFY (likely already fine)

Confirm `minSdkVersion` is at least 21:

```gradle
defaultConfig {
    ...
    minSdkVersion flutter.minSdkVersion   // <- confirm this resolves to >= 21
    ...
}
```

**Why:** `flutter_tts` requires API 21 as an absolute floor. Recent
Flutter SDKs already default well above this, so this is a "verify, don't
necessarily change" step — but check it explicitly rather than assume.

**Limitation regardless of this setting:** pause/resume and any future
word-boundary callbacks only work on **API 26 (Android 8.0)+** — see
Patch note in `TtsService.pause()`. This is a runtime engine limitation,
not something raising `minSdkVersion` further would fix; devices on API
21–25 will run this app fine, just without a working Pause button (see
the fallback behavior explained in the chat response).

## 3. Kotlin Gradle Plugin version — VERIFY (likely already fine)

`flutter_tts` requires Kotlin **1.9.10 or newer**. Depending on which
Flutter version generated your project, this lives in one of two places:

- **Older template** — `android/build.gradle`:
  ```gradle
  buildscript {
      ext.kotlin_version = '1.9.10'   // bump if lower
  }
  ```
- **Newer template** — `android/settings.gradle`:
  ```gradle
  plugins {
      id "org.jetbrains.kotlin.android" version "1.9.10" apply false   // bump if lower
  }
  ```

Check whichever of these two your project actually has, and only change
it if the current version is below 1.9.10.

## Nothing else changes

No new runtime permissions (like microphone or storage) are needed —
text-to-speech *output* requires none. If your app's `build.gradle`
already compiles and runs Module 1–3 successfully, changes 2 and 3 above
will very likely already be satisfied; change 1 is the one almost
certainly not already present, since nothing before Module 4 needed it.
