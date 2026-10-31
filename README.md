# Bookwave TV

An unofficial Android TV app (Flutter) that plays your Storytel audiobooks on a
Chromecast with Google TV. The UI is in Polish.

## Install on the TV

1. On the TV open Settings > System > About and tap "Android TV OS build" seven times to enable developer options.
2. Open Settings > System > Developer options and turn on USB debugging (network debugging on newer builds).
3. Find the TV's IP address under Settings > Network & Internet.
4. On your computer, build the APK: `flutter build apk --release`.
5. Connect and install:

   ```sh
   adb connect <tv-ip>:5555
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

6. Accept the debugging prompt on the TV the first time. The app appears in the apps row as "Bookwave TV".

## Development

```sh
flutter pub get
flutter analyze
flutter test
```
