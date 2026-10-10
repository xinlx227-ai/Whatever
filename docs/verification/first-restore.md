# First restore: shared entry and full-screen drawing

Developed on `codex/first-restore`, based on `d70ada57f941b52d759c65ee3831223541172b7c`.
The user authorized delivery on `main`, followed by commit and push, on
2026-10-10. Both branches shared the base commit, so the reviewed working changes
were carried to `main` before committing. Sections and manifests below retain
their historical verification state. Issue updates and branch deletion remain
separate delivery steps.

## Review follow-up: explicit pending state — 2026-10-10

Replaced the obsolete nullable replacement index with the boolean
`hasPendingReplacement`. The outgoing result is removed immediately, so its old
index is not a meaningful reference into the retained results. Production callers
and existing unit, widget, and native journey assertions now use pending-state
semantics. Replacement, confirmation, and animation behavior are unchanged.

Validation: `flutter analyze --no-pub`, all 257 tests, and `git diff --check`
passed. Test log: `build/first-restore-review-fix-tests.log`. Current source hashes
are in [the review follow-up manifest](first-restore-review-fix-source.json).
The release APK and device evidence below predate this refactor; no APK rebuild
or native journey rerun was performed for this internal state cleanup.

## Centered shuffle overlap correction — 2026-10-10

The user reported ghosted overlapping backs on the right during shuffle. A
14-card centered fan reproduced this on the previous release. A deterministic
frame test failed with an interior card opacity of 0.375: independent nine-card
groups placed wrap fades inside the viewport, and the final five-card group had
a different travel distance, producing an internal spacing seam.

Shuffle now uses one continuous full-deck track with matching paint order.
Travel remains 18 card steps for decks of at least nine cards (two original
nine-card laps), preserving pixel speed, timing, direction, and easing. Smaller
decks travel twice their count. Fades occur only at the full deck's outer wrap
boundaries. Integer travel ends on the same grid of identical backs; resting
identity positions resume before selection becomes enabled. No model/deck order
changes. Midpoint browsing is unchanged.

Validation: static analysis passed; all 257 tests passed, including ten focused
feedback tests. The new 14-card regression checks opaque interior cards and
uniform spacing over 40 motion frames. Existing frame tests check original travel
distance/timing, leftward direction, faded outer wrapping, fixed midpoint,
ordinary-draw browsing, pause, and reduced motion. Logs: `build/overlap-*.log`.
The initial failing regression is recorded in `build/overlap-red.log`.

The rebuilt ARM64/x86_64 release was installed on API 35 without clearing data.
Inspected actual mid-shuffle frames of the same 14-card scenario:
[before](images/first-restore-overlap-before.png) shows the right interior ghost;
[after](images/first-restore-overlap-after.png) shows continuous opaque overlaps.
These capture the same flow, not an exactly synchronized animation timestamp.
Current source/APK hashes: [overlap manifest](first-restore-overlap-source.json).
The emulator was returned to entry; no history was saved. Crash buffer was empty.
Native integration journeys and physical-device perception were not rerun.
`git diff --check` passed; changes remain uncommitted.

## Earlier shuffle direction comparison — 2026-10-10

The user requested reversing the direction to compare the perceived rhythm.
Circulation now moves right-to-left, with matching paint order. Two laps,
1800 ms initial / 700 ms replacement timing, curves, wrap fading, and fixed
midpoint browsing remain unchanged. The nine focused card-feedback tests pass,
including leftward travel and wrapping, exact completion times, no center-scroll
animation, pause, and reduced motion. This supersedes the rightward-motion
decision below. Logs for this comparison use `build/shuffle-direction-*.log`.
Static analysis and `git diff --check` passed. The release APK was rebuilt,
installed on API 35 without clearing data, and launched. Current hashes are in
[the direction source manifest](first-restore-direction-source.json). The full
suite and native journeys were not repeated for this direction-only comparison;
earlier results below apply to their recorded source. Perceived motion awaits
user comparison. Changes remain uncommitted.

## Earlier shuffle rhythm correction — 2026-10-10

The user rejected the slower one-lap shuffle below and confirmed restoring the
original rhythm while keeping left-to-right motion and centered resting browsing.
Both fan positions and paint order now use two laps again. Initial shuffle remains
1800 ms (32% spread, then circulation); replacement remains 700 ms, with the same
ease-in-out curve. Midpoint positioning still uses a layout-time jump, independent
of card motion; there is no animated scroll to the center after shuffling.

