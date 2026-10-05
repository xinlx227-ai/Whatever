# Meal app technical direction

Primary-source research: 2026-10-05. Status: provisional recommendations; no framework, provider, or dependency set adopted. Scope: [accepted behavior](../planning/meal-app-handoff.md) and [planning synthesis](../planning/meal-app-overall-plan.md).

## Framework comparison

| Option | Documented capabilities | App-specific assessment: inference |
| --- | --- | --- |
| Flutter / Dart | Windows supports Android development; local iOS development requires macOS. CustomPainter supports painting, hit testing, semantics, and animation-triggered repainting. The SQLite cookbook uses sqflite on Android/iOS/macOS. | Preferred first feasibility candidate for a bespoke wheel and transformed fan cards. Painted wheel geometry plus card widgets could avoid combining multiple drawing libraries. Exact interactions and performance remain untested. Windows development can target an Android emulator/device; it does not require a Windows desktop build. |
| React Native / Expo / TypeScript | Reanimated supports UI-thread animations; its current 4.x line requires the New Architecture. expo-sqlite persists across restarts and supports scoped exclusive transactions. Expo offers cloud iOS builds from any computer; local iOS builds require Mac/Xcode. | Strong alternative with established React/TypeScript expertise. Prototype card transforms and select a wheel drawing dependency deliberately. Cloud builds help a Windows workflow but do not provide a local iOS simulator or eliminate native debugging. |
| Kotlin / Compose Multiplatform | Compose can share common UI across Android/iOS. iOS builds require macOS/Xcode. Room KMP supports shared entities/DAOs, platform-specific builders, and transactional SQLite writes. | Credible with Kotlin expertise or substantial native integration needs. Choosing Android-only Compose and a separate later iPhone UI would deliberately trade away UI reuse. The retrieved Room KMP guide illustrates Room 3.1.0-alpha01; do not adopt that sample dependency set automatically. |

Sources: [Flutter platform integration](https://docs.flutter.dev/platform-integration), [CustomPainter API](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html), [Flutter SQLite cookbook](https://docs.flutter.dev/cookbook/persistence/sqlite), [Expo CLI and builds](https://docs.expo.dev/more/expo-cli/), [Reanimated prerequisites](https://docs.swmansion.com/react-native-reanimated/docs/fundamentals/getting-started/), [Expo SQLite](https://docs.expo.dev/versions/latest/sdk/sqlite/), [KMP quickstart](https://kotlinlang.org/docs/multiplatform/quickstart.html), [Room KMP](https://developer.android.com/kotlin/multiplatform/room).

**Recommendation:** first validate Flutter, SQLite behind a repository boundary, a draw state machine independent of widgets, and replaceable recognition adapters. This is a fit assessment, not a measured performance ranking. Reconsider Expo if verified React experience outweighs learning Dart; reconsider Compose Multiplatform if Kotlin expertise or native integration requirements justify it. No team-language preference has been established.

## Persistence implications

Propose stable IDs independent of names; retained deleted-option rows; ordered history-item references; and one transaction for each complete confirmation. A unique confirmation-operation key makes retries idempotent. Preserve results until persistence succeeds. Keep unfinished rounds and exclusions in memory to match process-lifetime sessions.

Use parameterized SQL and enforce foreign keys. Expo documents that an ordinary async transaction can include interleaving queries; evaluate its scoped exclusive transaction API for the save boundary. Whichever SQLite wrapper is selected must pass failure-injection and concurrency tests. A cookbook recipe alone does not validate this application's save/retry implementation. [Expo SQLite transaction documentation](https://docs.expo.dev/versions/latest/sdk/sqlite/).

## Recognition architecture: proposal, not provider selection

Perform normalized exact and curated-alias checks over the entire local scenario, including deactivated and deleted identities. With consent and connectivity, use a small HTTPS gateway holding provider credentials and a replaceable provider adapter. When offline, consent is absent, or the request fails, complete local recognition and apply the accepted uncertain-match/Unclassified behavior.

The gateway needs request limits, a spending ceiling, and a circuit breaker. It does not need an account UI or a server database of user libraries/history. A shared token embedded in a mobile binary is not sufficient protection for a public endpoint.

Send only the accepted name, scenario, category names, and necessary same-scenario names. Use request-local handles; keep persistent option IDs on the device. Exclude photos, history, addresses, and notes. Validate returned references against supplied candidates, discard stale responses, and preserve manual category choices. Disablement must stop new transmissions; a late response must not modify saved content.

Provider-neutral results should distinguish category assignment/abstention and identity match/abstention, including evidence type and provenance where available. Model self-reported confidence alone should support a possible-duplicate warning, not a mandatory block. Normalized equality and tested curated aliases can provide stronger identity evidence. Evaluation must distinguish Tomato scrambled eggs (番茄炒蛋 / 西红柿炒蛋) from tomato egg soup and preserve separately accepted Soy milk (豆浆) and Soy beverage (豆奶). Distinct restaurant branches remain distinct.

Choose payload limits, candidate shortlisting, and the online deadline after measuring realistic libraries. Shortlisting can reduce recall: omitted candidates must not be interpreted as proof of uniqueness. Local data coverage/licensing and evidence for online hard-blocking remain unresolved. Neither a provider nor a model has been benchmarked.

## Adoption gates

Use the proposed gates in the planning synthesis as the shared checklist: profile a release build on representative Android hardware, exercise every card in large pools, inject save failures and missed acknowledgements, test process lifecycle and midnight, and measure recognition on held-out labeled Chinese cases. Before claiming demonstrated iPhone reuse, build and exercise the interaction/persistence slice in a real macOS build environment on an iPhone.

Report hard-block precision and false blocks, alias recall, category precision and coverage, abstentions, manual corrections, latency percentiles, fallback rates, and cost per completed recognition. Zero errors in a finite test set does not establish perfect production recognition. Agree device-specific thresholds before adopting the implementation.

Estimate provider cost from measured input/output usage per request and dated official unit prices. Include request frequency, retries, gateway overhead, and spending limits. Scenario-library size can materially affect payload cost. No numerical cost estimate is defensible from the evidence gathered here.

## Limits of this research

The research subtask consulted primary documentation; the root reviewed its findings against the product rules. A redundant root fetch of three pages did not complete and was stopped. No app prototype, SDK installation, device benchmark, dataset audit, provider test, or service deployment occurred. Provider availability, regional access, privacy/retention terms, licensing, hosting, and operating cost remain unvalidated. Pin compatible stable versions during feasibility work rather than treating live documentation examples as a lockfile.
