# S13 yesterday-filter verification

Implemented on `codex/issue-14-yesterday`, based on
`d442b1b2b7a28b2bac17c015285c858710cec9b8`, on 2026-10-11 (Asia/Shanghai).
Scope: [Issue #14](https://github.com/xinlx227-ai/Whatever/issues/14) and
[parent specification #1](https://github.com/xinlx227-ai/Whatever/issues/1).
Live blockers #12, #13, and #8 were closed. The previously authorized push of
the S12 main commit succeeded, and the remote SHA was verified before branching.
S13 changes are uncommitted. Formal issue review, commit/delivery, merge, push,
branch deletion, and issue closure have not been performed.

## Implementation

- Added the selectable Yesterday filter (昨天选过的不选) to Decide in every
  scenario and both modes, using the existing persisted preference, initially off.
  It shares a wrapping row with the category button and its candidate-count
  subtitle, preserving the normal-text portrait entry's primary-action visibility.
- Added the filter to the staged conditions sheet. The drawing-stage header now
  provides Adjust conditions (调整条件), including during a pending replacement
  when no animation is running. Canceling the sheet, applying unchanged values,
  or declining restart preserves the round and preference.
- A changed filter in a started round requires explicit restart consent.
  `updatePreferences(..., restartRound: true)` permits a same-mode filter change,
  saves it before clearing the round, and retains the current round on write
  failure. Mode switching remains locked. Successful restart keeps session
  exclusions and the manually selected period and returns to Decide entry.
- Empty-pool recovery can disable the filter through the public conditions sheet.
  Persistent deactivation and session exclusions continue to apply independently.
- Reused the existing identity-based local-calendar-day eligibility and frozen
  round scope. No schema migration, seed change, new clock service, or repository
  filtering implementation was needed.

## Acceptance evidence

| Contract | Automated evidence |
| --- | --- |
| Off by default; selection persists | Existing `preferences_test.dart` reopens real SQLite for both mode/filter values; new UI tests operate the selectable control in all scenarios and check durable preference values |
| Previous local day, across periods | New `yesterday_filter_test.dart` uses UTC clock/history values corresponding to local exact midnight boundaries, one microsecond outside/inside the interval, month/year rollover, leap and nonleap February |
| Every multi-item identity, independent scenarios/categories | New fixtures confirm a cooking batch at breakfast, filter at late night, and distinguish same-category options and same-name identities in eating and restaurant scenarios |
| Rename/restore and history deletion | New tests use public rename, soft-delete, restoration, history deletion, and database reopen; existing `history_controller_test.dart` covers repeated item references across deleted/retained records |
| Frozen round through midnight and replacements | New tests run both modes through midnight, subsequent dishes, Exclude and Redraw replacements, unique batch results, abandonment, and a newly confirmed next round |
| Independent exclusions and manual period | Frozen-scope tests retain session exclusions and manual dinner while the clock reaches late night; UI recovery keeps both inactive and session-excluded options unavailable |
| Restart consent and failure recovery | UI tests cover draft cancellation, restart cancellation, no-op apply, and confirmed apply in both modes; SQLite trigger faults retain pending replacement, results, selection and old preference until successful retry |
| Public empty-pool recovery | UI tests disable the filter through Adjust conditions in all six scenario/mode combinations and enter drawing again; controller tests separately recover via public history deletion |
| Responsive controls | Both modes at 375 x 812 and 812 x 375 with 2x text and reduced motion; controls remain reachable and the entry chip meets a 48-pixel test target |

## Validation and limits

- Targeted controller/UI/category regression run: 30 tests passed in
  `build/issue-14-targeted-tests.log`.
- Static analysis: no issues in `build/issue-14-analyze.log`.
- A first full-suite run exposed a portrait primary-action visibility regression
  from the extra filter row. The shared wrapping row fixes it without shrinking
  the artwork or loosening the existing assertion. All 25 scenario/new-filter UI
  tests then passed in `build/issue-14-layout-tests.log`.
- Independent implementation checking found that the new stage conditions
  sheet did not pause an unfinished Cards shuffle. The modal now uses the
  existing `asking`/animation-pause scope and restores it in `finally`.
  A widget regression failed before the fix (`build/issue-14-modal-before.log`)
  and now verifies stationary card positions during the sheet and resumed motion
  after cancel. All 19 filter/category UI tests passed after this fix in
  `build/issue-14-modal-tests.log`.
- Final full suite after the modal fix: all 341 tests passed in
  `build/issue-14-tests.log`; static analysis remained clean. Dart formatting and
  `git diff --check` passed. The independent read-only follow-up confirmed the
  animation finding resolved with no remaining findings.

All new persistence tests use real temporary SQLite databases and injected
clocks. Flutter commands run sequentially on native Windows. Widget checks do
not establish Android device rendering, TalkBack focus order, physical Back,
background/process-death behavior, or iOS support. No new APK or device test was
produced. There is no automatic foreground-midnight timer: eligibility is
recomputed on public actions/getters, rebuild, or resume before an unstarted
draw; an already started round intentionally retains its frozen scope.
