# S08 single-target Cards

Scope: [Issue #9](https://github.com/xinlx227-ai/Whatever/issues/9), using the confirmed 2026-10-09 design and existing S07 replacement/save contracts. Branch: `codex/issue-9-single-card`. This report records local implementation; merge, push, and issue closure are separate delivery actions.

## Behavior and boundaries

Cards supports requested count one in all three scenarios. Every eligible identity receives one shuffled face-down card. Browsing preserves identities and selection; the first tap selects, another card changes selection, blank space cancels, and the second tap starts the reveal and mode lock. The fan remains above the central result. Confirmation is direct, with no collection step or bottom result row. Requested counts above one retain their value and offer Wheel while S09/S10 remain undelivered.

Selection takes 200 ms and reveal takes 800 ms, with light reveal haptics and no sound. Reduced motion preserves the explicit selection/reveal steps. The real-action tutorial follows selection, reveal, and confirmation/replacement, with Skip (跳过引导). Successful confirmation or skipping durably dismisses it. SQLite v6 adds that flag without replacing options, history, or the existing preferences.

Replacement reuses the alternative preflight and original-slot state. Redraw (重新抽) can return the outgoing option; Exclude it (排除它) retains a session exclusion. Both valid choices reshuffle and await two explicit taps. A shortage preserves the result and exclusions. Confirmation uses the shared atomic, idempotent contract; failure preserves the selected result for retry. Pre-round eligibility refreshes across midnight while surviving cards retain their identity and relative order; the first flip freezes the round scope.

The unchanged canonical back is bundled from `docs/design/assets/card-back-celestial-black-purple-gold.png`, SHA-256 `7F5944A0B53F4BFA94835261FDBD6E63238536E74C7852E15AE1428D11419FF2`. Cards applies a dark purple/gold palette to shared navigation, library, history, and editors. Existing food SVGs remain; new SVGs provide a plate, generic storefront, and six dining-type storefronts. Built-in restaurant artwork uses stable identities. New personal options receive a persisted default from their initial category identity, preserving it through later category/name edits. User images take priority; unreadable images fall back to the stable default.

## Verification

Run Flutter checks sequentially on Windows. Local logs live under ignored `build/`.

```powershell
& D:/flutter/bin/flutter.bat analyze --no-pub
& D:/flutter/bin/flutter.bat test --no-pub --reporter expanded
& D:/flutter/bin/flutter.bat test --no-pub integration_test/cards_journey_test.dart -d emulator-5554 --reporter expanded
git diff --check
```

The full desktop suite passed **206 tests** (`build/s08-tests.log`). Static analysis passed (`build/s08-analyze.log`). Coverage includes complete card identity reachability, uniform shuffle permutations for a three-card pool, both replacement choices, no-alternative preservation, frozen scope and midnight recovery, failed-save/lost-acknowledgement retry, tutorial persistence/failure retry, and v5 migration preservation. Widget journeys cover tap versus horizontal scroll, off-screen selection, blank cancellation, pre/post-reveal Back behavior, tab visits during animation, mode lock, target-many classification, direct history confirmation, and long names in portrait/landscape at 2x text with reduced motion.

Independent read-only review found two P2 issues: empty pre-round decks did not recover newly eligible candidates across midnight, and category-management helper text retained low-contrast Wheel colors in Cards. Both were fixed and independently rechecked; no further confirmed findings remained. Review restrictions were enforced by instruction, not by runtime permissions. The original Wheel launch CTA viewport regression caused by the new selector was fixed, and its existing regression passes unchanged.

The final category-management theme change passed static analysis and all six category-management widget tests (`build/s08-category-theme.log`).

The subsequent issue review found a cross-tab selection regression: ordinary Library/History taps invoked the shared blank-space cancellation handler. The handler is now restricted to Decide. Four new widget regressions failed before the fix and passed afterward, covering initial and pending-replacement selection in both destinations. They verify text/blank taps preserve the selected identity, deck order, and pending slot, then a second card tap reveals that identity. All 13 card UI tests passed, including Decide blank cancellation (`build/s08-tab-selection-tests.log`); static analysis passed (`build/s08-tab-selection-analyze.log`). The Android journey, screenshots, and release APK below predate this fix and were not regenerated.

The Android 15/API 35 integration journey passed (`build/s08-android.log`) against native SQLite using a temporary database. It verifies pre-reveal navigation, locked-mode feedback, session exclusion and explicit replacement, missed acknowledgement after commit followed by exactly-once retry, direct confirmation in all three scenarios, history, and preference persistence after database/controller recreation. Production records are untouched by this test.

The workstation initially lacked a Gradle 9.3.1 compiler JAR and contained corrupt transform workspaces. Restoring the missing JAR from the checksum-verified official distribution and reversibly quarantining only error-reported transform entries restored the build. No project toolchain versions/configuration were changed (`build/s08-gradle-repair.log`).

## Release and visual checks

The final ARM64/x86_64 release APK built and installed successfully on the API 35 emulator without clearing application data (`build/s08-release.log`). Artifact: `build/app/outputs/flutter-apk/app-release.apk`, SHA-256 `B5CF92DC228C62B9FC29D6AFF5D13402E167127DFD235D79616D71901B58D45C`. After the integration run, the first `--no-pub` release attempt retained the test-plugin registrant; rebuilding with normal dependency/plugin regeneration produced this successful artifact.

Manual release checks confirmed the [face-down fan](images/s08-card-fan.png), [central result with direct actions](images/s08-card-result.png), [restaurant illustrations and library palette](images/s08-card-library.png), and [history palette](images/s08-card-history.png). Actions remained above bottom navigation/system controls. Calculated foreground/background contrast is 16.56:1 for body text, 10.52:1 for secondary text, 13.47:1 for the card name, and 9.70:1 for the primary button; these token checks do not replace full accessibility testing.

Actual Android Back before reveal returned to the launcher, and bringing the live task forward preserved the selected card. Back after reveal offered Continue/Abandon. Browsing Library/History preserved the unfinished result. Actual `am force-stop` and relaunch removed the unfinished result/selection, retained Cards mode, and retained the unfinished tutorial. This manual journey made no history confirmation or library mutation; the crash buffer was empty. Large-text portrait/landscape and reduced-motion coverage remains widget-level rather than manual device evidence.

## Limits

Multi-target card collection and slot replacement belong to #10/#11. No physical-device, TalkBack, iOS, low-memory, or large-library performance certification is claimed by desktop widget tests. Native process termination and real OS Back evidence must be distinguished from controller recreation and widget-level Back dispatch.
