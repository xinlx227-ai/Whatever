# S01 verification

Date: 2026-10-06, Asia/Shanghai. Scope: [Issue #2](https://github.com/xinlx227-ai/Whatever/issues/2).

## Reproducible checks

Run the commands in the repository root with Flutter on PATH:

```powershell
flutter pub get
flutter analyze
flutter test
flutter test integration_test/android_journey_test.dart -d emulator-5554
flutter build apk --release --target-platform "android-arm64,android-x64"
```

## Verified implementation

`flutter analyze` reports no issues. `flutter test` passes 23 tests: 12 application journeys backed by real temporary SQLite databases and 11 widget interaction/layout tests.

The database checks prove complete header/item rollback after an injected write failure, one complete record after post-commit acknowledgement loss and retry, repeated-confirmation exclusion during saving, UTC ordering, durable reopening, ephemeral unconfirmed rounds, accepted time boundaries, and selection access to every eligible identity. Selection uses one `Random.nextInt(pool.length)` call; animation consumes its chosen index.

Widget checks cover one explicit spin, disabled repeated actions, save retry, browsing without confirming, canceling/accepting period restarts, Back priority, abandonment during animation, reduced motion, and overflow-free layouts at 375×812 and 812×375 logical pixels with text scaled to 200%. Native screenshot inspection exposed a partly clipped confirmation button after reveal; the UI now brings the completion area into view. A 393×851 regression verifies the entire result and button remain visible after reveal and after returning from either tab without an extra manual scroll.

Independent review identified a post-commit acknowledgement edge case: the current history snapshot stayed empty if the user abandoned instead of retrying. The fix refreshes committed history on save errors while retaining the result and retry payload. Regression tests cover abandonment and period switching; review of the fix found no remaining issue.

## Workstation

- Flutter 3.47.6 stable, Dart 3.13.5, `D:/flutter`.
- Android SDK `D:/SDK`: platform 36 rev2, build tools 36.0.0, NDK 28.2.13676358.
- Java 17.0.12 at `D:/JDK`; Android licenses accepted.
- AVD `meal_app_api35`: Android 15/API 35, AOSP x86_64, emulator 35.2.10, 1080×2340 pixels, density 440. Animation scales are 1.

The Android toolchain section of `flutter doctor -v` passes. The current shell predates the user PATH update; absolute Flutter paths work. Visual Studio is absent, which only affects Windows desktop builds.

### Local repository routing

The workstation's `repo.maven.apache.org` resolution caused connection and certificate failures. The same artifacts load successfully from Maven Central's official `https://repo1.maven.org/maven2` endpoint with TLS verification enabled.

`C:/Users/27871/.gradle/init.d/whatever-official-central-routing.gradle` rewrites Central repositories for this checkout and the Flutter SDK's included Gradle build only. It also avoids Plugin Portal redirects through the affected hostname. This is workstation configuration, not a dependency-source change in the repository. After network routing is repaired, remove that file to restore the default behavior.

## Native evidence and remaining limits

`flutter test integration_test/android_journey_test.dart -d emulator-5554` passes its native UI journey after the final presentation change. It uses Android's actual SQLite plugin with a temporary database, presses public UI actions, checks exactly one confirmed record, and closes/reopens the repository and app widget before reading that same record.

Both debug and release APK builds succeeded. The final release APK was installed and launched on the API 35 emulator. Manual UI actions selected Soy milk (豆浆), confirmed it, and displayed exactly one dated history row. `adb shell am force-stop com.xinlx227.whatever` followed by launch retained the same single row. A subsequent draw without confirmation followed by force-stop/relaunch returned to the idle draw action and still showed exactly one history row. The crash log was empty.

Final artifact: `build/app/outputs/flutter-apk/app-release.apk`, 34,370,076 bytes (32.8 MiB), package `com.xinlx227.whatever`, version `0.1.0+1`, minimum Android API 24, target API 36. It includes ARM64 and x86_64 and uses the local debug signing key for review. This exact artifact was used for the final emulator checks.

SHA-256: `091BF2E7F1F02DB405F593196963FCA4962B8FA43C01428274FD8C06FC5D3BF1`.

Screenshots from the release APK: [Decide](images/s01-decide.png), [revealed result and confirmation](images/s01-result.png), [read-only library](images/s01-library.png), [confirmed history](images/s01-history.png). The wheel's pointer and visible result agree. Library content continues by scrolling; all eight options are covered by the app and native tests.

The demonstrated native path supports the [Flutter/SQLite adoption decision](../adr/0001-flutter-sqlite.md). Later v1 slices retain their independent acceptance gates.

Physical-phone haptic strength and perceived animation smoothness require phone review. Automated haptic-channel assertions establish the invocation, not physical quality. TalkBack and performance on a modest physical phone are not yet verified. The application intentionally uses the approved light palette under either system theme.