Validation: `flutter analyze --no-pub` passed; the full widget/unit suite passed
256 tests. The nine focused card-feedback tests include frame sampling for two
rightward laps, exact initial/replacement completion times, fixed midpoint during
motion and after settling, faded wrapping, both browse directions, ordinary-draw
offset preservation, pause, and reduced motion. Logs: `build/shuffle-rhythm-*.log`.
Native integration journeys and physical-device motion perception were not rerun
for this correction; native evidence below belongs to the prior source.

The ARM64/x86_64 release APK was rebuilt and installed on API 35 without clearing
data, then launched. Current source and APK hashes are recorded in
[the shuffle source manifest](first-restore-shuffle-source.json). The release APK
at `build/app/outputs/flutter-apk/app-release.apk` supersedes the earlier build.
`git diff --check` passed. All changes remain uncommitted.

## Earlier feedback correction pass — 2026-10-10

The user confirmed and authorized four follow-up corrections after inspecting
screenshots. These supersede the original manual Wheel replacement start below
and in the older GitHub issues:

- Entry artwork is initialized from the current selected mode whenever entry
  remounts. Its pager owns its controller and disables PageStorage restoration,
  preventing a restored page/scroll offset from showing Cards under Wheel labels.
- Wheel Redraw (重新抽) and Exclude it (排除它) immediately start the replacement.
  There is no separate Start replacement (开始替换) step. Cards still shuffles and
  waits for manual selection/reveal. Whole-round restart still returns to entry.
- Initial and replacement shuffles center browsing at the full deck midpoint;
  short decks center as a group. Ordinary next dishes preserve browsing position.
- Shuffle makes one clearer left-to-right arc circulation. Cards fade at wrap
  boundaries to reduce visible right-to-left jumps; reduced motion and dialog/
  background pause behavior remain supported.

Validation against this pass:

| Check | Result | Local ignored log |
| --- | --- | --- |
| `flutter analyze --no-pub` | No issues | `build/feedback-fix-analyze.log` |
| `flutter test --no-pub --reporter expanded` | 254 passed | `build/feedback-fix-tests.log` |
| API 35 combined six-mode/scenario native journey | Passed | `build/feedback-fix-android.log` |
| API 35 replacement native journey | Passed | `build/feedback-fix-android.log` |

New regressions cover both entry modes after switching and leaving an unfinished
stage; automatic Redraw/Exclude in all scenarios; same-sample continuation and
retained confirmation during automatic replacement; initial/replacement fan
midpoint, both browse directions, ordinary-draw offset preservation, short-fan
centering, rightward movement/faded wrapping, pause, and reduced motion. Existing
small-screen, landscape, and large-text tests also pass. Both native journeys
use isolated databases; their confirmation checks do not add production history.

Release ARM64/x86_64 APK rebuilt and installed without clearing app data:
`build/app/outputs/flutter-apk/app-release.apk`. Exact source/artifact SHA256
identities are in [the feedback source manifest](first-restore-feedback-source.json).
Build log: `build/feedback-fix-release.log`. `git diff --check` passed.

Release UI checks on API 35 verified Wheel exit back to matching entry artwork,
Redraw immediately showing the enlarged spinning Wheel, the centered resting
fan, and browsing from that midpoint to both ends. Inspected a mid-shuffle frame
and resting frame; directional movement/fade behavior is additionally covered
by frame-based widget tests. No production history was saved or library edited.
The emulator is left at Cards entry; the Android crash buffer was empty.

Inspected screenshots: [Wheel entry](images/first-restore-feedback-wheel-entry.png),
[automatic replacement](images/first-restore-feedback-auto-replacement.png), and
[centered fan](images/first-restore-feedback-card-center.png).
Physical-device, TalkBack, iOS, and OS low-memory behavior were not verified.

The original verification and screenshots below describe the prior build, whose
APK at the same build output path has now been superseded.

## Accepted scope and authority

The confirmed implementation handoff dated 2026-10-10 supersedes the older
layout and replacement criteria in Issues #1, #9, #10, and #11. Those issues
were read but not edited. This implementation includes both the shared redesign
and multi-target Cards collection/replacement; it does not defer #10/#11.

- All scenarios share the entry structure. Only the wheel/deck region pages
  between modes, with clickable mode names and indicators. The mode preference
  persists. Full-screen drawing hides conditions and bottom navigation.
- Cards uses the unchanged celestial back, a large central card above the lower
  browsable fan, initial spread/arc circulation, and a shorter replacement
  shuffle. Ordinary next draws preserve remaining identities and order.
- Target-one Cards remains central. Target-many Cards collects into a horizontal
  row and reopens without adding a result. Revealed central cards are included
  in confirmation even before collection. Collection has a short pausable
  travel/shrink transition; reduced motion preserves the manual steps.
