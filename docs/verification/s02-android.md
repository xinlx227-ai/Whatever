# S02 verification and integration contracts

Date: 2026-10-06, Asia/Shanghai. Scope: [Issue #3](https://github.com/xinlx227-ai/Whatever/issues/3), using the [parent specification](https://github.com/xinlx227-ai/Whatever/issues/1).

## Base and scope

The S02 branch is `codex/issue-3-lifecycle`, based on S01 commit `b3cf6126d98700603dd5ab730e08e50619661447`. Issue #2 remained open with stale pre-implementation text when work began; its delivered code and [S01 evidence](s01-android.md) supply the actual dependency. Implementation here does not mark that issue closed or imply a PR/merge.

The production UI remains What to eat (吃什么), Wheel (转盘), a read-only library, and confirmed history. It opens Decide (决定), uses the current local meal period, and includes the full eligible period pool. Other scenarios, category/count controls, Cards (抽卡), yesterday-filter controls, replacement, and editors retain their later slice gates. No inactive future controls are exposed. Mode and yesterday-filter storage are implemented and exercised through public controller actions; S02 does not render Cards merely because its preference is stored by a test harness.

## Public behavior and ownership

- `MealRepository` schema v2 adds one preference row. First installation and v1 migration default to Wheel with yesterday filtering off. Preference pairs are written atomically; migration retains options, periods, confirmation IDs, items, and timestamps.
- `MealController.updatePreferences` persists preferences before exposing success. It rejects changed preferences while a round is started or another operation is busy; an unchanged pair is a no-op. Later controls obtain restart consent and abandon the old round before changing conditions.
- A round starts at `startDraw`, not at a future unrevealed card selection. Its eligible pool is frozen through animation and midnight. Manual meal-period selection remains unchanged during the session. A new controller computes the current local period and loads only durable data/preferences.
- `excludeForSession` and `restoreSessionExclusions` currently operate between rounds. These public actions establish session lifetime and eligibility; S05 will supply the replacement slot transition. Confirmation, abandonment, period restart, and data invalidation retain exclusions. No round, exclusion, selected index, result, or mode lock is serialized.
- Future library mutations in any scenario and completed history deletions call `applyDataChange(changed: true)` **after the durable mutation succeeds**. Canceled edits/deletions and unchanged saves use `changed: false` (or omit the call). The controller blocks new actions, waits for any in-flight confirmation, clears the old round, reloads data, and retains one reset notice for the next Decide return. Reload failure blocks stale draws and keeps visible feedback until data is successfully refreshed.
- `MealApp` owns tab selection, dialogs, animation, and one-time feedback. All paths back to Decide expose the result/confirmation area. Data invalidation cancels the old animation. The resumed lifecycle event restores completion visibility without changing the chosen option, period, or round.
- Native `MainActivity.popSystemNavigator` moves the root task home instead of finishing the activity, preserving the live Flutter engine on the legacy Back path. Normal task removal destroys the default activity-owned engine. No background service, disk session snapshot, or custom cached engine is introduced.

## Reproducible checks

Use the existing [S01 toolchain and Gradle routing notes](s01-android.md). Run from the repository root:

```powershell
& D:/flutter/bin/flutter.bat analyze
& D:/flutter/bin/flutter.bat test
& D:/flutter/bin/flutter.bat test integration_test/android_journey_test.dart -d emulator-5554
& D:/flutter/bin/flutter.bat build apk --release --target-platform 'android-arm64,android-x64'
```

The real-process probe deliberately uses a separate `lifecycle-probe.sqlite` database and a diagnostic UI. It is not imported by the production entry point. Build/install this target only on the test emulator:

```powershell
& D:/flutter/bin/flutter.bat build apk --debug --target integration_test/lifecycle_probe.dart
& D:/SDK/platform-tools/adb.exe install -r build/app/outputs/flutter-apk/app-debug.apk
& ./scripts/verify-android-session.ps1
```

The script uses public controller actions, actual Home/Back key events, sleep/wake plus keyguard dismissal, `am force-stop`, an app-UID `SIGKILL`, and an identified AOSP recents-card swipe. It temporarily enables the emulator's swipe lock and restores the original setting in `finally`. It checks that killed processes disappear, confirms a new process on restart, and validates fresh results/exclusions/period alongside durable preferences/history. `am kill` alone was insufficient because Android declined to kill a recently visible process; it is not used as proof. Quickstep card bounds are re-read for up to three bounded swipe attempts, always targeting only this app.

After probe checks, reinstall the production release APK before reviewing the product UI:

```powershell
& D:/SDK/platform-tools/adb.exe install -r build/app/outputs/flutter-apk/app-release.apk
& D:/SDK/platform-tools/adb.exe shell am start -W -n com.xinlx227.whatever/.MainActivity
```

## Evidence

Final checks passed: `flutter analyze` (no issues), 37 tests (19 real-SQLite controller journeys, four preference/migration tests, 14 widget journeys), the expanded native Android integration journey, and the release APK build. The native integration journey uses production `MealApp` with actual Android SQLite and verifies tab returns, Continue/Abandon, one explicit durable confirmation, and reopening.

Real SQLite and widget checks cover the S01 regressions, preference defaults/reopening/atomic rollback/v1 migration, session exclusion lifetime, mode lock, no-op versus actual saved data changes, history deletion, midnight pool retention, in-flight confirmation coordination, persistent read-error feedback and recovery, dialog Back priority, lifecycle return, and cancellation of an invalidated animation.

The API 35 AOSP emulator completed the host-driven session script. [Recorded observations](evidence/s02-session.json) show:

| Event | Process | Observed state |
| --- | --- | --- |
| Prepare, Home return, lock return | 5785 | Same `noodles` result, late-night manual period, `soy-milk` exclusion, Cards/on preferences |
| Abandon and root Back return | 5785 | No round or mode lock; manual period and exclusion retained |
| Explicit confirmation | 5785 | History increased from 3 to 4; exclusions retained |
| Force-stop and relaunch | 6142 | No result/exclusions/lock; local Lunch; Cards/on and four history records retained |
| Background SIGKILL and relaunch | 6256 | Same fresh-state and durable-data guarantees |
| Actual recents swipe and relaunch | 6390 | Same fresh-state and durable-data guarantees |

The probe database accumulated three confirmations during earlier verification attempts; the final run added exactly one. `build/s02-session-evidence/` retains UI XML snapshots plus screen-off power/window evidence. The successful lock check reported `showing=true`, `mIsShowing=true`, and `screenState=SCREEN_STATE_OFF`. The original disabled-lock setting was restored after the run.

Independent review found a read-error feedback bug after period changes. The fix keeps the data-unavailable error separate from ordinary action errors; a public-action SQLite regression verifies that period changes, abandonment, and preference writes cannot hide it, and successful reload restores drawing. The reviewer verified the fix with no remaining confirmed findings.

### Production release UI

The final release APK was installed after the test-only probe and native integration run. Host-driven public UI actions and actual Android hardware events verified:

- Fresh Decide opened with the current local Lunch period and Wheel. Bottom destinations remained library, Decide, history.
- During a late-night wheel spin, Home/background for five seconds and return produced Soy milk (豆浆), with process ID 6606 unchanged. The pointer and visible result agreed, and the complete confirmation button remained visible. [Return screenshot](images/s02-result-return.png).
- Library and history root Back returned to the same result. Back opened Continue/Abandon; another Back dismissed only that dialog. Continue retained the result. A genuine keyguard lock/unlock also retained it.
- Abandon cleared the result without saving. Idle root Back returned home, and reopening retained process 6606 and the manual late-night period.
- A subsequent explicit confirmation saved exactly one Soy beverage (豆奶) record at 13:47, with the manually selected late-night period. Later force-stop/relaunch and recents removal/relaunch cleared new unconfirmed rounds and restored the current Lunch default, while retaining that same single record. [History screenshot](images/s02-history.png).
- Android's crash log was empty. UI XML observations and the local host exercise script are retained under `build/s02-release-evidence/` and `build/s02-release-check.ps1`.

Artifact: `build/app/outputs/flutter-apk/app-release.apk`, 34,435,612 bytes, ARM64 and x86_64, version `0.1.0+1`, package `com.xinlx227.whatever`. It remains signed with the local debug key for review, as in S01. SHA-256: `05F4873379FAD6EBB7EB3353739C2E4807A2370DFB27EB1EAFA82EA2B7C8459A`.

## Limits

Native lifecycle observations are from the Android 15/API 35 emulator. API 24–32 root Back is covered by the native delegate implementation and source inspection, not an additional emulator/device run. The probe exposes hidden controller state; it is separate evidence from production presentation checks. Physical-phone haptics, TalkBack, low-memory pressure initiated by the OS, and OEM-specific task management remain unverified. SIGKILL proves genuine abrupt process termination, not a measured low-memory event. Future editor/card-selection controls retain their own UI acceptance work.
