# S11 local recognition verification

Implemented on `codex/issue-12-local-recognition`, based on
`bca3fa23a8f45c35100961e75e2f0e152bf26e80`, on 2026-10-11 (Asia/Shanghai).
Scope: [Issue #12](https://github.com/xinlx227-ai/Whatever/issues/12) plus the
settled implementation handoff from the same date. Changes remain uncommitted;
merge, push, branch deletion, and issue closure are separate delivery steps.

## Delivered behavior

- Local recognition covers the 70 approved scenario entries and three protected
  ingredient/form boundary records. Dataset `2026-10-11.1` has 39 explicit aliases.
  [Dataset provenance and maintenance rules](../data/local-recognition.md) define
  bounded coverage, supported modifiers, category evidence, and uncertain inputs.
- Food seasoning and explicitly supported optional additions preserve base-food
  identity. Known principal-ingredient and food-form differences remain separate.
  Ambiguous wording warns rather than creating a hard duplicate block.
- New forms infer categories independently of entry filters. A manual choice wins;
  competing custom-category evidence and unknown inputs use Unclassified (未分类).
  Built-in category inference uses stable IDs after category label renaming.
- Create and rename assess all same-scenario active, inactive, and deleted options.
  Confirmed duplicates have no add-anyway override; uncertain matches allow viewing
  candidates or proceeding. Existing legacy collisions keep their IDs and history.
- Multiple deleted matches require selecting a target. Restore-and-save reuses its
  ID, applies submitted fields, retains an existing image when no new image is
  selected, and permits clearing restaurant address/notes through empty fields.
  Confirmation explains the overwrite. Reactivation retains the existing fields.
- SQLite schema v8 adds a nullable semantic identity, preserving known identity
  across an opaque user-confirmed rename without storing historical name aliases.
  Clear different-food renames are rejected. Alias search uses retained identity;
  uncertain comparison also retains its lexical evidence after a display rename.
- Migration preserves IDs, status, category memberships, user display text,
  preferences and history. Built-in food IDs retain their seed meaning; a recognized
  same-brand explicit restaurant branch refines the migrated restaurant identity.
  Brand-level and branch-level choices remain distinct. Address differences prompt
  explicit branch naming rather than establishing a new identity themselves.
- Actual saved changes invalidate unfinished rounds. Viewing, canceling, duplicate
  blocks, and no-op saves preserve rounds. Existing drawing behavior is unchanged.

## Verification

- `flutter analyze --no-pub`: passed, no issues.
- `flutter test --no-pub`: all 285 tests passed. Real temporary SQLite tests cover
  v7 semantic migration and older-schema upgrades, collisions, restoration, retained
  history, ambiguous wording, branch identity, and semantic continuity after rename.
- Widget coverage includes automatic/manual category precedence, uncertain viewing
  and creation, confirmed duplicate blocking, alias rename/search, clear different
  rename rejection, explicit selection among deleted targets, restaurant address
  guidance, image cleanup, cancellation, and round invalidation.
- Independent read-only review found and then verified fixes for pathological
  modifier-regex backtracking, ambiguous soy wording, legacy branch migration, and
  uncertain evidence after opaque rename. No remaining findings were reported.
- `git diff --check`: passed.
- `flutter build apk --debug --no-pub`: incomplete. Gradle remained in HTTPS
  dependency reads, with zero-byte download files and no observed progress for
  several minutes. A JVM thread dump confirmed `DownloadAction` waiting in SSL
  input reads; the build was interrupted. No current APK is claimed. An SDK XML
  tooling-version warning was also emitted; no source compiler error was observed.

The 287-case project-authored comparison corpus produced:

| Measure | Observed result |
| --- | ---: |
| Confirmed-match precision | 189 / 189 |
| Labeled-positive recall | 189 / 189 |
| Semantic decision coverage | 242 / 287 |
| Uncertain outcomes | 23 / 287 |
| Unknown outcomes | 22 / 287 |
| False hard blocks among non-positive cases | 0 / 98 |

All 39 curated aliases are included among the positive cases. The distinct cases
include 29 protected-food comparisons and 24 branch/brand comparisons. These finite
regression labels are not an independent field benchmark or a claim of universal
recognition accuracy. Unsupported vocabulary remains usable through the fallback.

Logs are local build artifacts: `build/issue-12-analyze.log`,
`build/issue-12-tests-final.log`, `build/issue-12-evaluation.log`, and
`build/issue-12-apk.log`. Source and artifact hashes are recorded in
[the verification manifest](s11-local-recognition-source.json).
The download diagnostic is `build/issue-12-gradle-threads.log`.

## Runtime limits

No Android emulator/device journey or physical-device accessibility/performance
evaluation was run for this slice. Earlier native evidence in
`first-restore.md` applies only to its recorded revisions, not these changes.
Online recognition and consent transport belong to the later online slice.
