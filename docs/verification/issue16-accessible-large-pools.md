# Issue #16: accessible drawing with large candidate pools

Implementation branch: `codex/issue-16-accessible-large-pools`.
Baseline: `73d85bd2e94350d2c6ea6e6abb34026a29f9b9b9`.
Date: 2026-10-13, Asia/Shanghai.

## Current acceptance decision — 2026-10-14

The user accepted ordinary-scale manual phone use after the UI cleanup and
explicitly deferred the remaining emulator frame-performance optimization.
Under this revised scope, the functional implementation is accepted; the original
frame thresholds are no longer a gate for this slice. Their measured result
remains failed (82/384 windows passed), not waived into a numerical pass.
Input and sampled memory checks passed in the historical release matrix.
Commit, merge, push and tracker closure remain separate delivery steps.

The latest user-approved UI cleanup removes visible Cards tutorials and redundant
rule explanations while retaining accessibility action hints, errors, destructive
confirmations and online consent. The current isolated APK is
`build/issue16/whatever-issue16-phone-20261014.apk`, SHA256
`BCD7B67334345603A609D59BD7EF2E19A53971BAB1C4890F1ADEEA53AB77545F`.
Its package is `com.xinlx227.whatever.verification`, labeled “这一餐·验证”.
The latest 45 related UI tests and static analysis passed; logs are
`build/issue16/ui-copy-tests.log` and `build/issue16/ui-copy-analyze.log`.
The isolated build passed in `build/issue16/ui-copy-phone-isolated.log`.
The earlier 446-test suite, native checks and performance matrix belong to the
pre-cleanup build; they were not rerun as a full suite/matrix for this APK.

The user reported no remaining issues in ordinary phone use. This is subjective
manual experience evidence, not a per-item certification of maximum font/display
scaling, physical TalkBack gestures/speech or physical-device performance.
Review against local main found no confirmed production blocker; its one P3
finding concerned stale documentation, reconciled by this update.

### Deferred performance work

Resume only as separately requested follow-up work. Use the preserved
[measurement protocol](issue16-measurement.md) and
[rendering diagnosis](issue16-rendering-diagnosis.md) as starting evidence.
Investigate intermittent frame submission latency and environment variability;
validate any proposed diagnostic environment or metric before adopting it.
Keep the original results and baseline identifiable. A separate API 35 emulator
remains a proposal, not an approved or completed environment change. All automated,
smoke and stress work remains emulator-only. This follow-up has no deadline and
is not a prerequisite for the revised Issue #16 functional acceptance.

## Historical implementation and measurement evidence

The following results describe the original pre-cleanup implementation and its
subsequent diagnostic runs. The current decision above supersedes historical
next-step recommendations and statements that performance blocks this slice.

## Authority and delivery boundary

The user authorized implementation from the approved 2026-10-13 Issue #16
handoff. That approval replaces the live issue's physical performance wording
with emulator-only stress and smoke testing. The OnePlus 9RT remains an
ordinary-scale manual check, using a separate installation identity.
No merge, push, issue publication/editing/closure, or branch deletion is included.

## Changes

- Cards constructs the visible fan and a small cache through a horizontal sliver.
  The unchanged controller retains the full logical deck, identities, order and
  off-screen selection. Every candidate remains reachable without pagination or
  substitute random selection.
- Independent overlapping-card touch strips are 48dp. The raised selected card's
  entire face remains tappable, and drags beginning on that face still scroll.
  Shuffle timing, direction, two-lap rhythm and midpoint behavior remain intact.
  The spacing adjustment increases an 18-slot travel from 792 to 864 logical
  pixels; the celestial back asset is unchanged.
- Hidden cards expose position, count and selection without disclosing the option
  name. Accessibility focus alone does not select; successive activations select
  and reveal. Revealed results request accessibility focus. Collected result
  actions expose the complete name and selected state. Wheel exposes count and
  meaningful drawing/result states without narrating decorative sectors.
- Result names wrap, result rows remain horizontally scrollable, and stage action
  buttons wrap at large text sizes. Reduced motion preserves manual steps and
  skips the wheel's decorative settle animation.
