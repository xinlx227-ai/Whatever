# S03 personal library verification

Date: 2026-10-06, Asia/Shanghai. Scope: [Issue #4](https://github.com/xinlx227-ai/Whatever/issues/4), governed by [Issue #1](https://github.com/xinlx227-ai/Whatever/issues/1). Branch: `codex/issue-4-personal-library`, based on main `85148790280b2278e1f13844392cb52751aadbee`.

## Delivered behavior

- What to eat (吃什么) library defaults to active options, searches normalized names, and offers inactive/all filters. Queries take an explicit scenario and omit retained deleted rows.
- Personal forms require a name, one category, and at least one period. New forms default to the current local period, independently of the draw's manually selected period. Classification remains Unclassified (未分类); category management and alias recognition remain later slices.
- Name comparison folds full/half width, English case, outer whitespace, and repeated internal whitespace, retaining word boundaries and punctuation distinctions. Display text retains entered content except outer trimming. Duplicate checks include inactive and deleted rows. Restoring an exact deleted custom match requires explicit confirmation and preserves its identity, history references, and existing image when no replacement was supplied.
- Renaming to a different normalized name asks the user to confirm that it is the same food. S03 makes no broader recognition claim. Built-in names/images remain editable; built-in category/period edits and deletion are blocked at the application persistence boundary.
- Selected photos are decoded and copied to app-owned support storage before the option row commits. Writes use a temporary file, flush, then rename. Identical bytes reuse the existing path, preserving no-op behavior. Editor completion/disposal removes unused attempts and superseded photos only after checking all durable references, including deleted rows. Unknown foods use a stable generic plate icon. Library, result, and history render selected images with a default-art fallback if a file cannot be decoded.
- Android uses the system photo picker through [image_picker](https://pub.dev/packages/image_picker). Bootstrap retrieves lost picker results after process recreation and offers a new, unsaved form; it does not guess the interrupted option identity. The user can instead return to the library and edit the original option.
- SQLite v3 adds option metadata without rebuilding seed identities or history. Deletion retains the backing option and its photo. Public maintenance operations serialize with confirmation. Only committed actual changes invalidate the unfinished round and retain feedback until Decide is shown. Canceled dialogs, unchanged saves, duplicate refusals, and failed writes preserve the round.
- Editor Back asks before discarding dirty input. Picker/save activity disables repeated actions. The current app retains its light visual theme; no new dark theme is introduced.

## Reproducible verification

Use the toolchain and Maven routing documented in [S01](s01-android.md). This slice disables Kotlin incremental compilation in `android/gradle.properties`: the new image-picker plugin's cache is on `C:`, while the project is on `D:`, and Kotlin's incremental path converter failed on different drive roots. This changes build caching only.

```powershell
& D:/flutter/bin/flutter.bat analyze
& D:/flutter/bin/flutter.bat test
& D:/flutter/bin/flutter.bat test integration_test/library_journey_test.dart -d emulator-5554
& D:/flutter/bin/flutter.bat test integration_test/android_journey_test.dart -d emulator-5554
& D:/flutter/bin/flutter.bat build apk --release --target-platform 'android-arm64,android-x64'
git diff --check
```

Run desktop Flutter test invocations sequentially on Windows; simultaneous invocations can lock the generated SQLite DLL. Flutter's normal concurrent execution within one invocation passed.

## Evidence

The final combined desktop suite passed 69 tests, and static analysis and whitespace validation passed. New coverage includes real v1/v2 SQLite upgrades, transactional rollback, duplicate races alongside confirmation, normalized duplicates, retained identity/history/image references, creation-to-confirmation maintenance, no-op invalidation, editor Back priority, built-in restrictions, copied image bytes after source deletion/reopening, unused/replaced-photo cleanup, failed reference-read retention, and valid-header corrupt-image rejection. Editor checks cover portrait and landscape at twice the default text size, plus explicit consent for recovered images.

Both native integration targets passed on the API 35 emulator. The S03 journey creates through the production form, draws and confirms the new option, deactivates and deletes it, reads retained history, restores the exact name under the same ID, and reopens the database. Native tests wait for observable persistence outcomes because animation settling alone does not await SQLite completion. The original Android journey also passes against the integrated S03 implementation.

The production release APK was installed after integration tests. Host-driven actual UI checks selected `build/s03-photo.png` through Android's system photo picker, saved `S03PhotoMeal`, searched the library, removed the gallery source file, force-stopped and relaunched the app, and verified that the stored photo remained visible. Hardware Back on an edited period showed the unsaved-change prompt; cancel preserved the form, and discard returned without the period edit. Android's crash buffer was empty.

- [Editor with selected photo](images/s03-editor.png)
- [Searchable personal option](images/s03-library.png)
- [Photo after source deletion and process restart](images/s03-photo-reopened.png)

The photo is an explicit test fixture. Native integration uses temporary databases; the manually created `S03PhotoMeal` remains in the emulator's production library for review. No pre-existing production record was cleared.

Independent review found an unused-image leak after rejected/canceled saves and photo replacement, including deleted-option restoration with a new photo. Cleanup now checks all retained database references and restricts deletions to the app-owned image directory. Review also prompted full first-frame decoding before copying. The reviewer rechecked both fixes and reported no remaining confirmed findings.

Artifact: `build/app/outputs/flutter-apk/app-release.apk`, 38,112,090 bytes, ARM64 and x86_64, package `com.xinlx227.whatever`, version `0.1.0+1`, signed with the local debug key for review. SHA-256: `0647A4F88A03C220C07370F0E152B398A4C53DB55275A885F48B551CA9DDEC05`.

## Limits

Broader aliases, semantic food classification, category management, other scenario screens, and restaurant-specific editing remain later issues. Image cleanup retains files when durable references cannot be read; abrupt process death between file copying and row persistence may leave an orphan until a future maintenance implementation. Native validation is limited to the API 35 emulator, with no physical-device, TalkBack, or genuine low-memory-pressure claim. See S02 for earlier lifecycle evidence; its native process matrix is historical evidence, not a rerun for S03.
