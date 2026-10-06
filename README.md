# Whatever — Warm meal

Android-first meal decisions. S01 opens What to eat (吃什么), draws one of eight accepted options with a wheel, and saves an explicitly confirmed choice to local SQLite history. The library is read-only in this slice.

## Scope

- [Product specification and slice map](https://github.com/xinlx227-ai/Whatever/issues/1)
- [S01 acceptance criteria](https://github.com/xinlx227-ai/Whatever/issues/2)
- [Domain language](GLOSSARY.md)
- [Selected visual treatment](docs/design/warm-meal.md)
- [Verification evidence and workstation notes](docs/verification/s01-android.md)

Later slices retain all three scenarios, card mode, replacements, and editable libraries. The browser comparison under `prototype/visual-directions/` is historical design material; variant A is selected. Its adjustable preview controls are not application settings.

## Run and verify

Install Flutter stable and the Android SDK, accept Android licenses, and provide a booted Android emulator or connected phone. This workstation uses Flutter at `D:/flutter`, Android SDK at `D:/SDK`, and JDK at `D:/JDK`; other machines can use their own paths.

```powershell
$env:Path = "D:\flutter\bin;D:\SDK\platform-tools;" + $env:Path
flutter pub get
flutter analyze
flutter test
flutter test integration_test/android_journey_test.dart -d emulator-5554
flutter run -d emulator-5554
```

Launch the local emulator without a separate console window:

```powershell
Start-Process 'D:/SDK/emulator/emulator.exe' -WindowStyle Hidden -ArgumentList '-avd','meal_app_api35'
```

Create an APK for phone review:

```powershell
flutter build apk --release --target-platform "android-arm64,android-x64"
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk` and supports ARM64 phones and x86_64 emulators. S01 review builds use the local debug signing key; configure release signing before store distribution. Tests remove their temporary databases. Production records use the app-private `whatever.sqlite` database and survive process restarts.

## Implementation boundaries

- `lib/domain/meal.dart`: accepted identities, meal periods, and confirmation data.
- `lib/application/meal_controller.dart`: eligible selection and temporary round state; animation cannot influence probability.
- `lib/data/meal_repository.dart`: SQLite schema and atomic, idempotent confirmation. Fault seams simulate rollback after a header write and lost acknowledgement after commit.
- `lib/presentation/`: Chinese UI, responsive layout, animation, navigation, and feedback.
- `test/`: real SQLite application journeys and widget interaction checks.
- `integration_test/`: native Android draw-to-durable-history smoke journey.

Unconfirmed rounds remain in memory. Confirmation fixes an operation ID and payload before writing; retries reuse them, preventing duplicate records after lost acknowledgements. The database stores UTC instants and the UI groups records by local calendar date.