- Display image decoding bounds both dimensions and protects the short side of
  extreme aspect ratios to at least one pixel. Validation decoding is likewise
  bounded. Persisted original bytes and source-gallery files are not rewritten.
- An opt-in Gradle `verificationBuild=true` builds the independent Android package
  `com.xinlx227.whatever.verification`, labeled “这一餐·验证”. The default package
  and label are unchanged.

## Verification status

For the pre-cleanup build, static analysis passed and the full unit/widget suite
passed **446 tests**.
Latest logs: `build/issue16/analyze-optimized.log` and
`build/issue16/all-tests-optimized.log`. These include the final per-build
eligibility reuse optimization: visible cards share one `canDraw` computation
instead of each recomputing the complete eligible pool.
The coverage includes all 1,000 logical slots through semantic system scrolling,
focus versus activation, selected-card off-screen continuity, real overlap
coordinates including the raised right edge, scrolling without reveal, ten full
names and actions at 2x text in both orientations, semantic replacement and
exactly-once confirmation/history, and extreme/invalid image fallbacks.

Independent review identified selected-face hit routing, zero-sized short-side
decodes and an input-probe timestamp mismatch. Production fixes and regressions
passed; static re-review found no remaining confirmed production defect. The
reviewer's read-only restriction was instructional, not runtime-enforced.

The native Android integration journey passed in debug mode on the selected
emulator, covering all six scenario/mode combinations, collection, retained
confirmation, missed-acknowledgement retry and reopen. Log:
`build/issue16/native-journey.log`. Flutter does not support `flutter test
--release`; release acceptance uses the standalone production-widget probe.
The release matrix is complete: 54 runs and 128 full journeys. Input feedback,
input correctness and sampled memory checks passed. The rendered-frame target
failed under the original acceptance scope. See the measured results below and
the current revised acceptance decision above.

Native accessibility checks used a separate Java instrumentation observer with
`UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES`. Its snapshots confirm
TalkBack stayed bound with touch exploration enabled. On 1,000-option fixtures,
Android node actions verified focus without selection, first activation selecting,
second activation revealing, a real `TYPE_VIEW_ACCESSIBILITY_FOCUSED` event on
the central full result, horizontal system scrolling without selection/reveal,
exclusion replacement, confirmation, history/detail opening, collection and
reopening with native selected state. Wheel exposed its 1,000 candidate count,
drawing state and complete restaurant branch result with accessibility focus.
Evidence: `build/issue16/a11y-helper/*.jsonl`.

These checks used 2x system font and density 550 (baseline 440); portrait and
landscape content remained scrollable. Screenshots are under `build/issue16/`.
The reduced-motion multi-card check additionally set Android's
`transition_animation_scale` to zero, the setting Flutter actually observes;
`animator_duration_scale=0` alone does not establish reduced motion. All three
animation scales, density, text and orientation were restored before performance
runs, and TalkBack was disabled.

Native node actions exercise the Android accessibility bridge with TalkBack
active; they are not physical TalkBack gestures or a listening assessment.
ADB `input tap` bypasses touch exploration on this setup and was not counted as
TalkBack gesture evidence. Complete 1,000-slot traversal, ten-result layouts,
filter-empty recovery and first/middle/last replacements additionally have
unit/widget evidence; the manual phone checklist retains touch and speech QA.

## Measurement environment and evidence

Use the [frozen measurement protocol](issue16-measurement.md) for methods,
thresholds, fixtures, repetitions and limitations. The primary frame metric is
release engine `totalSpan` (vsync to raster finish), with component durations and
raw display-layer evidence retained separately. Input evidence and sampled PSS
must retain their documented coverage limits.

### Final release matrix

The tested APK is `build/issue16/final-optimized-probe.apk`, SHA256
`18B52485F14DC9F706EAABB6CC0A4ABFEB84AAE0E995C001F207E6C2C0CE4983`.
`build/issue16/final-matrix-summary.json` verifies all 54 unique expected cases
and aggregates these four evidence directories:

