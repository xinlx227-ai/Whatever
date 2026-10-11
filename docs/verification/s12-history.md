# S12 history verification

Implemented on `codex/issue-13-history`, based on
`30e11f45c80f28b349da6b98467f5a0f8dc30c40`, on 2026-10-11 (Asia/Shanghai).
Scope: [Issue #13](https://github.com/xinlx227-ai/Whatever/issues/13) and
[parent specification #1](https://github.com/xinlx227-ai/Whatever/issues/1).
The live blocker #5 was closed, and local/remote main matched before branching.
Changes are uncommitted; review, merge, push, branch deletion, and issue closure
remain separate delivery stages.

## Behavior

- History (足迹) starts with all scenarios, retaining the existing newest-first
  local-date groups and one row per confirmation. Its scenario filter persists
  across tab browsing for the current session independently of Decide and Library.
- A record opens an ordered, scrollable detail page with its single confirmation
  date/time, scenario, meal period, and all current option names and images.
  Restaurant addresses and notes remain visible. Soft-deleted custom options
  retain their backing data; rename/image edits appear through stable references.
- Deletion requires explicit whole-record confirmation. Success returns to the
  filtered list with feedback; a transaction failure retains the detail with a retry action.
  Cancel and Back preserve the record. There is no per-item deletion.
- Repository deletion removes items and the header in one SQLite transaction.
  Schema v8 remains unchanged; referenced options and their images are retained.
- History deletion and library writes share the controller's serialized mutation
  boundary, which waits for an active confirmation. Only an actual deletion
  invalidates unfinished results, progress, selection, pending replacement, and
  mode lock. Conditions and session exclusions survive. Existing restart feedback
  appears on returning to Decide. Missing records and failed transactions leave
  the unfinished round intact.

## Review fix: committed deletion with unreadable refreshed data

The Spec review identified a P2 failure path: deletion committed, but the
subsequent data refresh failed. The controller retained a stale record while the
UI reported only success; retrying deletion could not refresh a missing record.

Committed deletions now remove the record from the cached snapshot before
refreshing. History distinguishes successful deletion from refresh failure and
shows a persistent Retry refresh (重试刷新) action. The action retries reads only
while data is unavailable and no other operation is busy. Repeated read failures
retain the notice and keep drawing blocked; successful refresh restores drawing.
A retry after recovery is a no-op, preserving any new round and session exclusions.

The real-SQLite widget regression failed before the fix and now passes. It covers
the success notice, absent deleted row, failed refresh retry, and successful
recovery. A controller regression covers pending replacement cleanup, preserved
exclusions, and no-op retry after a new round starts. The 22 focused controller/UI
tests and static analysis pass; logs use `build/issue-13-refresh-*`.

Final validation: all 314 tests passed in `build/issue-13-refresh-tests.log`;
static analysis and tracked/staged/new-file whitespace checks passed. Independent
read-only follow-up confirmed the original P2 resolved with no remaining findings.
No new APK or native-device evidence was produced for this fix.

## Initial verification

- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --no-pub`: all 312 tests passed, including the 27 new history
  tests. Logs: `build/issue-13-analyze.log` and `build/issue-13-tests.log`.
  After the final date-heading typography adjustment, all eight light/dark,
  portrait/landscape layout and host-font capture cases passed again in
  `build/issue-13-final-layout.log`; the full suite predates that style-only change.
- Tracked, staged, and newly added file whitespace checks passed.
- The 16 new repository/controller tests use real temporary SQLite databases.
  They cover 1/3/10-item deletion and reopening, rollback at both item/header
  deletion, literal operation IDs, retained custom-option identity/image data,
  both drawing modes with pending replacement, no-op/failure preservation,
  yesterday eligibility with overlapping records, confirmation success/failure
  coordination, and queued library mutations.
- The 11 new widget tests cover ordering and date grouping, single/multiple-item
  details, independent filters and empty states, current names/images after
  rename and soft deletion, cancellation, successful whole-record deletion, and
  transaction failure followed by retry. Light/dark themes are exercised at
  375×812 and 812×375 with 2× text, reduced motion, and simulated safe insets.
- Widget persistence actions and their completion listeners run in real async
  time; the initial test failures were fixture/localization/async-harness issues.
  The corrected focused suite passes without fixed-delay polling.
- A temporary desktop capture harness loaded the host's Chinese font and Material
  icons for visual inspection in both themes and orientations at 2× text. The
  four capture cases passed; local screenshots and the capture log are under
  `build/issue-13-*`. Detail dates use a smaller heading to avoid a trailing
  day-marker orphan on a narrow screen. These host-font captures are supplementary
  local evidence, not portable golden baselines.

## Limits

Full-screen drawing hides bottom navigation. Unreachable drawing/deletion
combinations are exercised through the public controller rather than adding a
navigation exception. Widget screenshots are desktop renderer evidence, not
Android screenshots. No Android device was connected; no APK build, emulator or
physical-device journey, TalkBack, native Back/lifecycle, or iOS validation is
claimed for S12. Prior APK/device evidence predates this change.

The four pre-existing untracked card/wheel prototype files were preserved.
