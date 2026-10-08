# S06 cooking meals with the wheel

Scope: [Issue #7](https://github.com/xinlx227-ai/Whatever/issues/7), based on integrated S05 at `8886b71b44ccd8c68163ae48fd202ea110e0292a`. Branch: `codex/issue-7-cooking-meals`. This report covers local implementation and verification, not merge, publication, or issue closure.

## Behavior and persistence

Cooking alone exposes 1/2/3/custom 1–10 choices below category filters. A new process starts with one; current-session conditions retain the cooking count after confirmation and scenario browsing. Each explicit wheel press reveals one distinct dish in an ordered slot. Confirmation uses the actual revealed count, including early confirmation. Changing a started round's count requires restart consent; cancel and unchanged choices preserve its slots.

Eligibility freezes for the whole round, including yesterday's date boundary. Each next spin removes already revealed identities from that round only; its ordered display pool stays stable through animation so the pointer and selected index agree. Batch history contributes every option identity to yesterday filtering. Library writes retain the existing serialized mutation and invalidation boundary.

Positive shortages offer the available count or filter adjustment, with no automatic draw or eligibility relaxation. Zero candidates retain the existing condition/exclusion recovery. A confirmation attempt freezes an operation ID and immutable ordered payload; adding another dish remains disabled after ambiguous save failure until retry or whole-round reset.

SQLite remains at schema v5: its existing header and ordered-item tables already support meals. New confirmations validate 1–10 distinct cooking identities (other scenarios exactly one), same scenario, active status and period applicability. One transaction inserts one header and all items. Retry compares timestamp, period, item count, identity and position; an already committed operation acknowledges its original payload even after later deactivation. History groups items into one record and retains old single-option records, identity-based names and soft-deleted options.

The cooking completion controls stay above bottom navigation on ordinary tall portrait screens. Short screens and enlarged text use the scrollable layout. Result names and slot order remain visible while the next dish spins. History shows all names in order under one timestamp.

## Verification

Run Flutter commands sequentially on this Windows workstation; toolchain paths are in [README](../../README.md).

```powershell
& D:/flutter/bin/flutter.bat analyze
& D:/flutter/bin/flutter.bat test --reporter expanded
& D:/flutter/bin/flutter.bat test integration_test/cooking_journey_test.dart -d emulator-5554 --reporter expanded
git diff --check
```

The new repository and controller suites exercise ordered 1/2/3/10-dish records, early confirmation, first/second-item rollback, lost acknowledgement and exact retry matching, reopen and legacy coexistence, invalid/duplicate/mixed-scenario payloads, midnight eligibility, all-item yesterday filtering, count reset, and serialized library changes. A SQLite trigger rejects the second insert independently of the repository fault callback.

Widget journeys cover explicit successive draws, count visibility and range validation, canceled/accepted restart, shortage alternatives, early save, grouped history, disabled additional draws during retry, and ten-result reachability at 375×812 and 812×375 with 2× text and reduced motion. Existing single-option tests remain regressions, with cooking confirmation copy updated to the actual count.

Static analysis passed with no issues and the complete desktop suite passed all 141 tests (32 added). An initial portrait-layout regression was fixed by the adaptive cooking completion region; the subsequent 17-test batch/scenario UI run and full suite passed. Logs: `build/s06-analyze.log`, `build/s06-tests.log`, and `build/s06-ui-tests.log` (ignored local artifacts).

The API 35 emulator passed `integration_test/cooking_journey_test.dart` against native Android SQLite. The journey preserves a single-option meal beside batches, reveals two of three requested dishes, cancels a count restart, injects failure after the second item and retries, loses a successful commit acknowledgement and retries without duplication, exercises both shortage alternatives, confirms a reduced four-soup batch, displays four grouped records, and reopens the temporary database to verify ordered contents and fresh count/round defaults. Log: `build/s06-android-cooking.log`. It does not reset production data.

The full desktop and native runs above precede two presentation refinements: the cooking success notice now refers to a meal, and the cooking heading omits decorative introductory lines to make room for the count and wheel. The final 17-test batch/scenario UI run passed after both changes (`build/s06-ui-final.log`). The native journey was not repeated after these presentation-only refinements.

Independent read-only reviews reported **Standards 0 / Spec 0** across tracked and untracked changes against the baseline commit. Reviewers inspected implementation, tests and execution logs; root ran the checks and integrated the changes. Runtime permissions did not enforce read-only access, but reviewers were instructed accordingly and made no edits or Flutter calls.

The final ARM64/x86_64 release APK built and was installed without clearing app data. Visual inspection confirmed the cooking count, complete wheel, ordered results and fixed completion actions above navigation on the API 35 emulator; the crash buffer was empty. Screenshots: [count and wheel](images/s06-cooking-setup.png), [two of three dishes](images/s06-cooking-results.png). Final static analysis again passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, SHA-256 `3EA9B8D6AB0235BAAF5C45443D55240A290AD6CFFA9A7BB4C8345CCAFB87C15D`; build log: `build/s06-release-build.log`.

## Limits

No physical-device, TalkBack, low-memory, or iOS evidence is claimed. Card mode, replacement, broader history management and name recognition remain later slices. This change does not add a migration. Native integration uses a temporary database and preserves production records.