- `restarted-cards-50`: three 50-option/default-art Cards runs.
- `matrix-wheel-50-default`: three matching Wheel runs.
- `matrix-50-photos`: twelve 50-option runs with 50%/100% photos.
- `matrix-200-1000`: thirty-six 200/1,000-option runs, all photo tiers and modes.

Every case has first-entry and repeated journeys. The 1,000-option/all-photo
run 1 in each mode adds ten retained journeys, for 128 journeys in total.
All 512 graded inputs have valid Android-event/frame-number joins and complete
feedback within 100 ms; the maximum was 73.051 ms. All journey invariants passed:
browsing did not select/reveal, exclusion replacement changed the stable ID,
confirmation added exactly one history record, and history detail remained
reachable. All 256 tab navigations succeeded on their first attempt; the bounded
navigation retry path was not needed in this matrix.

All 54 PSS series contain valid samples from the corresponding single process.
The maximum sampled PSS was 116.85 MiB. After warm-up and ten additional journeys,
resting growth was 6.26 MiB for Cards and 6.84 MiB for Wheel, below the 50 MiB
limit. These are one-second sampled emulator PSS figures, not continuous peak
measurements or physical-device guarantees.

| Pool | Mode | Runs | Graded inputs | Maximum feedback (ms) | Sampled peak PSS (MiB) | Frame windows passing both budgets |
| --- | --- | --- | --- | --- | --- | --- |
| 50 | Cards | 9 | 90 | 73.051 | 103.86 | 38 / 72 |
| 50 | Wheel | 9 | 54 | 36.289 | 100.78 | 12 / 36 |
| 200 | Cards | 9 | 90 | 40.531 | 103.50 | 26 / 72 |
| 200 | Wheel | 9 | 54 | 37.626 | 102.00 | 6 / 36 |
| 1,000 | Cards | 9 | 140 | 48.057 | 116.85 | 0 / 112 |
| 1,000 | Wheel | 9 | 84 | 49.587 | 116.42 | 0 / 56 |

**Frame acceptance failed:** only 82 of 384 entry/browse/reveal/replacement
windows meet both frozen total-span budgets. Confirmation/history windows are
diagnostic and excluded from this count. Every relevant window's build-time
p95 is below 16.67 ms (maximum 15.802 ms), but only 105 windows have raster-time
p95 below that limit (maximum 46.438 ms). The remaining issue is rasterization
and pipeline waiting; these timings do not identify the exact engine/driver
cause or establish compositor presentation. Since cases ran in ascending pool
order, differences between tiers alone do not prove pool-size causation.

A diagnostic APK isolated static card backs and the wheel rotor with inner
repaint boundaries. Its two largest-pool release journeys remain in
`build/issue16/repaint-comparison`; source variants, hashes and build logs are in
`build/issue16/repaint-experiment`. Cards browsing p95 remained 52.510/56.077 ms,
and Wheel entry/replacement p95 remained 47.499-56.308 ms. This did not establish
a useful improvement; the experiment was reverted exactly and is not part of
the feature branch or the final matrix APK. It does not relax the failed target.

A reverse-order control then reinstalled the unchanged final APK and returned to
50 options/default art in both modes (`build/issue16/post-matrix-small-control`).
Cards browsing p95 was 54.143/51.351 ms and Wheel entry/replacement p95 was
48.602-55.106 ms, similar to the preceding 1,000-option runs. Small pools were
also slow late in the session, supporting a runtime/renderer-state contribution
instead of attributing all later failures to pool size. This control is one run,
does not pinpoint the driver/engine cause, and does not replace the failed
three-run matrix. The earlier cold restart also improved timing substantially.
Further frame-budget work needs a stable emulator rendering baseline and
engine/GPU profiling; no acceptance threshold or product interaction has been
changed to convert these failures into passes.

The probe was stopped after collection. Production/probe source hashes and the
final/phone APK hashes were rechecked against the manifest; only the documented
host navigation script revision changed after the original build. Static
analysis and the 446-test result applied to those exact restored pre-cleanup
sources, not to the later UI cleanup build.
No further builds or tests ran during the matrix. Short host-side CSV/JSON
summaries were computed between progress checks; this was not an isolated host
benchmark, and the observed runtime variability remains an explicit limitation.