- Wheel samples a candidate uniformly before mapping it to a deterministic
  display sector. Display grouping does not weight probability. The wheel has
  at most 18 sectors, a fixed center pointer, restaurant-type/food/neutral art,
  and approximately one-third mystery sectors only for pools of at least ten.
  Each next dish starts manually and focuses the newly revealed result.
- Valid replacement removes the outgoing result immediately. Retained dishes
  compact; the replacement appends. Alternative preflight, possible Redraw
  recurrence, session exclusion lifetime, and uniqueness remain intact.
- Pending replacement can open an explicit retained-meal decision when at least
  one revealed result remains. Confirming that decision discards any sampled,
  unrevealed replacement and saves only the retained meal. Save failure keeps
  that chosen reduced payload for idempotent retry; zero-result confirmation
  is unavailable.
- Back and restart require whole-round discard consent, then return to entry
  with conditions and session exclusions preserved. Successful saving also
  returns to entry. Dialogs and backgrounding pause draw, shuffle, collection,
  and wheel-size animations without resampling.
- SQLite v7 adds a separate collection-tutorial completion flag. Existing v6
  base-tutorial completion remains intact, while the new collection step can
  teach returning users. Skip marks both tutorials complete. Migration preserves
  options, categories, history, and preferences; stale preference writes cannot
  reactivate completed guidance.

## Original implementation verification

Original implementation checks passed against the source identified by the
[source manifest](first-restore-source.json). No production code changed after
the native journey or release build; subsequent changes only strengthened
test assertions and finalized this report. Logs are local ignored files under
`build/first-restore-*.log`.

| Check | Result | Log |
| --- | --- | --- |
| `flutter analyze --no-pub` | No issues | `first-restore-analyze.log` |
| `flutter test --no-pub --reporter expanded` | 242 passed | `first-restore-tests.log` |
| Android API 35 `first_restore_journey_test.dart` | Passed, native SQLite | `first-restore-android.log` |
| ARM64/x86_64 release APK | Built and installed without clearing app data | `first-restore-release.log` |
| `git diff --check` | Passed | Terminal output |

The automated coverage includes all scenarios and modes; target one versus
many; full fan reachability and selection continuity; stable uniform sampling
and display mapping; collection/reopen without duplicate results; replacement
preflight, redraw recurrence, exclusion, compact/append ordering, and shortage;
pending confirmation while waiting and during reveal; zero-retained prohibition;
unchanged sampled choice after pause; rollback and missed-acknowledgement retry;
v6-to-v7 data preservation; small portrait/landscape viewports and 2x text;
reduced motion; and collection interruption by backgrounding, save, and reset.

The Android journey uses an isolated temporary database. It completes all six
scenario/mode combinations, multi-target Cards collection, retained-meal
confirmation, injected missed acknowledgement with exactly-once retry, and
database/controller reopening. Five earlier integration journey sources were
adapted to the new navigation/replacement contracts but were not rerun in this
turn; the new combined journey is the native evidence for this redesign.

Independent review identified four P2 issues: collection guidance missing for
returning single-card users, reduced-motion spin, wheel sizing continuing behind
dialogs, and missing collection travel. All were fixed and re-reviewed without
remaining actionable findings. Read-only review restrictions were instructional;
the subagent runtime did not enforce a filesystem sandbox.

## Original release and visual inspection

Artifact: `build/app/outputs/flutter-apk/app-release.apk`.
SHA-256: `8E38DDF79E57C678DE36A3B8A693ACBEF37226692950EE376C6D9601E1253D03`.

Inspected actual release screenshots on the API 35 emulator:
[Wheel entry](images/first-restore-entry-wheel.png),
[Cards entry](images/first-restore-entry-cards.png),
[Wheel result](images/first-restore-wheel-result.png),
[lower fan](images/first-restore-card-fan.png),
[central card result](images/first-restore-card-result.png), and
[collected card row](images/first-restore-card-collected.png).
The collected-row screenshot intentionally shows the vertically scrolled stage.
Cooking's additional settings or results can require scrolling on constrained
viewports; artwork, names, and touch targets retain their size. Back remains
fixed above the scrolling stage, and confirmation scrolls with content.

Manual release checks used system Back to leave an unfinished result, drew and
collected a cooking card, verified Home/return preserved that live meal, and
verified actual `am force-stop`/relaunch reset it to the entry while retaining
Cards preference. No manual history confirmation or library mutation was made.
The emulator crash buffer was empty after these checks.

Historical S08 screenshots/APKs and the browser prototypes are design references,
not evidence for this production redesign. Native emulator evidence does not
establish physical-device, TalkBack, iOS, or OS low-memory behavior.
