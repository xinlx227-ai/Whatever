# Issue #16 rendering diagnosis: 2026-10-14 follow-up

## Current status — 2026-10-14

The user subsequently accepted ordinary manual phone experience and deferred
remaining performance optimization. Diagnosis is paused and no longer blocks
Issue #16 under its revised scope. The historical frame failures remain failures.
See [current acceptance and APK evidence](issue16-accessible-large-pools.md).
The environment change below remains an unexecuted proposal for future work.

## Historical diagnostic recommendation

Do not simplify the accepted artwork or switch the production renderer on the
current evidence. The remaining Wheel failures concentrate in frame submission,
and a plain rotating rectangle also fails inconsistently. The selected emulator
cannot currently provide a valid system scheduling trace. Investigate a separate,
equally configured standard API 35 emulator before more production edits.

This is a proposed diagnostic-environment change, not an approved replacement
acceptance baseline. The original release matrix remains failed. Do not lower
thresholds, substitute profile results, declare physical-device performance, or
use phone experience to claim the frozen numerical thresholds passed.

The user approved diagnosis and targeted fixes, with evidence and discussion
before changing the fixed environment or acceptance method. No production fix
was retained in this follow-up. The existing feature implementation and probe
hashes match their previously validated manifest; `wheel.dart` was restored
byte-for-byte after an isolated experiment.

## System tracing limitation

The current `Pixel_5_API_35` runs the Google APIs ps16k image; `getconf PAGE_SIZE`
returns 16384. Perfetto's configuration had to be piped through stdin because
its process could not open the shell-pushed file directly. Capture then completed,
but Trace Processor rejected it with `FTRACE_STATUS_PARTIAL_PAGE_READ`.
Forced diagnostic loading reported zero scheduling rows. It is not usable
evidence of thread scheduling or compositor presentation.

Artifacts under `build/issue16/`:

- `diagnosis-trace.pbtxt`, `diagnosis-partial.pftrace`,
  `system-trace-parse-error.log`.
- `diagnosis-trace-wheel`: release journey, but system capture started late after
  the configuration error. Do not treat it as a fully traced journey.