The original `Pixel_5_API_35` AVD referred to a missing Google APIs 16KB API 35
image; it was installed before testing. Runtime is 1080 x 2340, density 440,
2 GiB guest RAM and 60 Hz. Headless `auto` initially selected SwiftShader;
`-no-window -gpu host` uses the verified NVIDIA GeForce RTX 2050 renderer.
WHPX is available. Configuration values alone were not treated as runtime proof.
TalkBack is installed. No physical phone was used for stress or smoke testing.

Preoptimization source was archived from the baseline commit into ignored
`build/issue16/baseline-source`; its probe uses the same measurement source as the
final build. Earlier tool-development smoke outputs with missing input-frame
joins or scoped-storage command permissions are invalid acceptance evidence.
The external control directory must be created by the app, and commands use
`adb push` to preserve app-readable ownership.

### Diagnostic runs and interrupted matrix attempts

These are bounded diagnostics, not the complete three-run acceptance matrix.
The fixed-probe baseline in `build/issue16/baseline-frozen` and the earlier
optimized build in `build/issue16/final-smoke` each cover 1,000 options with all
photos, both modes, one run and two journeys. Cards input p95 decreased from
134.421 ms to 29.731 ms; sampled peak PSS decreased from 163.44 to 118.09 MiB.
The optimized Cards browsing total-span p95 remained 32.071/31.177 ms for
first/repeated entry: the frozen frame budgets failed. That build precedes the
last per-build eligibility reuse optimization and cannot establish final status.

`build/issue16/final-matrix` stopped on an ADB transport error.
`build/issue16/final-matrix-v2` completed only the 50-option/default-art Cards
run 1 before run 2 stopped at history navigation. The completed case had valid
input/frame joins, but input p95 was 260.546 ms and browsing total-span p95 was
139.019/140.154 ms. Sampled peak PSS was 111.28 MiB. Preserve these failures;
they are not replaced by the earlier faster diagnostic. Neither attempt
establishes the required matrix or ten-journey retained-memory result.

The failed history target was absent because the page had not switched; two
durable history records remained intact. A bounded navigation-only reproduction
also missed a return to the decision page. Screenshot and native node bounds
in `build/issue16/navigation-diagnostic` show the resolved tap inside the enabled
navigation button. The exact cause remains unresolved; this is not evidence of
history loss. Navigation readiness and any retries must be logged separately
from the single-attempt graded selection/drawing/confirmation inputs.

The host navigation revision passed five bounded host-only regression fixtures
(immediate mount, recorded retry, exhausted retries, transport error propagation,
and an unrelated missing-target error), a fresh-directory guard check and parser
validation. After a cold restart of the same AVD, the current APK completed all
three 50-option/default-art Cards runs in `build/issue16/restarted-cards-50`.
All 30 graded inputs were joined and within 100 ms; per-run input p95 was
73.051/31.592/31.131 ms. Sampled peak PSS was 103.86/95.32/96.04 MiB.
All 12 tab navigations succeeded on their first attempt. Browsing total-span
p95 ranged from 13.421 to 48.122 ms across first/repeated windows, so the frame
target still did not pass consistently. The restart changed runtime state,
not the APK, thresholds or renderer configuration; the previous slow run
remains evidence of variability, not a discarded result.

## 2026-10-14 differential performance diagnosis

The user requested diagnosis of the remaining frame failures. No production
source, acceptance threshold, or interaction was changed. The same frozen release
APKs and host harness ran on a cold-started host-GPU AVD with normal font/density
and accessibility services disabled. No build or Flutter test ran concurrently.

Four blocks used old/new/new/old APK order. Each block covered 50 and 1,000
options, zero photos, both modes, and first/repeated journeys. Pool order was
50/1000, 1000/50, 50/1000, 1000/50 respectively. This counterbalances ordering;
it does not provide an isolated-host benchmark or the three-run acceptance
matrix. Evidence directories under `build/issue16/` are
`diagnosis-1014-a2-old`, `diagnosis-1014-b-new`, `diagnosis-1014-c-new`, and
`diagnosis-1014-d-old`; `diagnosis-1014-summary.json` retains their merged rows.
Installed APK SHA256 checks during new and old blocks match the saved APKs;
see `diagnosis-1014-{new,old}-installed-sha.txt`. The first attempted old block,
`diagnosis-1014-a-old`, stopped before measurement on an empty `pidof` result.
Its startup failure is retained and is not frame evidence.

