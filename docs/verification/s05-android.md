# S05 category management and combined filters

Scope: [Issue #6](https://github.com/xinlx227-ai/Whatever/issues/6), based on completed S04 at `87e3bf97ccf595871ffa069e34e583ffec1a73a1`. Working branch: `codex/issue-6-categories`. This report describes local implementation; it does not record merge, publication, or issue closure.

## Persistence and session behavior

SQLite v5 adds a scenario-scoped category registry with stable category identities, built-in protection, and one retained fallback per scenario. The v4 migration retains existing option identities, labels and memberships, display edits, images, status, periods, preferences, and history. Legacy labels become registered custom categories. Older schema upgrades still run their existing content migrations first.

Option membership storage retains its label-based representation. Category rename updates the registry, primary labels, and secondary memberships in one transaction; custom-category deletion moves memberships to the current fallback label. Both operations include soft-deleted options so restoration and history remain coherent. Built-in categories, including the fallback, can be renamed but cannot be deleted. New options resolve an omitted category to the current fallback. All (全部) is a filter and cannot be created or assigned as a new category.

Decide stores selected category IDs for the current scenario. An empty selection means All. Switching scenario resets category filters to All and retains the shared meal period. Rename retains selected IDs; deleting a selected category follows its options to the scenario fallback. Fresh controller initialization selects All. Custom options retain exactly one membership; built-in memberships remain read-only in the option editor.

The filter sheet stages category and period edits until Apply. Closing the sheet, canceling restart consent, or applying unchanged conditions preserves an unfinished round. A changed saved category in any scenario goes through the same serialized mutation boundary as option edits, waits for pending confirmation, refreshes data, and invalidates unfinished results with feedback. Invalid and no-op mutations preserve results.

Candidate filtering iterates unique option records and tests whether any selected category matches. Multiple matching memberships do not create additional candidates or selection probability. The zero-candidate view offers condition adjustment and session-exclusion restoration; restoration preserves category/period filters and persistent deactivation.

## Verification

Run Flutter commands sequentially on this Windows workstation (tool paths are in [README](../../README.md)):

```powershell
& D:/flutter/bin/flutter.bat analyze
& D:/flutter/bin/flutter.bat test --reporter expanded
& D:/flutter/bin/flutter.bat test integration_test/category_journey_test.dart -d emulator-5554 --reporter expanded
& D:/flutter/bin/flutter.bat build apk --release --target-platform 'android-arm64,android-x64'
git diff --check
```

The full desktop suite passed all 109 tests, including 21 new category tests. Coverage includes exact v4 migration/reopen, built-in primary/secondary membership rename, custom category deletion with inactive/deleted options and retained history, rollback injection, normalized/reserved names, cross-scenario invalidation, no-op preservation, confirmation/write serialization, duplicate-free union selection, canceled filter drafts/restart, and empty recovery without reactivation. The deterministic random-index test visits every index in an overlapping union and checks that each eligible identity is drawn exactly once; it is not a statistical randomness claim.

Filter tests cover 375-by-812 portrait and 812-by-375 landscape at 2x text with reduced motion and long category names. Existing scenario tests still verify portrait primary-action visibility above navigation and both orientations at 2x text. Category management tests cover creation defaulting to eating independently of the library scope, custom deletion confirmation/cancel, no-op rename, renamed fallback, and persisted editor categories.

The native S05 journey passed on the API 35 emulator using Android SQLite and a temporary database: create category, add a classified option, rename category and fallback, filter/draw/confirm, cancel then confirm custom-category deletion, draw and confirm through the retained fallback, inspect two history records, and reopen the database to verify retained identities and categories. It does not clear production records. Log: `build/s05-android-category.log` (ignored local artifact).

Independent review reported no actionable correctness/spec or standards findings after examining the integrated code, formal issues, and desktop test results. The reviewer used read-only instructions; runtime permissions did not technically restrict writes, and no edits or Flutter commands were made by the reviewer. Root owns the native run and final verification.

Final static analysis passed with no issues. The supplementary six-test category-management run passed after adding the 700-by-375 landscape assertion at 2x text. `git diff --check` passed. Logs are ignored local files: `build/s05-analyze.log`, `build/s05-tests.log`, and `build/s05-management-final.log`.

The release APK built successfully for ARM64 and x86_64, was installed without clearing app data, and received visual inspection on the emulator. Decide retains the primary action above navigation; category filters, selected states, the Apply action, and management controls are visible with safe-area clearance. The Android crash buffer was empty. These screenshots show the final release:

- [Decide](images/s05-decide.png)
- [Category filters](images/s05-filters.png)
- [Category management](images/s05-management.png)

Artifact: `build/app/outputs/flutter-apk/app-release.apk`, 38,440,122 bytes. SHA-256: `D3C3294C2094593B2229DCE74447E6606654E733BBBAE35FD79D0F65546C4DB2`. Native integration passed before the final brace-formatting-only controller adjustment; the final release was then rebuilt and visually inspected. No behavior changes followed the successful native journey.

## Limits

Native validation is on an API 35 emulator, not a physical phone. The schema migration/failure cases run against real desktop SQLite; the Android journey starts a fresh temporary database and reopens it. Earlier native scenario/library/lifecycle/photo-picker matrices were not rerun for this slice; the full desktop regressions passed. No TalkBack, low-memory-pressure, physical haptic-quality, or iOS claim is made. The app retains its existing light theme and local debug signing key for review builds. Cooking batches, card mode, replacements, and recognition remain separate slices.
