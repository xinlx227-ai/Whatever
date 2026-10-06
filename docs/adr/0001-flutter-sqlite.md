# Flutter and SQLite for the Android foundation

Adopt Flutter and SQLite through `sqflite` for the first Android slice after demonstrating the wheel-to-confirmation-to-history path on an Android 15 emulator. Flutter shares presentation and domain code for the later iPhone adaptation; SQLite transactions and unique operation identities preserve complete confirmations under write failure and acknowledgement loss, which separate preference/JSON writes would not provide without additional coordination.

Keep selection and temporary rounds in an application controller, independent of animation. The repository receives a database factory so the same confirmation code runs against native Android SQLite and real temporary desktop SQLite in tests. History references retained option identities and stores UTC instants; the current single-item schema is versioned for later scenario and batch migrations.

See [S01 verification](../verification/s01-android.md) for build, execution, failure-injection, and UI evidence. This adopts the foundation only: large card fans, recognition providers, physical-phone performance, and iOS remain separate acceptance work in the issue map.