| Diagnostic | Baseline | Current implementation |
| --- | --- | --- |
| 1,000-card browsing, window total-span p95 range | 128.32-181.54 ms | 13.32-27.36 ms |
| Same browsing windows, build p95 range | 118.02-144.42 ms | 1.95-2.72 ms |
| 1,000-card sampled peak PSS, two cases | 163.62-165.91 MiB | 116.55-116.73 MiB |
| 50-card browsing, window total-span p95 range | 10.05-26.85 ms | 13.59-39.23 ms |

This confirms a substantial improvement in the original large-deck build
bottleneck. It does not prove every small-pool path is unchanged: current
small-pool and Wheel timings were sometimes worse in this sequence. Current
1,000-card browsing still failed two of four windows, so improvement is not
equivalent to acceptance.

To investigate that signal, each APK then received its own cold emulator boot
and the same 50-option/default-art Wheel case. Evidence is in
`diagnosis-1014-cold-new` and `diagnosis-1014-cold-old`. In chronological window
order (first entry, first replacement, repeated entry, repeated replacement),
current p95 was 22.398/22.874/8.556/13.229 ms; baseline was
23.933/10.374/8.017/8.841 ms. Current passed 2/4 windows, baseline 3/4.
Before restart, current 50-option Wheel windows ranged from 25.56 to 59.44 ms.
Thus the same current APK performs substantially differently across runtime
conditions, and the cold baseline also fails the target. The first replacement
still differs between versions; one cold case per version cannot exclude a
localized regression or identify its cause.

The complete follow-up contains 18 cases and 36 journeys, all without photos;
it does not replace the previous full matrix or retained-memory checks. Broad
host windows include naturally emitted frames but do not fabricate failed
frames for idle gaps. A read-only audit found no demonstrated timestamp or idle
counting error explaining the failures. Engine timings remain distinct from
compositor presentation. APK provenance in the historical harness records the
host file rather than enforcing installed identity; this follow-up adds direct
installed hashes without changing the frozen harness.

**Conclusion:** the principal large-card build bottleneck is improved; remaining
frame failures include shared baseline behavior and strong runtime variability.
They cannot all be attributed to pool size, a new regression, or an emulator
driver defect on this evidence. Original frame acceptance remains failed. The proposed follow-up engineering
step is active-animation engine/GPU tracing and repeated cold-baseline checks,
including the first-replacement difference, before further targeted rendering
changes. Do not rerun the entire matrix until that diagnostic loop is stable.

## Personal phone (manual verification)

The subsequent [rendering diagnosis](issue16-rendering-diagnosis.md) captures
engine submission spans, a failed system-tracing path, release renderer controls,
and an artwork-complexity control. It proposes a separate diagnostic emulator;
no replacement acceptance baseline or changed metric has been approved.

The user has since installed the isolated verification app and reported no
remaining ordinary-use issues after the UI cleanup. See the current acceptance
section for the latest APK, validation and evidence limits. The
[manual checklist](issue16-phone-checklist.md) remains a reference; individual
specialist checks are not inferred from the user's general confirmation.

The original `build/issue16/whatever-issue16-phone.apk` is historical. Both package
identities coexisted on the emulator and the isolated app launched. Build the
isolated package with an explicit Gradle property after Flutter has generated
plugin registration for the production entry point; environment-variable-only
attempts produced the default identity and were caught during package checks:

```powershell
./android/gradlew.bat -p android :app:assembleRelease '-PverificationBuild=true' '-Ptarget=lib/main.dart' '-Ptarget-platform=android-arm64,android-x64' --console plain
```

Use `build/app/outputs/apk/release/app-release.apk` from that command and verify
its package before copying/installing it; Flutter's separate APK output can be
stale after a direct Gradle build.
