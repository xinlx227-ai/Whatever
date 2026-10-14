# Issue #16 release emulator measurement protocol

Current scope (2026-10-14): the user deferred remaining frame-performance
optimization. This protocol preserves the original measurements and thresholds
for future work; those thresholds no longer gate this slice's revised functional
acceptance. See [current status](issue16-accessible-large-pools.md).


Protocol frozen on 2026-10-13 before collecting acceptance results. This file defines methods; achieved results belong in the implementation verification report.

## Execute

1. Use only `Pixel_5_API_35`, 2 GiB RAM, 1080 x 2340, accelerated graphics, and verified 60 Hz runtime refresh. Record emulator/Android/Flutter versions, host load, renderer, APK SHA256, source SHA and local diff. The host script refuses serials outside `emulator-*`; personal phones remain ordinary-scale manual checks.
2. Preserve preoptimization production sources in an isolated checkout. Copy this probe and its tools into that checkout to build the baseline. Use the identical probe, fixture manifest, runtime, windows, and command sequence for the final build.
3. Build `integration_test/large_pool_probe.dart` with `flutter build apk --release --target integration_test/large_pool_probe.dart`. Install only on the selected emulator. This entry point uses the actual `MealApp`, production controller, and native sqflite; it opens a newly created temporary database and never opens `whatever.sqlite`.
4. Generate fixtures once with `tool/issue16_photos.ps1`, then run `tool/issue16_measure.ps1` with the explicit emulator serial and output directory. Completion means all selected cases finish with raw frames, pointer feedback, journey states, external PSS samples, and fixture/build/environment metadata retained. A failed case remains failed; resume it explicitly after diagnosis.

```powershell
flutter build apk --release --target integration_test/large_pool_probe.dart
D:/SDK/platform-tools/adb.exe -s emulator-5554 install -r build/app/outputs/flutter-apk/app-release.apk
./tool/issue16_photos.ps1 -OutputDirectory build/issue16/photos -Count 1000
./tool/issue16_measure.ps1 -Serial emulator-5554 -PhotoDirectory build/issue16/photos -OutputDirectory build/issue16/final
./tool/issue16_summarize.ps1 -Directory build/issue16/final
```

The harness uses the emulator installation's existing package identity. Do not install this benchmark APK on the personal phone. A separate phone installation identity is a later manual-check preparation step.

The host starts the probe and requires its fresh release/PID-matched boot response before pushing photos. This lets the app create its own external-files control parent. Precreating that parent with ADB can assign incompatible ownership and produce `response.tmp` permission failures. A boot failure records logcat and stops before fixture configuration; repairing an already misowned emulator directory is a host setup task.

## Fixed cases and journeys

The performance matrix is 50/200/1000 eligible options x 0/50/100 percent photos x Cards/Wheel. Default scenario is eat; the tool accepts cook and restaurant for targeted follow-up. Each fresh process and native fixture has three independent runs. Each run contains first-entry and repeated-use journeys, reported separately. First-entry means first entry into the draw stage in a fresh fixture/process, not cold application startup; fixture construction precedes the measured window. `-Pools`, `-Photos`, `-Modes`, and `-Runs` select a bounded diagnosis or resume subset. `-SkipRetainedJourneys` is diagnosis-only and leaves retained-memory acceptance unverified. `-SkipPhotoPush` reuses the already pushed frozen fixture files.

A journey enters the actual stage, browses the Cards fan by opposing real Android swipes, shuffles Cards, selects/reveals or spins Wheel, replaces the first result with session exclusion, selects/reveals or spins the replacement, confirms through the UI, opens history and its latest detail, then returns to the decision page. The tool verifies controller state and durable history count along this path. Animation durations remain production defaults. Wheel has no browsing/shuffle segment; its draw/replacement animation windows are measured instead.

Host navigation amendment: after reproducible missed tab taps, the host waits for
an explicit destination widget after each tab tap. It permits at most three tab
taps, logs every readiness check and retry in `navigation.jsonl`, and propagates
errors other than the exact missing-target response. Tab taps are unarmed and
excluded from input-latency grading. Graded selection, reveal, drawing and
confirmation remain single-attempt operations. The probe, frame/input metrics
and thresholds are unchanged. Compare navigation-inclusive windows only between
runs using this same host revision; earlier diagnostic windows used fixed sleeps.
Each invocation requires a fresh output directory to prevent mixed-process PSS
records or overwritten failed cases.

