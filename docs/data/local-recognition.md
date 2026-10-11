# Local recognition dataset

Read this document when changing recognition rules, alias/category records, or the labeled evaluation corpus. Production data and parsing live in `lib/domain/local_recognition.dart`; regression labels live in `test/fixtures/local_recognition_cases.json`.

## Version and provenance

Dataset version: `2026-10-11.1`.

This project-maintained dataset contains 73 scenario records: the approved 32 eating, 26 cooking, and 12 restaurant seed entries, plus three boundary records for tomato egg soup (番茄鸡蛋汤), tomato egg rice bowl (番茄鸡蛋盖饭), and chicken noodles (鸡肉面). Scenario entries are not globally distinct foods. The two millet/pumpkin porridge entries each occur in both food inventories.

| Record/rule source | Evidence and scope |
| --- | --- |
| Seed canonical names and categories | `lib/domain/meal.dart` accepted inventory, stable seed IDs, and [parent specification #1](https://github.com/xinlx227-ai/Whatever/issues/1). All 70 scenario entries are checked by the inventory test. |
| Additional food-form/principal-ingredient boundaries | [Issue #12](https://github.com/xinlx227-ai/Whatever/issues/12) and the settled implementation interview on 2026-10-11: scrambled eggs, rice bowl, noodles, and soup remain separate; beef/chicken substitution changes identity. |
| Curated aliases | 39 explicit project-authored spelling, common-name, and brand-name alternatives stored beside the canonical record. They are a finite maintained vocabulary, rather than an imported corpus or a claim about all regional usage. |
| Seasoning and optional additions | Settled 2026-10-11 interview: taste changes and optional additions preserve the base food. Complete suffix parsing bounds the supported examples. |
| Restaurant branches | Settled interview: explicit branch names distinguish identities; an address string does not prove identity. |
| Custom-category evidence | Project-authored ingredient/form memberships are explicit stable record-ID sets; supported category names are enumerated in the source. |

No third-party dataset, online inference, external API, or unverified accuracy benchmark is used. The implementation handoff was temporary; this document records the relevant outcomes for dataset maintenance.

## Identity and parsing

`identity` returns a scenario-qualified stable record ID. Known food names are available in both eating and cooking scenarios; restaurant records remain restaurant-only. A restaurant branch adds its complete normalized branch label to the brand identity. A brand option, its East Street branch, and its West Street branch are separate identities. Parenthesized and plain branch suffixes ending in “branch/shop” (店) are supported. Arbitrary branch names outside known brands retain normalized exact-name comparison and otherwise abstain.

Normalization reuses `normalizedOptionName`: width equivalence, English case folding, outer trim, and collapsed spaces preserve punctuation and word boundaries. Curated aliases supply the explicitly supported punctuation/name alternatives.

Food recognition first matches a complete canonical name or alias. It then permits a complete suffix sequence of enumerated seasoning tokens or “add ingredient” (加食材) tokens, optionally wrapped in one pair of normalized parentheses. Every character must be consumed. Prefix decorations, arbitrary additions, replacement language, malformed parentheses, and unexplained trailing text abstain. Matching `牛肉面加蛋` to `牛肉面` does not classify `牛肉面换鸡肉` as beef noodles.

The suffix scanner advances a cursor through complete tokens instead of using a nested repeated regular expression. Malformed input up to the editor's 120-character limit has regression coverage against input-time stalls.

Hand-pulled noodle wording (`牛肉拉面`, `鸡肉拉面`) is more specific than the generic noodle entries and remains uncertain rather than a hard alias. Soy wording `豆乳` also remains uncertain against both protected soy identities: the [Taiwan Ministry of Education dictionary](https://dict.revised.moe.edu.tw/dictView.jsp?ID=43444&la=0&powerMode=0) lists it as an alternative for `豆漿`, so treating it as exclusive evidence for `豆奶` would contradict the accepted distinction. Ambiguous wording receives no automatic category.

A saved `FoodOption.recognitionId` preserves known semantic identity after a user-confirmed opaque display rename. Search uses that identity's curated aliases as well as the current display name. The dataset does not retain each option's historical display names.

`compare` returns:

| Outcome | Evidence | Consumer behavior |
| --- | --- | --- |
| `confirmed` | Normalized exact name or equal recognized/persisted identities | Enforce duplicate handling. |
| `different` | Two distinct recognized identities, including branch distinctions | Keep identities distinct; reject a clear different-food rename. |
| `uncertain` | Recognized-name containment/decorations or a one-edit Chinese near-spelling involving a known name | Offer a warning, never a hard duplicate block. |
| `unknown` | Insufficient supported semantic evidence | Preserve uncertainty and existing rename-confirmation policy. |

For rename checks, derive the proposed new identity independently before retaining the old identity. Passing the retained identity as evidence for the proposed new name before that check would conceal a known different-food rename.

## Categories and search

Seed categories are selected by stable built-in category IDs, preserving classification after a label rename. Reliable cross-scenario forms map noodles/porridge/pancakes to the eating form category and rice/noodles/flour staples to cooking Main food (主食). Other cross-scenario categories abstain.

Custom categories match either a full recognized canonical/alias name or one of the enumerated objective ingredient/form labels with explicit membership evidence. Egg, tomato, beef, tofu, noodles, and porridge concepts are supported. A unique supported custom match wins; competing supported matches return Unclassified (未分类). Subjective labels and unsupported relationships abstain. Optional added ingredients preserve the base food's category evidence. Manual form selections are handled by the editor and take precedence.

Alias search checks the current display name, curated identity aliases, and complete recognized query variants. Brand searches may retrieve branch options without merging branch identities. Search remains filtered to the current scenario by its controller caller.

## Evaluation and maintenance

The frozen corpus has 287 labeled comparison cases:

| Group | Cases |
| --- | ---: |
| Seed normalization | 70 |
| Explicit aliases | 39 |
| Complete seasoning suffixes | 58 |
| Optional additions | 20 |
| Protected distinct foods | 29 |
| Restaurant branches | 26 |
| Unsupported variants/ambiguous wording/near-spelling warnings | 23 |
| Outside vocabulary | 22 |

Expected outcomes are 189 confirmed, 53 different, 23 uncertain, and 22 unknown. The branch group includes two positive formatting/brand-alias cases and 24 negative branch/brand distinctions.

The evaluation test prints observed confirmed precision, positive recall, semantic decision coverage, uncertain/unknown rates, and false hard blocks with denominators. Read the actual test output for measured results. This finite project-authored corpus is regression evidence; it is not independent real-world validation or a guarantee for unseen names. Semantic decision coverage intentionally excludes uncertain and unknown cases.

When changing the dataset:

1. Keep existing identity keys stable. Add a new record for a distinct principal ingredient or food form.
2. Add only explicit, defensible alias/category evidence and bump `datasetVersion`.
3. Add independently labeled positive, protected-negative, and unsupported examples to the frozen fixture; align its version.
4. Run `flutter test test/local_recognition_test.dart` and the repository/editor/controller regression checks sequentially on Windows. Inspect every disagreement and the printed denominators before accepting the new version.

Inventory, classification, opaque-rename identity/search, restaurant search, custom-category ambiguity, scenario isolation, and complete suffix consumption have additional focused tests outside the comparison corpus.
