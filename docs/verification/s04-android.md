# S04 independent meal scenarios

Date: 2026-10-07, Asia/Shanghai. Scope: [Issue #5](https://github.com/xinlx227-ai/Whatever/issues/5), under [Issue #1](https://github.com/xinlx227-ai/Whatever/issues/1). Branch: `codex/issue-5-scenarios`, based on `622aa96ced95f4366d090cf6444e931023461d38`.

## Delivered behavior

- What to eat (吃什么), What to cook (做什么), and Where to eat (去哪吃) have independent persisted libraries and draw one eligible result per round. Only explicit confirmation writes history; history displays the corresponding scenario.
- The complete initial content contains 32 eating options, 26 cooking options, and 12 restaurant brands. The original eight eating identities remain. Rice bowl meals (盖饭套餐) replaces the earlier category label without renaming dishes. Cooking keeps only accepted memberships, including three memberships for tomato scrambled eggs and two for egg pancake. Counts for breakfast/lunch/dinner/late-night are respectively 14/28/29/19 eating, 6/20/20/6 cooking, and 2/10/12/6 restaurants.
- Option library and Decide retain independent scenario selections for the current session. Decide shares one selected meal period across scenarios. Changing Decide scenario or period during a started round asks to restart; cancel preserves conditions and results. Fresh processes still begin in eating with the current local period.
- Custom options select one category and at least one period. Built-in categories are read-only and built-in food/dish periods remain read-only. Restaurant periods are editable draw applicability, not opening hours; brand inclusion does not imply a nearby available branch. Restaurant forms store optional address, notes, and the existing optional user image. Generic restaurant art uses a stable storefront icon.
- SQLite v4 adds category memberships and restaurant fields. Versioned expansion retains display names, default art, selected images, active/deleted state, preferences, custom categories, and history references. When a newly introduced seed matches an existing same-scenario normalized name, expansion preserves that existing identity instead of creating another candidate, including inactive/deleted options. Existing restaurant periods remain user-owned. Actual saved changes, including restaurant address/notes changes while deciding food, invalidate unfinished rounds; canceled, duplicate, and no-op saves preserve them.
- Dense wheel pools use radial labels while keeping every candidate in the uniform selection pool and showing the full result name after drawing.

## Specification provenance

Issue #4 was confirmed CLOSED with completion evidence before implementation. The user explicitly authorized Issue #5 implementation from the 2026-10-07 temporary handoff. That handoff resolves the complete eating inventory, freezes cooking memberships, separates page scenario selections, and shares the Decide period. Those decisions govern this implementation. Formal issue text synchronization is a separate requested approval; this report is delivery evidence, not a replacement issue tracker.

## Reproduce

Use the Flutter/Android toolchain documented in [README](../../README.md) and [S01](s01-android.md). Run Flutter invocations sequentially on Windows to avoid SQLite DLL and build locks.

```powershell
& D:/flutter/bin/flutter.bat analyze
& D:/flutter/bin/flutter.bat test
& D:/flutter/bin/flutter.bat test integration_test/scenario_journey_test.dart -d emulator-5554
& D:/flutter/bin/flutter.bat test integration_test/android_journey_test.dart -d emulator-5554
& D:/flutter/bin/flutter.bat test integration_test/library_journey_test.dart -d emulator-5554
& D:/flutter/bin/flutter.bat build apk --release --target-platform 'android-arm64,android-x64'
git diff --check
```

The scenario integration test uses a temporary database and checks independent browsing, canceled restart, all three explicit confirmations, restaurant creation with multiple periods/address/notes, drawing that personal restaurant, and retained data after reopening. Production records are not cleared.

## Verification results

Static analysis passed with no issues, the final desktop suite passed all 88 tests, and whitespace validation passed. New tests cover exact inventories and period counts; all scenario/period confirmation paths; preserved identities through v1/v2/v3 upgrades; active/inactive/deleted same-name seed collisions; multi-category built-ins; restaurant field clearing and reopening; cross-scenario mutation/no-op behavior; independent page selection; canceled restart; and portrait/landscape layouts at twice the default text size. A 393-by-851 portrait test with 48-pixel top/bottom safe areas verifies that every scenario starts with the full primary action and footer above navigation, without scrolling.

All three native integration targets passed on the API 35 emulator. The S04 journey confirmed eating, cooking, and restaurant choices, created and confirmed a personal restaurant with multiple periods/address/notes, then reopened its temporary SQLite database and verified history and fields. Original Android navigation/draw/history and S03 create/delete/restore flows also passed against the expanded implementation. Upgrade collision scenarios run against real desktop SQLite; native journeys use fresh temporary databases.

The first native S04 run exposed a missed test tap while the keyboard inset was settling; the helper now waits through the platform transition and checks visibility again. The corrected run passed without missed-tap warnings. A duplicate-preview widget test similarly required its dialog continuation to resume in the real async zone used by SQLite saves; the final full suite includes that correction.

Independent review found and rechecked two fixes: migration now avoids introducing a second identity for an existing same-scenario normalized name, and built-in editors show all accepted category memberships as read-only. The final read-only review reported no remaining findings. The root executed all Flutter validation.

Release visual inspection then corrected the portrait start-action clipping and overlapping restaurant wheel labels. After the final painter adjustment, static analysis and all 25 affected UI journey tests passed again. The final release was rebuilt, installed without clearing production data, and inspected across all three scenarios; primary actions and footers are fully visible and restaurant labels no longer overlap. Android's crash buffer was empty. Native integration runs precede these final presentation-only adjustments; the final APK received manual visual inspection rather than another full native integration run.

- [Eating, lunch](images/s04-eat.png)
- [Cooking, lunch](images/s04-cook.png)
- [Restaurants, lunch](images/s04-restaurant.png)

Artifact: `build/app/outputs/flutter-apk/app-release.apk`, 38,243,378 bytes, ARM64 and x86_64, package `com.xinlx227.whatever`, version `0.1.0+1`. SHA-256: `1B8CCE79E493D6D31336D100198E1615307B0FC6BB385C9E26B342F23B747663`.

## Limits

Cooking batches, category filtering/management, cards, replacements, and broader recognition remain later slices. Native validation targets the API 35 emulator; no physical-device, TalkBack, or low-memory-pressure claim is made. The previous S03 photo-picker and lifecycle matrices are historical evidence rather than fresh S04 runs. The existing debug signing key is for review builds, not store distribution.