For the 1000-option/all-photo case in each mode, run 1 also performs 10 additional journeys after the first/repeated warm-up journeys. This covers the approved ten-journey retention check in both modes at the largest pool/photo tier; all 18 cases retain three runs, two entry/use journeys, and peak PSS sampling across tiers. The handoff does not require ten retained journeys at every tier. `-RetainedAllCases` optionally expands retention sampling. Compare the same decision page after exactly five seconds of settling: post-warm-up resting PSS versus post-journey-10 resting PSS. Preserve history and normal caches between journeys; do not force garbage collection or clear caches. Initialization and changes between cases may clear caches and use a new temporary database. Cook defaults to one result for performance comparability; ten-result cooking and all-scenario functional/accessibility coverage are separate tests. Thresholds remain 512 MiB peak and 50 MiB resting growth; neither check substitutes for the other.

Host-generated JPEGs are distinct files and byte sequences at 4000 x 3000. Their colorful procedural texture represents photo-sized decode/cache pressure, not natural photographic entropy. A SHA256/dimensions manifest freezes their identity. Separate oversized, extreme-ratio and invalid files support targeted image tests; they are outside the standard JPEG matrix. No personal originals are used or modified.

## Frames: engine diagnostics and display evidence

The probe registers `SchedulerBinding.addTimingsCallback`, which the installed Flutter SDK explicitly supports in release builds (approximately one-second batches). It records raw engine frame number, build/raster durations, total span, timestamps and raster finish wall time. The collector assigns frames to wall-clock windows using each frame's timestamp, never callback-arrival time. It drains callbacks for 1.5 seconds after closing a window. The primary accepted rendered-frame metric is conservatively `FrameTiming.totalSpan`: actual engine vsync start through raster finish. Grade >= 95% <= 16666.667 microseconds and >= 99% <= 33333.333 microseconds, per continuous browsing/shuffle/wheel window in the release journey. Build and raster durations are separate component diagnostics. This is actual rendered engine timing, not a synthetic widget-build benchmark. The root froze this interpretation before final acceptance runs; the earlier smoke with broken input/frame joins is discarded as acceptance evidence.

These values alone do **not** establish compositor presentation, deadline success or all missed display refreshes. Batch gaps and idle frames must not be counted as frame failures or fabricated successes. The handoff specifies rendered-frame budgets, not a separately specified compositor target. Raw compositor presentation is reported separately and remains ungraded unless continuous-window coverage and timestamp alignment are established.

The optional Perfetto capture uses `android.surfaceflinger.frametimeline`; `tool/issue16_frames.sql` exports the actual/expected app-surface records with identity and presentation fields for inspection. Verify the app's actual Flutter surface appears, rather than measuring only Android decor or unrelated SurfaceFlinger frames. The [official FrameTimeline documentation](https://perfetto.dev/docs/data-sources/frametimeline) currently notes a SurfaceView limitation. Missing app-surface tracks are an unsupported metric, never a passing result. The SQL exports evidence; it deliberately does not substitute app actual-slice duration for on-screen presentation latency. If tracks exist, establish the compositor linkage and window/timebase mapping before grading the fixed thresholds.

```powershell
D:/SDK/platform-tools/adb.exe -s emulator-5554 push tool/issue16_perfetto.pbtxt /data/local/tmp/issue16_perfetto.pbtxt
D:/SDK/platform-tools/adb.exe -s emulator-5554 shell perfetto --background --txt -c /data/local/tmp/issue16_perfetto.pbtxt -o /data/misc/perfetto-traces/issue16.perfetto-trace
# Run the selected journey during the fixed 120-second capture.
D:/SDK/platform-tools/adb.exe -s emulator-5554 pull /data/misc/perfetto-traces/issue16.perfetto-trace build/issue16/
trace_processor_shell.exe build/issue16/issue16.perfetto-trace -q tool/issue16_frames.sql
```

If Perfetto lacks the app surface, first list layers using `adb -s emulator-5554 shell dumpsys SurfaceFlinger --list`, then run `issue16_surface.ps1` with the exact Flutter `SurfaceView[...]` layer in a separate fixed capture while a host journey runs:

```powershell
./tool/issue16_surface.ps1 -Serial emulator-5554 -OutputDirectory build/issue16/surface-smoke -LayerName '<exact Flutter SurfaceView layer>' -DurationSeconds 30
```

