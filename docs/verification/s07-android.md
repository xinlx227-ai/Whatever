# S07 wheel result replacement

Scope: [Issue #8](https://github.com/xinlx227-ai/Whatever/issues/8), based on integrated S06 at `5b3def3193341078d653c6d2fe4736b93d1c037e`. Branch: `codex/issue-8-wheel-replacement`. This report covers local implementation and verification; merge, push and issue closure remain separate delivery actions.

## Behavior

Every revealed wheel result offers Replace (换一个), including single-result scenarios and any position of a partial or full cooking meal. Both Redraw (重新抽) and Exclude it (排除它) require a distinct alternative after removing the other meal results. When none exists, the dialog explains the shortage and retains the current result and exclusions; Back dismisses it.

Redraw returns the outgoing identity to the replacement pool, so it may recur. Exclude it removes that identity for the running app session. Both shuffle the complete replacement pool and wait for another explicit start. The original slot shows a pending placeholder until its replacement is revealed. Other slots keep their order; another replacement, additional dishes and confirmation remain locked while pending. Whole-round condition changes and abandonment retain their existing consent and exclusion semantics.

Replacement uses the round's frozen eligibility, including its date boundary, with current session exclusions. Browsing preserves pending state; durable library changes invalidate it, while canceled edits and no-op saves preserve it. Confirmation freezes the final ordered payload and operation ID; replacement cannot change a payload awaiting retry. Session exclusions survive confirmation and whole-round resets, and restoration leaves persistent deactivation intact. Fresh controllers clear pending results and exclusions. SQLite stays at schema v5.

## Verification

Run Flutter checks sequentially on this Windows workstation; toolchain paths are in [README](../../README.md).

```powershell
& D:/flutter/bin/flutter.bat analyze
& D:/flutter/bin/flutter.bat test --reporter expanded
& D:/flutter/bin/flutter.bat test integration_test/replacement_journey_test.dart -d emulator-5554 --reporter expanded
git diff --check
```

The complete desktop suite passed **171 tests**, including 20 new controller cases and 10 new widget journeys (`build/s07-tests.log`). Controller coverage includes partial/full batches, all three scenarios, outgoing-item recurrence, every replacement candidate remaining selectable, exclusion lifetime and restoration, frozen midnight scope, no-op versus durable mutations, immutable snapshots, write rollback and lost acknowledgement retry. Widget journeys cover explicit starts, pending navigation, shortage actions and Back, reset consent, and ten-slot replacement in 375×812 portrait and 812×375 landscape at 2× text with reduced motion.

Independent read-only Standards and Spec reviews included tracked and non-ignored untracked changes against the baseline. Standards reported zero findings. Spec found one misleading Back warning: a replacement shortage was being described as an uncertain prior save. The fix gates that message on an actual confirmation attempt, and all three scenario shortage tests now exercise the second Back prompt. The reviewer verified the Back-warning fix. A subsequent issue review found a second P2: excluding a result during a partial cooking batch could exhaust the remaining candidates without explaining why the next draw was disabled. Review restrictions were given by instruction, not enforced by runtime permissions.

After the review fix, all **24 replacement and existing UI journey tests** passed (`build/s07-ui-final.log`), and static analysis reported no issues (`build/s07-analyze.log`).

The API 35 native journey passed against Android SQLite both before and after the review fix (`build/s07-android-replacement.log`, `build/s07-android-replacement-final.log`). It draws three of four custom dishes, redraws the middle slot, leaves and returns to a pending replacement, excludes the first slot, exercises both impossible choices and both Back prompts, retries a lost acknowledgement without duplicating the final ordered record, then draws a subsequent round without the excluded identity. Reopening the temporary database verifies retained order and fresh-controller session defaults. The final native run includes the second Back warning regression. This native run predates the subsequent active-batch shortage feedback fix described below.

The ARM64/x86_64 release APK built successfully and was installed on the API 35 emulator without clearing production data (`build/s07-release-build.log`). Visual inspection confirmed the [replacement choices](images/s07-replacement-choice.png) and [pending original slot with explicit start and disabled conflicting actions](images/s07-replacement-pending.png). Native Home/background return retained the pending replacement. An actual `am force-stop` followed by launch cleared the unfinished round and restored fresh defaults; reselecting cooking/lunch showed the original 20-candidate pool and count one, with session exclusions cleared. The Android crash buffer was empty. This manual journey made no history confirmation or library mutation.

Pre-shortage-fix APK: `build/app/outputs/flutter-apk/app-release.apk`. This artifact and the screenshots above predate the active-batch shortage feedback fix. SHA-256: `5BE9FEC086370A9643DBD9C40F6E16347B5B44CDD71D7BFCAED1FEA52149EC4C`. All execution logs under `build/` are ignored local artifacts. Formatting and `git diff --check` pass.

## Active-batch shortage follow-up

The subsequent P2 is fixed in presentation: a partial cooking batch whose remaining candidates cannot fill the requested count displays the remaining count and explains early confirmation or condition adjustment. The adjustment action reuses the existing filter sheet and restart consent. Requested count and session exclusions remain unchanged until an explicit user action. Pending replacement, drawing, saving and confirmation retry suppress this advice; the existing save feedback takes precedence. The feedback is scrollable and exposed as a live region.

Four new widget regressions reproduce a three-candidate, three-requested meal exhausted by exclusion after two draws. They verify ordered early persistence in portrait and landscape at 2x text, filter-sheet dismissal/no-op/canceled restart/confirmed restart, and a lost-acknowledgement retry with exactly one record. The replacement, batch and existing UI journey suites passed **34 tests** (`build/s07-shortage-ui.log`); static analysis passed (`build/s07-shortage-analyze.log`), as did formatting and `git diff --check`. These checks cover the current feedback change; no new Android run or APK build was performed for this follow-up. The original Spec reviewer independently verified the fix and reported no remaining findings in the scoped follow-up; review was read-only by instruction rather than runtime enforcement.
## Limits

Automated native journeys use temporary databases and preserve production records. The controller-recreation test and manual emulator force-stop check are distinct evidence; neither establishes low-memory process recovery. No physical-device, TalkBack, low-memory or iOS evidence is claimed. The current wheel theme is light-only; dark/card theme verification remains outside this slice. Card replacement remains a later slice.
