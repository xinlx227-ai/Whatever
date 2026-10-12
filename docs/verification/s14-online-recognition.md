# S14: consent-controlled online recognition

## Agreement and tracker reconciliation

Implementation baseline: main `66a5ae4b59b721a34c593d01964f99ecb58bbeee`; implementation commit `bf419e7`, merged into local main. Scope follows the final user-confirmed 2026-10-12 implementation handoff and [Issue #15](https://github.com/xinlx227-ai/Whatever/issues/15), with blockers #6/#12 verified closed. On 2026-10-12 the user authorized pushing main, reconciling and closing Issue #15, and deleting the merged feature branch. They explicitly accepted skipping another emulator smoke test. This is source delivery, not APK publication or store release.

The handoff supersedes the issue's older gateway/off-device credential and anonymous spending-control language. The accepted architecture calls Xiaomi `mimo-v2.6-flash` directly, bundles a shared build-injected key, and has no account, invitation service, gateway, monthly monetary cap, or remote key distribution. The key is extractable from delivered packages. Local per-install quotas are not account-wide or tamper-proof. Key rotation requires a new package; old invalid keys fall back locally.

Earlier evaluation artifacts are preserved locally under `docs/research/s14-online-recognition-feasibility.md` and `docs/research/mimo-evaluation/`; these pre-existing untracked research files are outside this source delivery. The original 520-call allowance is exhausted. Initial implementation verification used fakes and controlled local HTTP only. The user subsequently explicitly authorized paid calls as part of emulator testing; the live follow-up below records that separate scope without changing historical evaluation journals.

## Implementation

- `OnlineRecognitionRequest` owns deterministic same-scenario ranking, edit self-exclusion, opaque references, complete serialized UTF-8 accounting, and response validation. It starts with at most 80 candidates, removes the lowest-ranked tail until the entire body fits 16,384 bytes, and abstains if the category/query/prompt base is too large. Names and category lists are never truncated. Inactive/deleted candidates remain eligible.
- The ranker uses weighted character/bigram overlap and a small linear prefix component. This adapts, rather than exactly ports, the offline Python ranker. Sorting ties use stable local IDs; only opaque references leave the device. Experimental recall/latency numbers do not validate this production ranker or establish field success probabilities.
- The prompt is adapted from the frozen phase-three protocol. Local `different` judgments veto hints. Structured references must belong to the actual snapshot. Objective custom categories have bounded lexical evidence; unsupported or competing custom meanings abstain. Stable built-in category identity survives label changes. Subjective cooking labels and Light meals (轻食) are conservatively excluded from online automatic filling. Manual choices, existing-item categories and definite local classification win.
- `HttpOnlineRecognitionTransport` has one complete three-second deadline, bounded response bytes, no redirects, no retries, and cancellation that closes the HTTP client. `OnlineRecognitionSession` also guards delayed quota/transport completion with revisions. A form debounces name changes by 600 ms and binds results to its name/scenario/category/candidate snapshot. Address, notes and photo changes do not request recognition. The app registers a page-only route observer: actual page navigation revokes the session even if the editor returns before the response; temporary category menus defer consent/result application until dismissal without consuming a new request.
- Save cancels pending work and uses only a timely, current result already available. The editor combines full-library local uncertain matches with online hints. Confirmed local duplicates still use the authoritative repository path. New entries offer Use existing / Save new / Return to edit; edits offer View existing / Save this item anyway / Return to edit. Existing-item viewing preserves the draft. Multiple matches require selection. Inactive use requires explicit activation; deleted use requires explicit restoration plus the existing field-overwrite confirmation. Restoration retains the original ID/history and revalidates inside the transaction.
- Schema 9 adds independent consent/settings and request-reservation tables. The daily 30 and rolling-minute 6 limits survive restart and are reserved atomically before transmission. Failed requests consume their reservation. Settings writes do not overwrite draw preferences; disabling invalidates in-flight and unapplied results immediately, even if persistence fails.

## Privacy and build

The first eligible typing pause offers consent if no decision was recorded. Declining leaves the local form usable. The library's top-right Settings entry permits later opt-in and disable. Payloads contain only the current name, scenario, available category names, necessary same-scenario candidate names and opaque references. History, image paths, addresses, notes, stable identity metadata and expected test labels are excluded.

The [Xiaomi MiMo policy](https://privacy.mi.com/XiaomiMiMoPlatform/zh_CN/) was fetched directly on 2026-10-12; the page reports an effective date of 2026-10-10. Search indexing still showed an older June version, so the fetched page determined the consent wording. It states domestic storage for domestic use, no text training without prior consent, IP collection for security, and necessity/legal retention rather than a fixed zero-retention promise.

`scripts/build-online-apk.ps1` reads the key silently from `D:\project\mimo_api.txt`, writes a temporary UTF-8 JSON define file under ignored `build/`, builds a release APK, and removes the temporary file in `finally`. The command line contains only that file path. Flutter build intermediates and APKs remain sensitive and ignored; build-time injection protects tracked source, not package secrecy. A normal build without `MIMO_API_KEY` remains fully functional locally and sends no online request. Do not add the actual key to source, docs, logs or research.

## Verification

Before the enum cleanup recorded below, static analysis (`flutter analyze --no-pub`) passed with no issues. The complete desktop suite (`flutter test --no-pub --reporter expanded`) passed all **433 tests**. Logs are retained locally in ignored `build/s14-analyze.log` and `build/s14-all-tests.log`. [Changed-file SHA-256 evidence](s14-online-recognition-source.json) binds these checks to the uncommitted implementation on the baseline above. No merge, push, or issue update/closure was performed. The repair verification used no paid calls; earlier authorized live testing is recorded below.

The original pre-review `scripts/build-online-apk.ps1` release build succeeded. Original artifact (superseded by the repair build below): `build/app/outputs/flutter-apk/app-release.apk`, 59,725,331 bytes; SHA-256 `75f43dad421bf18abb4d021d1d692169802fb50cdc6ab6d2e00fe15c647d6259`. The packaged manifest includes `android.permission.INTERNET`. The actual build-injected credential was verified inside the arm64 library without printing it. A literal/encoded credential scan of tracked/untracked source, research evidence and S14 logs passed; temporary define files were absent after completion. These checks establish packaging, not a live authenticated provider journey. Build output is retained in ignored `build/s14-apk-build.log`.

The deterministic suite covers privacy allowlists, same-scenario/edit-self filtering, zero/fewer/more than 80 candidates, exact UTF-8 body boundaries with escaped/multibyte names, reduction to zero and oversized base fallback. A controlled loopback HTTP server covers request headers/body, 401/429/5xx, redirects, malformed/oversized replies, streaming deadlines, pending connections and offline failure. Session tests include quota delay within the same deadline, stale uncancellable responses, missing credentials and no retries.

Temporary SQLite tests exercise schema migration, independent consent writes, restart-safe and concurrent quota reservation, rolling-minute/midnight behavior, failed transactions, invalid advisory restoration targets, and original history identity. Widget journeys cover first consent/decline/settings, manual/local/existing category priority, category snapshot changes, name changes, timeout, save without waiting, disposal, navigation away and back, category popups, duplicate selection/activation/restoration, edited-item confirmation, and creation through draw/history. Returning to edit or canceling departure retains an already timely hint for the next save without sending again.

Initial independent review covered same-branch unknown-brand spelling, repeat-save hint retention, page-versus-popup lifecycle boundaries, and immediate save before deferred category rendering. A subsequent branch review identified the branch-label spelling regression repaired below; final focused re-review found no remaining confirmed findings. The reviewer did not run Flutter concurrently; root owns executable validation. Read-only behavior was instructed rather than enforced by runtime permissions.

Current local rules produce 189/189 confirmed precision and 245/296 semantic decision coverage on the versioned project regression set, with 0/107 false hard blocks. These are regression observations, not independent accuracy estimates. Frozen provider studies remain historical evidence; this implementation makes no universal accuracy or three-second success-rate claim.

The APK uses the repository's existing local debug signing key even in release mode; it is a local review/install artifact, not a store-signed production release.

### Android emulator follow-up (2026-10-12)

Before the review repair, installed the original release APK with `adb install -r` on the user-started `emulator-5554` (Android 15/API 35, x86_64). That APK had SHA-256 `75f43dad421bf18abb4d021d1d692169802fb50cdc6ab6d2e00fe15c647d6259` and matched all 28 source fingerprints at that time. The repair build recorded below supersedes that artifact; these native observations apply to the earlier build. Existing app data was retained. Before launching the updated app, force-stopped it, enabled airplane mode and disabled Wi-Fi/mobile data; final airplane/Wi-Fi settings were 1/0. No real provider call was made.

Passed native UI smoke journeys, observed through ADB input, UI hierarchy snapshots and screenshots:

- Upgrade installation and launch; existing library and older history remained visible.
- Settings consent disclosure; decline followed by local creation of `EmulatorLocal1012` (library count 32 to 33).
- Later explicit consent/enabling, followed by process restart with the switch still enabled.
- While enabled and offline, entering `OfflineProbe1012`, waiting beyond the deadline, and saving successfully (count 34). This verifies offline usability, not an instrumented request/deadline measurement.
- Re-entering the same name produced the local exact-duplicate dialog; viewing the existing item showed the saved name/category/meal. Returning to the draft and abandoning it worked.
- Disabling recognition and restarting preserved the disabled switch and the 34-item library.
- Wheel draw, confirmation, and history display succeeded; the new Tuna sandwich (金枪鱼三明治) entry appeared alongside older history.

Local evidence is in ignored `build/s14-emulator/` (named XML snapshots, `duplicate.png`, `draw.png`, `history.png`, and `crash.log`). The crash buffer contained an Android Bluetooth-process abort, not an app crash; no app crash was observed during these journeys. At the end of the offline phase, two clearly named test options and one confirmed meal remained; online recognition was disabled and the emulator remained offline.

This is a bounded release-APK smoke test, not full native regression coverage. Physical-device behavior, accessibility services, and mobile provider latency distributions remain unverified. Deterministic success/error/lifecycle coverage remains the automated suite described above. No source-code change or APK rebuild was needed for this follow-up.

### Authorized live Xiaomi emulator follow-up (2026-10-12)

After the user explicitly clarified that emulator testing includes paid API allowance, restored network access and enabled online recognition in the same installed release APK. Entered three eligible names in separate new-item forms: `Spaghetti`, `Ravioli`, then `Spaghetti` again. No host-side authenticated probe, special endpoint, instrumentation, or credential logging was used. These are three UI-triggered attempts; server receipt, token usage and billed totals were not captured and must not be inferred from the UI.

- `Ravioli` produced Dumplings and wontons (饺子馄饨) with the explicit AI-generated category helper (AI 自动分类，可手动修改). This helper is set only after a timely validated online result is applied. It demonstrates the release APK's real authenticated provider response, parsing and UI application through its existing three-second session guard; it is not an independent elapsed-time measurement.
- Saving displayed advisory matches Water dumplings (水饺), Potstickers (锅贴), and Wontons (馄饨). Selected Save new (保存新项), which successfully raised the library count to 35. These suggestions are overbroad for ravioli, and the category conflicts with the prompt's wheat-pasta rule. Successful connectivity does not establish recognition correctness; existing advisory/manual safeguards remain necessary.
- Both `Spaghetti` forms stayed Unclassified (未分类), with no visible AI category. The uninstrumented release UI cannot distinguish timeout, transport/service error, invalid output, or valid abstention. The second form still saved successfully and raised the count to 36. No unsupported root-cause conclusion or success-rate estimate is claimed.

Evidence: ignored `build/s14-emulator/live-*.xml` and `live-ravioli.png`. Original research freezes/journals remain unchanged. No code change or APK rebuild was made. Final state: network access and online recognition enabled, with `Ravioli` and `Spaghetti` retained as two additional test entries. Real Xiaomi connectivity is now verified for one applied response; broader accuracy and reliability remain bounded by the observations above.

### Branch-review repair (2026-10-12)

The branch review found that arbitrary unequal branch labels incorrectly blocked same-restaurant spelling corrections. Rule version `2026-10-12.2` restores explicit rename confirmation for unresolved labels, for both unknown brands and recognized brands. Curated negative location evidence still rejects definite branch conflicts. Online advisory validation uses the same local decision instead of independently vetoing unequal branch text. No positive branch aliases, persistent identity migration, or automatic identity merges were added. The duplicated restoration disclosure now uses one helper while retaining the existing optional message.

New repository tests cover seven script/spelling corrections, confirmation before mutation, stable option and recognition IDs, history linkage after reopening the database, and rejection of a subsequent definite branch change. A focused independent review caught retained misspelled identity keys hiding current-name conflicts; the final fix also checks current names, including known-brand plain suffixes. Online contract tests cover the corresponding advisory acceptance and veto. Final read-only re-review reported no remaining confirmed findings.

At branch-repair completion, static analysis and all **433 tests** passed; `git diff --check` passed. The labeled local corpus now contains 296 cases, with the denominators above. The original ignored main-versus-branch reproduction also passed both cases after the initial repair (`build/s14-review/branch-regression-fixed.log`); the complete final suite covers the later retained-identity and plain-suffix refinements. Source fingerprints were refreshed after final tests. No additional paid API call or emulator/physical-device journey was run for this repair; the earlier native and live-provider observations remain evidence for the original APK only.

Repair release build: scripts/build-online-apk.ps1 succeeded. Artifact: build/app/outputs/flutter-apk/app-release.apk, 59725331 bytes; SHA-256: 87e4a29281bfcdca8445c6ba67ff44f7ccceaf83f62ef911e570456be5f037bc. The temporary build define file was removed. This rebuilt package has not been installed or smoke-tested on the emulator.

### Advisory outcome enum cleanup (2026-10-12)

The optional Standards suggestion is resolved: `resolveAdvisory` returns the private `_AdvisoryOutcome` enum (`proceed`, `restore`, `used`), with `null` still representing cancellation. Both save call sites consume enum values. Dialog choices and user-facing behavior are unchanged.

Static analysis, all 44 tests in `option_editor_test.dart` and `online_recognition_ui_test.dart`, and whitespace checks passed. Logs: `build/s14-enum-analyze.log` and `build/s14-enum-tests.log`. The source manifest records the new editor fingerprint and this bounded follow-up validation. The 433-test full-suite run and release APK above predate this type-only cleanup; neither was rerun/rebuilt. No new emulator journey or paid call was made.

### Main validation and delivery decision (2026-10-12)

After the enum cleanup was committed and fast-forward merged as `bf419e7`, `flutter analyze --no-pub` passed and the complete `flutter test --no-pub --reporter expanded` suite passed all 433 tests on main. The committed comparison against `66a5ae4` passed whitespace validation. Logs: `build/s14-main-analyze.log` and `build/s14-main-tests.log`. These results supersede the earlier note that the full suite had not been rerun after enum cleanup.

The user accepted the remaining native-validation gap and authorized source push, Issue #15 closure, and deletion of `codex/issue-15-online-recognition`. The existing APK predates the final enum cleanup; the branch-identity fixes and enum cleanup have automated coverage but no new emulator smoke journey. No physical-device, accessibility, production accuracy, or mobile reliability claim is added. Research files and unrelated prototypes remain preserved locally.
