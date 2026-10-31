# Bookwave TV

An unofficial Android TV app (Flutter) that plays your Storytel audiobooks on a
Chromecast with Google TV. The UI is in Polish.

## Release signing

Create the keystore once (keep it outside the repo and back it up):

```sh
keytool -genkey -v -keystore ~/.android/bookwave-tv.jks -keyalg RSA -keysize 2048 -validity 10000 -alias bookwave-tv
```

Then create `android/key.properties` (git-ignored):

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=bookwave-tv
storeFile=/home/wisienka/.android/bookwave-tv.jks
```

Without `android/key.properties` the release build falls back to the debug keys.
If you lose the keystore you cannot update the installed app: you must uninstall
it and install the newly signed build.

## Install on Chromecast with Google TV

1. On the TV open Settings > System > About and tap "Android TV OS build" seven times to enable developer options.
2. Open Settings > System > Developer options and turn on USB debugging (network debugging on newer builds).
3. Find the TV's IP address under Settings > Network & Internet.
4. Build the APK: `flutter build apk --release`.
5. Connect and install (use the SDK's adb):

   ```sh
   ~/Android/Sdk/platform-tools/adb connect <ip>:5555
   ~/Android/Sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

6. Accept the debugging prompt on the TV the first time. The app appears in the apps row as "Bookwave TV".

Switching from a debug (or debug-signed) build to a release signed with your
keystore changes the signature, so uninstall first:
`~/Android/Sdk/platform-tools/adb uninstall com.sz3ry.bookwavetv`.

## Development

```sh
flutter pub get
flutter analyze
flutter test
```