This collector polls the 128-record latency ring every 500 ms, preserves raw output, discards absent/unsignaled actual-present timestamps and deduplicates completed records. It also captures per-layer timestats. The [Android frame-rate guidance](https://developer.android.com/games/optimize/framerate) recommends timestats for present-to-present intervals. The [AOSP FrameTracker implementation](https://android.googlesource.com/platform/frameworks/native/+/51de481/services/surfaceflinger/FrameTracker.cpp) defines raw columns as desired-present, actual-present and frame-ready nanoseconds. API 35 can lack usable legacy latency records; zero records remain unavailable. Timestats integer-millisecond histograms have quantization at the 16.67/33.33 ms boundaries and are insufficient for exact grading. Raw records require app-surface identity, continuous-window coverage and timestamp alignment before grading; idle gaps and repeated ring samples do not become synthetic failures or successes. Capture overhead stays identical for baseline/final comparisons.

## Input feedback

All benchmark taps/swipes use `adb shell input`, reaching Android's input pipeline and the production gesture recognizers. The probe observes pointer-down delivery in the global Flutter pointer router. Armed selection/drawing/busy actions capture the first matching controller state change. Post-frame witnesses record the exact state, authoritative `PlatformDispatcher.frameData.frameNumber`, raw scheduler timestamp, and wall time. Witnesses continue on naturally produced frames while that exact state holds, without requesting frames. Join each candidate to `FrameTiming.frameNumber` and select the earliest candidate actually rasterized. Preserve the original marker and unmatched candidates. Timestamp proximity never proves frame identity: earlier Cards smoke showed a one-refresh offset between scheduler and engine timestamps under load, so its input associations are invalid evidence.

The primary input metric is `platformEventToRasterUs`: raw engine raster-finish time minus the Android pointer event timestamp. The installed Android implementation produces pointer timestamps from `MotionEvent.getEventTime()` in milliseconds, converted to microseconds; raster finish uses the same monotonic timebase in this pinned Flutter engine. See [AndroidTouchProcessor](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/AndroidTouchProcessor.java) and [engine frame timings](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/flow/frame_timings.cc). This implementation-specific clock mapping is validated per sample: timestamps and latency must be positive/nonnegative, and the event-to-Dart queue estimate calculated with that frame's wall/monotonic offset must be between zero and five seconds. Invalid mappings remain missing evidence. Preserve raw `platformTimestampUs`, `rasterFinishUs`, and wall timestamps. The 95% <= 100 ms target applies to this platform-event-to-rendered-feedback interval, not intentional shuffle/spin/reveal completion. Delivery-to-state and delivery-to-raster remain separate diagnostics.

The primary interval includes OS queue time after Android created the event; it excludes physical touch sampling before that event and compositor scanout, and the event timestamp has millisecond precision. The diagnostic delivery interval excludes the pre-Dart queue. A superseded busy state with no rendered witness and an unjoined frame remain missing evidence, not a zero-ms pass. Export action count, joined count, missing/superseded/invalid-clock count, raw timings, and latency percentiles. Stage navigation and opening dialogs have no controller feedback marker and are excluded from the graded selection/busy sample. Real overlap/scroll correctness, repeated taps and TalkBack focus/actions also require their separately defined functional cases.

## Process memory

The host samples `adb shell dumpsys meminfo <package>` externally approximately once per second, retaining raw output and host timestamps. PSS uses Android `TOTAL PSS` or the legacy `TOTAL` PSS column, divided by 1024 for MiB. Peak **sampled** PSS must be <= 512 MiB; one-second polling can miss a shorter peak, so label it sampled peak. Explicit resting samples use the same command after the fixed five-second settling interval. The peak includes both background and explicit resting samples; all captured sample PIDs must match the probe report PID. The summary preserves `memorySamples` as the background count and reports `restingMemorySamples` separately. Final resting increase after ten warm journeys must be <= 50 MiB. Record process IDs and detect unexpected process death; missing samples or a changed PID invalidate the run. Host JPEG generation is outside the memory measurement; native fixture construction is included in process sampling and precedes frame/input windows. ADB sampling and control-file polling overhead affect emulator evidence and are kept identical in baseline/final runs.

The host transfers each complete JSON command using `adb push`, then atomically renames it and polls for its unique response ID. Android scoped external storage rejected a shell-redirection optimization because its command files belonged to shell/root rather than the app; that timed-out smoke is invalid evidence and the unused helper was removed. Preserve the ADB transfer method. The probe's idle operation waits asynchronously for production busy/drawing state at a 50 ms cadence, avoiding repeated host snapshots during a four-second spin. Baseline/final comparisons use the same probe/host-tool revision.

`issue16_summarize.ps1` uses nearest-rank percentiles and exports `engine-windows.csv`, `cases.csv`, `input-feedback.csv`, and `summary.json`. Its frame rows stay per case/window/metric; individual input rows retain first-entry/repeated/retained phase labels. The new `platformFeedback*` fields are primary; earlier `feedback*` delivery fields remain diagnostics. Missing and invalid-clock feedback samples count against the 100 ms percentage denominator; never remove them to improve the result. The memory flags require stable PID and complete samples. Compositor acceptance stays separate and unverified by the summarizer.

## Evidence limits

Only a successful release build/run validates probe integration. Analysis and parsing validate source shape, not Android execution. This protocol does not certify physical-device performance, manual OnePlus operation, TalkBack usability, compositor deadlines, or photographic content realism. Record each unsupported measurement and each unperformed check explicitly in the final verification report.