The error proves a limitation of this capture path, not that 16KB pages caused
the application's frame delays. Perfetto defines this error as a ring-buffer
read problem in its [trace protocol](https://perfetto.dev/docs/reference/trace-packet-proto).
The native v58.2 Windows processor was downloaded following the
[official CLI documentation](https://perfetto.dev/docs/reference/trace-processor-cli);
its SHA256 matches the official wrapper manifest
`adfa6bad3d72be3ba9b83fa2b17b69fa13b3ab1cad0f42e52b86188bd5f0f997`.

## Engine profile evidence

A diagnostic-only copy of the probe allows Android profile mode while preserving
the production widgets/controller. Its report truthfully contains `release=false`.
A copied host harness enables the local VM service and captures Dart/Embedder/GC
timeline events. These are diagnostic measurements, not release acceptance.

Artifacts: `profile_probe.dart`, `profile-measure.ps1`, `diagnostic-profile.apk`,
`profile-build.log`, `diagnosis-profile-wheel`, `diagnosis-profile-repeat`.
Three cases each contain first and repeated draw/replacement/confirmation/history
journeys. The first case passed all four relevant frame windows; later cases
reproduced failures. Run 3 replacement total-span p95 was 24.014/23.943 ms.

Run 3 components, first/repeated replacement:

| Engine span | First p95 | Repeated p95 |
| --- | --- | --- |
| Rasterizer draw | 18.302 ms | 18.406 ms |
| Surface encode | 1.378 ms | 1.330 ms |
| GLES reactor | 0.986 ms | 0.924 ms |
| Surface submit | 17.615 ms | 17.710 ms |

These percentiles describe separate distributions and must not be subtracted as
if they were the same frame. The long submission span, together with short
encoding/reactor spans, points toward presentation/backpressure rather than
expensive Dart layout. It does not independently distinguish GPU execution,
driver blocking, BufferQueue waiting, or host scheduling.

The engine's Impeller GLES path reaches `eglSwapBuffers` through
`SurfaceFrame::Submit` -> `SurfaceGLES::Present` -> Android `GLContextPresent` ->
`impeller::egl::Surface::Present`. This path lacks the Skia-specific
`AndroidContextGL::SwapBuffers` marker. There is no separate measured swap span
in this trace; absence of that marker does not mean absence of buffer swapping.

Trace Processor reported malformed/crossing events in the exported VM JSON.
Component numbers above therefore use independent direct B/E pairing by exact
PID/thread/name from the original export. All selected synchronous spans have
matched starts/ends, nonnegative durations and no same-name nesting. Script and
results: `analyze_profile.py`, `profile-run3-components.json`. Other timeline
events remain unsuitable for exhaustive trace-health claims.

All four run-3 windows have adjacent engine-vsync-gap p95 of 16.667 ms. The two
replacement windows each contain one gap over 25 ms among 261/263 recorded
frames; idle gaps were retained. Thus high engine end-to-end frame latency can
coexist with regular engine frame production. This is not proof of on-screen
smoothness: neither vsync cadence nor raster completion alone establishes actual
presentation. Keep the frozen total-span failures visible; do not silently
substitute cadence for the accepted metric.

## Release renderer control

The same saved final release APK ran six 50-option/default-art Wheel cases in
Impeller/Skia/Skia/Impeller/Impeller/Skia order. Each case restarts the app and
contains first/repeated journeys. The only intervention is an Android launch
extra disabling Impeller for the Skia cases; per-case Flutter logs verify the
backend change. No manifest or production configuration changed.

| Renderer | Passing windows | Window total-span p95 range |
| --- | --- | --- |
| Impeller | 4 / 12 | 9.049-73.012 ms |
| Skia | 2 / 12 | 11.548-58.869 ms |

Both fail. Switching renderers is not a demonstrated fix. Artifacts:
`renderer-0-impeller` through `renderer-5-skia`, `renderer-comparison.csv`, and
the diagnostic-only `skia-measure.ps1`. These runs did not reboot the emulator
between cases and are not an isolated-host benchmark.

## Artwork-complexity control

A diagnostic APK temporarily replaces only `MealWheel` artwork with a rotated
solid rectangle of the same aspect ratio. The parent sizing/animation and actual
controller/manual replacement/confirmation/history flow remain. It is a
load-removal experiment, not an acceptable product design or acceptance APK.
The build script restored the original source in `finally`; the original and
restored hashes are identical.

Three 50-option/default-art Wheel runs passed 5 of 12 relevant frame windows.
Run 1 passed all four, run 2 passed one, and run 3 passed none. Window p95 ranges
from 9.767 to 30.490 ms. Removing the detailed rotor does not consistently remove
the symptom, so more artwork simplification is not justified as the next fix.
The experiment leaves the surrounding app intact and does not prove every
possible application contribution is absent.

Artifacts: `wheel-before-minimal.dart`, `wheel-minimal-diagnostic.dart`,
`minimal-wheel-build.log`, `minimal-wheel-diagnostic.apk`,
`diagnosis-minimal-wheel`. The generic Flutter release output now contains this
diagnostic variant: use the saved named final/phone APKs, not generic build output.

## Proposed bounded next step

1. Create a separate diagnostic AVD using the already installed standard API 35
   x86_64 image, keeping 2 GiB RAM, 1080x2340, density 440, host GPU and 60 Hz.
   Retain the selected ps16k AVD and all its failed evidence.
2. Verify runtime configuration and usable system traces before judging speed.
   Run the same old/current release 50-option Wheel control, including first
   replacement, then the current 1,000-card control. Keep cold/steady behavior
   separate. No phone, artwork change, renderer switch or threshold change.
3. If the diagnostic environment works, present its comparison before adopting
   it as the formal baseline. If it does not, report that result; do not turn this
   into repeated full-matrix runs or indefinite UI optimization.
4. If actual presentation evidence shows that total-span latency is not a suitable
   interpretation of the desired smoothness target, propose an explicitly revised
   metric with retained old results. User agreement is required before acceptance
   is evaluated under a different definition.

The final production probe was reinstalled and force-stopped after experiments;
`diagnosis-restored-apk-sha.txt` matches the saved final APK. The profile VM-service
port forwarding was removed. No tests ran on a physical phone. No commit, push,
merge or issue edit occurred. Previous unit/widget results apply to unchanged
production source; this follow-up does not claim newly executed test coverage.
