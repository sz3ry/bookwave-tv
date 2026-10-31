# Bookwave TV

Small Flutter app for Chromecast with Google TV (Android TV) that plays Storytel
audiobooks from the user's bookshelf. Sideloaded APK, Polish UI, no Play Store.

- Design spec: `docs/superpowers/specs/2026-10-31-bookwave-tv-design.md` (local, not committed)
- Storytel API reference: `docs/storytel-api.md`

## Commands

- `flutter analyze` - static analysis, must report no issues
- `flutter test` - unit tests
- `flutter build apk --release` - release APK
- `adb connect <tv-ip>:5555 && adb install -r build/app/outputs/flutter-apk/app-release.apk`

## Rules

- Code, comments, docs and commit messages are in English.
- All UI strings are Polish and live in `lib/l10n/app_pl.arb` (gen-l10n); never hardcode them.
- Commits: Conventional Commits, one short sentence, no AI attribution lines.
- Never log the password, the encrypted password or the jwt; secrets live only in `flutter_secure_storage`.
- The TV remote has no play/pause key: OK (select/enter) on the focused play button toggles playback.
- Do not commit `docs/superpowers/` or `.superpowers/`.
