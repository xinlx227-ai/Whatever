# Meal decision app: planning handoff

Updated: 2026-10-09, Asia/Shanghai.

## Resume here

The 2026-10-10 confirmed redesign is implemented locally on `codex/first-restore`.
See [current behavior and verification](../verification/first-restore.md) before
using the historical sections below. Full-screen navigation, lower fan layout,
remove-and-append replacement, and explicit retained-meal confirmation supersede
the older contracts here and in the still-unedited formal issues.

The user completed the S08 design discussion on 2026-10-09 and authorized implementation in the next session. This session records decisions only. [Issue #9](https://github.com/xinlx227-ai/Whatever/issues/9) owns single-target Cards in all three scenarios, including single-result replacement; [Issue #10](https://github.com/xinlx227-ai/Whatever/issues/10) owns multi-target collection; [Issue #11](https://github.com/xinlx227-ai/Whatever/issues/11) owns multi-target slot replacement. These are accepted design directions, not implementation or validation evidence. Read the current formal issues before implementation.

S04 implementation on 2026-10-07 applies the user's subsequently approved complete eating inventory, Rice bowl meals (盖饭套餐) label, frozen cooking memberships, independent page scenario selections, and shared Decide meal period. Earlier unresolved-content notes below are historical. See [Issue #5](https://github.com/xinlx227-ai/Whatever/issues/5) for slice ownership and [S04 delivery evidence](../verification/s04-android.md) for implementation and specification synchronization status.

S01 implementation began on 2026-10-06 under [Issue #2](https://github.com/xinlx227-ai/Whatever/issues/2). See the [repository entry point](../../README.md) and [verification evidence](../verification/s01-android.md) for current executable work; the planning-only instructions below describe the earlier planning session.

This is historical planning context recording confirmed product decisions, superseded proposals, and remaining questions. The product specification and vertical-slice tracker now live in [GitHub issue #1](https://github.com/xinlx227-ai/Whatever/issues/1) and its child issues. Use those issues for current scope, acceptance criteria, and blocking relationships; reconcile this handoff when decisions change rather than maintaining competing specifications. Publication does not validate unresolved framework, recognition, content, or visual choices.

The product-boundary discussion is closed for this round: the user accepted the final batched boundary decisions and requested consolidation of the overall plan, page flows, and technical choices. Continue with the [overall planning synthesis](meal-app-overall-plan.md), which distinguishes accepted behavior from proposed organization and technical validation. Do not reopen confirmed choices without a concrete conflict or resume a sequence of minor approval questions. Explain genuinely unresolved proposals with examples. Continue planning, not app implementation, unless requested.

Latest confirmed decisions: Cards branches permanently by the round's target/requested count. A target of one keeps the result central with direct confirmation and replacement; a target above one retains tap-to-collect and a horizontally scrolling bottom result row, even with only one revealed result or early confirmation. Both use the exact selected celestial back, a browsable fan, and a central reveal area. See Drawing and presentation for face styling, motion, tutorial, and illustration decisions. Final on-device sizing and engineering integration remain to be validated.

Agent-facing documents are English; user-facing explanations and UI are Chinese. The Oct 9 single-target confirmation labels below are accepted; other UI strings remain working examples. The user explicitly said their timestamp example was a data example and expected polished presentation later.

## Product and release scope

- Help young adults end everyday indecision about what to eat, what to cook, and where to eat through an enjoyable decision experience.
- Deliver Android first, then adapt for iPhone. Plan for reuse of core logic, but no framework has been selected.
- Android v1 includes all three scenarios, wheel and card modes, an editable option library, and confirmed-choice history.
- No registration or login in v1. Custom data and history are stored locally. Cross-device synchronization is not part of the agreed scope.
- Group dining uses one shared phone, not rooms or multiple connected devices.
- Restaurant discovery/search nearby is deferred. Include built-in chain brands and allow manually added restaurants.
- Support future food knowledge-base integration; no source, hosted service, or algorithm has been adopted yet.

## Navigation and scenario boundaries

Bottom navigation, left to right: Option library (选项库), Decide (决定), History (足迹). Open on the central Decide page.

Flow: select a scenario, optionally adjust conditions, draw, then confirm or replace. Defaults make drawing possible without a mandatory setup questionnaire.

| Scenario | What a result means | Candidate content |
| --- | --- | --- |
| What to eat (吃什么) | One food or drink option, possibly a simple meal combination; a drink can be a standalone result | Yellow braised chicken with rice (黄焖鸡米饭), beef noodles (牛肉面), steamed soup buns (小笼包), soy milk (豆浆), burgers, pizza, fried chicken |
| What to cook (做什么) | One dish per draw; optionally collect several dishes for a meal | Home-cooked dishes, not automatically generated meal combinations |
| Where to eat (去哪吃) | A restaurant or chain brand | Built-in Haidilao (海底捞), KFC (肯德基), McDonald's (麦当劳), Pizza Hut (必胜客), plus user-added places |

The three pools are independent. Share draw behavior and history infrastructure, but do not automatically connect a drawn burger to a restaurant brand in v1. Built-in brands do not imply a nearby or available branch. A restaurant name is required when adding one; address and notes are optional.

## Meal periods

Choose a default by current time; users can manually select any period. Preserve the user's manual choice during current use rather than overwriting it as time changes.

| Period | Default interval |
| --- | --- |
| Breakfast (早餐) | 05:00–10:59 |
| Lunch (午餐) | 11:00–15:59 |
| Dinner (晚餐) | 16:00–20:59 |
| Late-night meal (夜宵) | 21:00–04:59 next day |

All food/dish options support one or more applicable meal periods: Breakfast, Lunch, Dinner, and Late-night meal. Built-in applicability is preset by the system and remains read-only under the display-only editing rule; for example, beef noodles may be eligible at both Lunch and Dinner. User-created food/dish forms use a multi-select control, with the current local-time period selected by default on creation. Users can add or remove selected periods, keeping at least one. This supersedes the earlier single-period restriction for both built-in and user-created food/dish options.

Restaurant brands and individual places use the same multi-select meal-period rule:

- Select one or more of Breakfast, Lunch, Dinner, and Late-night meal. At least one period is required.
- Built-in restaurants have preset applicable periods that users can edit.
- Creating a restaurant defaults to the current local-time period; users may select additional periods or change the selection.
- Applicability means the user is willing to draw that restaurant during the selected periods. It does not assert current opening hours or availability at a specific branch.

Meal-period multi-selection is independent of category membership: user-created options still have exactly one category.

### Initial built-in What to eat meal-period assignments

The following default assignments are confirmed for the discussed starter content. Apply them to individual built-in options, not as constraints on their categories. User-created options retain user-selected periods.

| Option group | Applicable periods |
| --- | --- |
| Rice meals (米饭套餐) | Lunch, Dinner |
| Noodles, rice/starch noodles, dumplings and wontons (面食、粉类、饺子馄饨) | Lunch, Dinner, Late-night meal |
| Steamed soup buns, jianbing, egg-filled flatbread (小笼包、煎饼果子、鸡蛋灌饼) | Breakfast, Lunch |
| Roujiamo (肉夹馍) | Breakfast, Lunch, Dinner |
| Pork and century egg congee, mixed-grain porridge, millet porridge, pumpkin porridge (皮蛋瘦肉粥、杂粮粥、小米粥、南瓜粥) | Breakfast, Dinner, Late-night meal |
| Vegetable salad, chicken breast with mixed-grain rice (蔬菜沙拉、鸡胸肉杂粮饭) | Lunch, Dinner |
| Tuna sandwich, egg and vegetable wrap (金枪鱼三明治、鸡蛋蔬菜卷) | Breakfast, Lunch, Dinner |
| Burger meals and pizza (汉堡套餐、披萨) | Lunch, Dinner |
| Fried chicken meal (炸鸡套餐) | Lunch, Dinner, Late-night meal |
| Soy milk, milk, soy beverage, yogurt (豆浆、牛奶、豆奶、酸奶) | Breakfast, Lunch, Dinner, Late-night meal |
## Categories and filters

- What to eat uses these initial food-type categories. Examples guide content curation; the complete built-in option list remains to be prepared:
  - Rice meals (米饭套餐): yellow braised chicken with rice, rice bowls with toppings.
  - Noodles (面食): beef noodles, mixed noodles, stir-fried noodles.
  - Rice noodles and other noodle varieties (粉类): rice noodles, luosifen, hot-and-sour starch noodles.
  - Dumplings and wontons (饺子馄饨): boiled dumplings, potstickers, wontons.
  - Buns and flatbreads (包点饼类): steamed buns, jianbing, roujiamo.
  - Porridge (粥类): pork and century egg congee (皮蛋瘦肉粥), mixed-grain porridge (杂粮粥), millet porridge (小米粥).
  - Light meals (轻食): vegetable salad (蔬菜沙拉), chicken breast with mixed-grain rice (鸡胸肉杂粮饭). Use these concrete examples instead of the vague label Light meal bowl (轻食碗).
  - Western fast food (西式快餐): burgers, pizza, fried chicken.
  - Drinks (饮品): soy milk (豆浆), milk (牛奶), soy beverage (豆奶), yogurt (酸奶). Each can be independently drawn and confirmed as a What to eat result; there is no required main-food draw or separate drink-pairing step. Keep 豆浆 and 豆奶 as the user's separately listed options, not an assumed alias pair.
- What to eat also provides All (全部) as a filter and Unclassified (未分类) as the fallback category; users can add custom categories.
- Separate steamed soup buns (小笼包) and soy milk (豆浆) into individual options instead of the previously illustrated buns-plus-soy-milk combination. A proposed 32-option starter list has been discussed but not approved as a complete set; the confirmed drink additions do not approve all other proposed entries.
- What to cook uses everyday categories: All (全部), Home-style (家常菜), Quick dishes (快手菜), Rice accompaniments (下饭菜), Light side dishes (清爽小菜), Soups (汤羹), Staple foods (主食). All is a filter, not an assigned category.
- Where to eat uses dining types: All, Hot pot (火锅), Barbecue (烧烤), Chinese food (中餐), Western food (西餐), Fast food (快餐), Buffet (自助餐).
- Category filters support multiple selections, taking their union. An option matching several selected categories enters the candidate pool once and gains no extra probability.
- Built-in dishes can belong to multiple system-maintained categories; users cannot edit their category membership. User-created options have exactly one editable category, including Unclassified (未分类) as the fallback.
- Budget, taste and dietary-exclusion filters were rejected for this version. Do not reintroduce optional price fields from earlier proposals as accepted scope.

### Yesterday filter

All three scenarios expose a selectable filter button with working copy “昨天选过的不选.” It is a filter control, not a separate settings switch.

When active, exclude the same options confirmed in that scenario during the previous calendar day, across all meal periods. Do not exclude an entire category: yesterday's beef noodles do not exclude other noodles. For a confirmed multi-dish meal, each dish counts. Records represent confirmed choices, not verified consumption. On first use, this filter is off. Persist the selected state across app restarts.

If local midnight occurs during an unfinished round, preserve the round-start date-dependent candidate scope through that round, including replacements. Existing batch uniqueness and explicit session exclusions still apply. Recompute yesterday filtering using the new local date when the next round starts. Midnight does not overwrite a manually selected meal period. Explicit round resets continue to follow their existing rules.

### Category management and recognition

- New category form offers three scenario choices and defaults to What to eat. Users can select What to cook or Where to eat. The category belongs only to that chosen scenario.
- Built-in categories can be renamed but not deleted. Custom categories can be renamed or deleted. Keep the Unclassified fallback available.
- Confirm deletion of a custom category; preserve its options and move them to Unclassified.
- Adding an option should infer a category from its name, not from the currently browsed category or entry point. Example: infer Home-style for Scallion tofu (小葱拌豆腐).
- Reliably recognized input maps to one existing category; uncertain input maps to Unclassified. Users can override the result or create a category. Manual choices take precedence over automatic classification.
- Automatic classification considers both built-in and user-created categories in the option's scenario. Assign one existing category only when the match is sufficiently reliable; otherwise use Unclassified. For example, Chicken breast salad (鸡胸肉沙拉) may map to a user-created Fitness meals (健身餐) category when supported by the recognition method. Subjective categories such as My favorites (我的最爱) require manual selection unless reliable evidence exists; the name alone does not establish membership.
- Preserve manual category choices against subsequent automatic classification. Future knowledge-base integration should improve recognition without changing this user flow.
- The user accepted custom-category recognition subject to implementation feasibility. The flow can support bounded category selection and an Unclassified fallback, but no recognition implementation or accuracy has been validated. Arbitrary custom category names are not guaranteed to be understood.

### Online and offline recognition

- Use online recognition when the phone has internet access and the user has agreed to its data transmission; otherwise use local recognition. This applies to both category inference and dish-alias duplicate detection. The rest of the app retains its local-data, no-account scope.
- Apply the same confirmed-match, uncertain-match, Unclassified fallback, and manual-choice rules in either mode. Offline recognition coverage depends on the bundled local data; online and offline recognition are not guaranteed to have equal coverage.
- If online recognition times out or fails, automatically fall back to local recognition instead of leaving the user waiting indefinitely. Keep option creation available: use Unclassified when classification remains uncertain and apply the existing uncertain-duplicate warning rule. When the online service recovers, do not automatically modify content the user has already saved. The timeout duration remains an implementation decision.
- Online recognition may transmit only the current food/restaurant name, current scenario and available category names, and same-scenario option names needed for duplicate detection. Do not transmit history, photos, restaurant addresses, or notes.
- Before the first use of online recognition, explain its purpose and the transmitted data scope and obtain the user's agreement. If the user declines, continue with offline recognition even when internet access is available. Connectivity alone does not authorize transmission.
- The online provider, local dataset, recognition method, and costs remain to be selected and validated. Online recognition does not require a web search for every input.

## Initial built-in What to cook content

The initial What to cook library contains 26 confirmed options: the 20 dishes below default to Lunch and Dinner, and the six additional options in the following table default to Breakfast and Late-night meal. The table records their accepted primary groupings, not exclusive category assignments; built-in dishes may have multiple system-maintained categories. Tomato scrambled eggs also belongs to Quick dishes and Rice accompaniments. Additional memberships remain to be curated.

| Category | Dishes |
| --- | --- |
| Home-style (家常菜) | Tomato scrambled eggs (番茄炒蛋), beef stew with potatoes (土豆炖牛肉), braised pork ribs (红烧排骨), steamed chicken with shiitake mushrooms (香菇滑鸡) |
| Quick dishes (快手菜) | Green pepper scrambled eggs (青椒炒蛋), hot-and-sour shredded potatoes (酸辣土豆丝), garlic broccoli (蒜蓉西兰花), hand-torn cabbage (手撕包菜) |
| Rice accompaniments (下饭菜) | Kung pao chicken (宫保鸡丁), fish-fragrant shredded pork (鱼香肉丝), mapo tofu (麻婆豆腐), twice-cooked pork (回锅肉) |
| Light side dishes (清爽小菜) | Smashed cucumber salad (拍黄瓜), wood ear mushroom salad (凉拌木耳), scallion tofu (小葱拌豆腐), shredded three-ingredient salad (凉拌三丝) |
| Soups (汤羹) | Seaweed egg-drop soup (紫菜蛋花汤), winter melon and pork rib soup (冬瓜排骨汤), corn and pork rib soup (玉米排骨汤), mushroom tofu soup (菌菇豆腐汤) |

The following six additional options are confirmed. They represent food the user will prepare; matching names in What to eat remain independent options in that scenario. The category memberships below are confirmed; built-in options can retain multiple memberships.

| Additional option | Categories | Applicable periods |
| --- | --- | --- |
| Steamed egg custard (鸡蛋羹) | Soups | Breakfast, Late-night meal |
| Egg pancake (鸡蛋饼) | Staple foods, Quick dishes | Breakfast, Late-night meal |
| Tomato and egg noodles (番茄鸡蛋面) | Staple foods | Breakfast, Late-night meal |
| Greens and egg noodles (青菜鸡蛋面) | Staple foods | Breakfast, Late-night meal |
| Millet porridge (小米粥) | Staple foods | Breakfast, Late-night meal |
| Pumpkin porridge (南瓜粥) | Staple foods | Breakfast, Late-night meal |

## Initial built-in Where to eat content

The following 12 brands and dining-type assignments are confirmed as initial draw candidates. Inclusion does not assert that a nearby branch exists or is available. Users can deactivate unsuitable brands and add local restaurants. The default meal periods below are confirmed draw-applicability settings, not claims about actual opening hours; users can edit them.

| Dining type | Brands | Applicable periods |
| --- | --- | --- |
| Hot pot (火锅) | Haidilao (海底捞), Xiabuxiabu (呷哺呷哺) | Lunch, Dinner, Late-night meal |
| Barbecue (烧烤) | Wooden House Barbecue (木屋烧烤), Long Ago Lamb Skewers (很久以前羊肉串) | Dinner, Late-night meal |
| Chinese food (中餐) | Xibei (西贝莜面村), Grandma's Home (外婆家) | Lunch, Dinner |
| Western food (西餐) | Pizza Hut (必胜客), Saizeriya (萨莉亚) | Lunch, Dinner |
| Fast food (快餐) | KFC (肯德基), McDonald's (麦当劳) | Breakfast, Lunch, Dinner, Late-night meal |
| Buffet (自助餐) | Big Pizza (比格比萨), Han Ba Wei De (汉巴味德) | Lunch, Dinner |

## Drawing and presentation

### Confirmed visual direction

- Wheel mode uses a bright, playful visual style. Card mode uses the selected black-purple and gold celestial artwork described below. Historical illustrated tarot decks were not the desired direction; the chosen design uses flat ornamental linework rather than sculpted gems or futuristic armor.
- The Decide page changes atmosphere with the draw mode. Keep scenario, meal-period, filter, and navigation locations consistent across modes.
- Option library and History also follow the current mode's background palette, with readable matching text and controls, while retaining their layouts.
- First launch defaults to the wheel. Later launches remember the last-used draw mode and its visual style.
- A throwaway browser prototype exists at `prototype/visual-directions/index.html`, served with `node prototype/visual-directions/server.cjs`. A/B/C were exploratory alternatives; the prototype has not yet been adapted to the confirmed mode-driven theme. Its one-item rounds and sample content do not replace the agreed product rules.

### Selected card-back artwork

![Selected black-purple and gold celestial card back](../design/assets/card-back-celestial-black-purple-gold.png)

- Canonical asset: [`docs/design/assets/card-back-celestial-black-purple-gold.png`](../design/assets/card-back-celestial-black-purple-gold.png). This is the exact generated image selected by the user, preserved without cropping, recoloring, or resampling.
- Purpose: the concealed back of selectable cards in card-draw mode across all three scenarios. It is not a food-result face or an app cover screen.
- Palette: near-black and subdued dark purple background with fine warm-gold lines. Exact UI color tokens remain to be derived during interface design.
- Visual language: a central radial star/astronomical wheel, mirrored crescent moons, constellation dots, curling filigree, and a thin ornamental frame. Preserve the flat engraved-line appearance and balanced composition.
- Theme relationship: build the card-mode Decide page around this palette. Option library and History follow its background palette while keeping their layouts; text, icons, and controls must remain readable. The wheel retains its distinct playful theme.
- Provenance: generated with the built-in image_gen tool using the user's attached navy-and-gold celestial image as the visual reference. The user chose the resulting black-purple version, then authorized project storage. The earlier three generated alternatives are not selected project assets.
- Status: the asset is selected and archived. The A/B/C prototype has not been updated to consume it or the card interaction rules below. The 2026-10-09 face and motion directions below are approved; implementation and final on-device sizing remain unverified.

### Card-face content

- All three scenarios show the option name with a simple illustration and omit category labels from the card face: food/dish names for What to eat and What to cook, restaurant names for Where to eat. Use a dark-purple face, fine gold border, light name text, and a warm light illustration region.
- All three scenarios provide optional image selection in the option library's create/edit form: show an illustration preview and a Select image (选择图片) button beneath the name field. The button selects an image from the phone's photo library. Users can change the image later by editing the option; drawing displays the configured image.
- When the user has not selected an image, the system automatically assigns a built-in illustration by food/dish or dining type: for example, a noodle bowl for noodles, a rice bowl for rice meals, or a small hot-pot storefront for hot-pot restaurants. Use a generic plate for unrecognized food/dishes and a generic storefront for unrecognized restaurants. Keep the assigned default stable for the same option rather than randomizing it on each display. Built-in illustrations are automatic defaults, not a user-facing illustration picker; this does not imply runtime image generation or unique artwork for every option.
- S08 retains the current food drawings and supplies missing generic plate/storefront and dining-type shop illustrations. The user delegated their design to the implementation agent. A user-selected image takes priority over the automatic default. This scope is approved artwork work, not evidence that the assets have been created.

### Draw rules

- Every eligible unique option has equal probability. No weights or preference boosts in v1.
- Large candidate pools retain all eligible options. In wheel mode, omit some name labels when needed for readability without reducing the draw pool or changing probabilities; display the complete winning result after the wheel stops. In card mode, each candidate has one face-down card in the horizontally browsable fan. Off-screen cards remain part of the pool and can be browsed into view and selected.
- Both modes are available in every scenario: a spinning wheel and tarot-like face-down cards that the user picks and flips to reveal a result. Tarot describes the reveal interaction, not divination content.
- Lock the presentation mode when the first card begins to flip or the user presses the wheel's start control. Before the first reveal begins, selecting an unrevealed card still permits switching to the wheel; switching cancels that selection. While locked, tapping the other mode leaves results and progress intact and explains that the current draw must finish first. Unlock after the current round ends.
- Only What to cook shows a requested-count control. Place it below the category filters and above the wheel or card group, with One dish (1 道), Two dishes (2 道), Three dishes (3 道), and Custom (自定义) choices. Default to one; custom counts range from 1 to 10. What to eat and Where to eat draw one result per round and do not show this control. Results within a batch are distinct. If the requested count exceeds available candidates, follow the candidate-shortage rule below.
- Changing the requested count during a started round follows the condition-change rule: ask to restart, then apply the new count and clear the round's results and progress while preserving session exclusions if confirmed. Cancel preserves the previous count and round.
- Wheel: one user press draws one dish; never automatically run all rounds. Remove each drawn option from the current wheel, retain it in the result area, and show progress such as 1/3. Removal is batch-local, not deletion or persistent deactivation.
- Cards: use a fan-shaped card group (扇形牌组) with overlapping backs and horizontal browsing. Draw up to the requested dish count, without repeated dishes in the batch.
- The first tap raises/selects a card while keeping its back visible. A second tap on that selected card reveals it. Tapping another unrevealed card lowers the previous selection and raises the new one; tapping blank space outside the card group cancels the selection.
- Horizontal fan scrolling only browses cards. Preserve the selected card's identity even when it moves off-screen; scrolling does not reveal, cancel selection, or reshuffle.
- Only revealing a card counts toward draw progress. Selecting, changing selection, or canceling an unrevealed card consumes no draw slot.
- Card-page layout: place the fan at the top and the reveal/detail area centrally. On first tap, the selected card moves slightly toward the center while remaining face down. On second tap, it moves to the center, enlarges and flips. On small screens, allow vertical page scrolling while preserving a large card, a fully readable name, and usable touch areas. Keep confirmation above bottom navigation.
- Branch the card interaction by the round's target/requested count, never by current revealed count or implementation phase. Target one: keep the revealed card central with direct confirmation and Replace (换一个); omit collection interaction and the bottom result row. Target above one: tapping the central revealed card shrinks and collects it into one horizontally scrolling row of small cards; tapping a collected card reopens that same result. Use no separate collect button or automatic collection timer. Collection and reopening consume no slot and write no history. This multi-target flow remains in effect when only one result has been revealed or the user confirms early.
- Use one confirmation button, disabled before any result. Single-target labels are “就吃这个,” “就做这 1 道菜,” and “就去这家” for the respective scenarios. Multi-target cooking labels follow the actual revealed count, such as “就做这 2 道菜.” Allow confirmation before reaching the requested count, in either mode; an uncollected central result is already eligible for confirmation.
- Confirming the chosen dishes saves the record to History, shows a brief saved-to-history notice, and returns the draw page to its initial draw state, completing the round. Clear the completed round's displayed results and progress, and release its mode lock. Preserve the selected scenario, meal period, filters, requested draw count, saved history, and existing session exclusions. Do not add an intermediate retained-results screen or a Draw again button after confirmation.
- Clear the round only after history persistence succeeds. If saving fails, preserve the current results and show a failure notice with a retry action. Prevent repeated confirmation while saving, and ensure retries create at most one history record for that confirmation. This applies to all scenarios and both draw modes.
- Each dish in a multi-dish result can be replaced independently while the others remain.
- In card mode, show Replace (换一个) beside the central result and use the replacement prompt below. For multi-target rounds, reopen a small result card centrally to replace that existing slot; keep replacement access in the central area. Single-target rounds replace directly from the central result.
- If a requested count exceeds available candidates, explain the actual count and offer drawing that count or adjusting filters. Do not silently add ineligible options.

### Card motion and first-use guidance

- Use approximately 0.2 seconds for selection, 0.7–0.9 seconds for the reveal movement/enlargement/flip, and 0.3 seconds for collection in multi-target rounds only. Provide light haptic feedback and no sound. Reduced motion preserves every manual selection, reveal, confirmation, and replacement step.
- The first-use tutorial accompanies real actions: browse/select, second tap to reveal, then confirm or replace for a single-target round. It is skippable and has no separate demo. Completing or skipping it suppresses future automatic tutorial runs; afterward use brief contextual hints. The single-target tutorial teaches its own flow without a collection step.
- S08 engineering must preserve requested count while staging later multi-target work. Hiding cooking counts or forcing one dish on mode switching was not approved. Resolve slice integration without silently changing the target or applying the single-target layout to a multi-target round.

## Replacement, exclusions and interruption

Keep these scopes distinct:

| Mechanism | Lifetime |
| --- | --- |
| Drawn-item removal | Current batch, to avoid duplicates |
| User's temporary exclusion after replacement | Current app session, across scenario/meal switches; restore on closing and reopening the app |
| Long-term deactivation in library | Until the user manually reactivates the option |
| Yesterday filter | Derived from qualifying history while the filter is active |

Tapping replace (换一个) opens a simple two-choice prompt with button labels Redraw (重新抽) and Exclude it (排除它). Apply the physical-card model:

- Redraw returns the outgoing option to the eligible draw pool, reshuffles, and draws one replacement. Drawing the same option again immediately is allowed.
- Exclude it removes the outgoing option for the current app session, reshuffles the remaining eligible pool, and draws one replacement. This is temporary exclusion, not deletion from the library.
- Other results already drawn in the batch stay in place and outside the replacement pool, preserving batch uniqueness. Both actions replace one result rather than adding a result slot, and retain the existing equal-probability and filter rules.

Keep Redraw versus Exclude it as the replacement decision; do not add another prompt choosing manual versus automatic replacement. In card mode, after either action applies its pool rule and reshuffles, the user personally selects a replacement from the fan-shaped face-down card group. Reuse the established interaction: first tap selects a card, second tap reveals it in the center. Do not automatically select or reveal a replacement. The replacement fills the original result slot rather than adding a dish; other drawn results remain unchanged and unavailable in the replacement pool. A single-target replacement stays central with direct confirmation/replacement actions. In a multi-target round, tapping the revealed replacement collects it into the original position in the bottom result row. Once the user chooses Redraw or Exclude it and replacement begins, that replacement cannot be canceled and the outgoing result cannot be restored through an undo action. Do not provide Cancel replacement or rollback of the selected exclusion as a cancellation path. The user must draw the replacement to complete that slot. Existing whole-round abandonment and restart rules still apply; they do not restore the outgoing result. Detailed reshuffle animation timing remains unresolved.

In wheel mode, the user opens Replace for an existing result, chooses Redraw or Exclude it, then explicitly presses the wheel's start control to draw its replacement from the updated pool. Do not start the replacement spin automatically. The new result fills the original slot; other results stay unchanged and the drawn count does not increase. The same no-cancellation rule applies after replacement begins. When no alternative is available, either action only explains the shortage and system Back dismisses the prompt without changing the round, as specified below.
Only one result may be undergoing replacement at a time, in either mode. Until its replacement result is drawn, prevent replacing another result, drawing an additional dish, or confirming the meal. Switching to Option library or History and back preserves the pending replacement unless a saved library change or history-record deletion invalidates the round. Whole-round abandonment, condition changes, library edits, and app lifecycle events follow their existing preservation or reset rules; a round reset clears the pending replacement without restoring the outgoing result.
App lifecycle defines the session boundary:

- Switching to another app or locking the screen preserves the unfinished round, draw progress, mode lock, and temporary exclusions when the app remains running.
- Removing the app from recent tasks, force-stopping it, or OS reclamation ends the session. Reopening starts at the initial draw state, discards unconfirmed results and progress, releases the round's mode lock, and clears temporary exclusions. The user accepts losing an unfinished round after OS reclamation even without deliberately closing the app.
- On a fresh launch, open Decide with What to eat selected, derive the meal period from the current local time, select All categories, and reset the What to cook requested count to one. These startup defaults apply after a session-ending event; returning to the still-running app or switching tabs follows the existing preservation rules.
- Restarting preserves the option library, confirmed history, and preferences already designated as persistent: the last-used draw mode and yesterday-filter state. Unconfirmed results never become history on restart.
- Confirmation, scenario switching, and returning to the initial draw state within the same session preserve temporary exclusions.

Changing filters, scenario, or meal period during a round prompts that the change requires restarting the draw. Cancel preserves the prior selections, results, and progress. Confirm applies the requested change, clears results, and resets progress while preserving explicit session exclusions. This supersedes locking all filter changes.

Switching bottom tabs to Option library or History preserves an unfinished round's results and progress; returning to Decide resumes it. Tab navigation does not confirm the round or write history. This differs from explicitly abandoning a round to return to the initial draw state, which asks whether to continue or abandon. Unconfirmed results never enter history.

Android system Back, including the back gesture, follows this order:

- Dismiss the current transient layer or return from an editing page first. Prompt before discarding unsaved edits.
- From the Option library or History root page, return to Decide and resume any unfinished round.
- From Decide after drawing has started, ask whether to abandon the round, with Continue drawing (继续抽选) and Abandon (放弃) actions. Continue preserves the round. Abandon clears unconfirmed results and progress, releases the mode lock, and returns to the initial draw state while preserving session exclusions.
- From Decide before drawing has started, return to the phone's home screen. Returning while the app remains running preserves the current state; a fresh app launch follows the lifecycle reset rule above. Selecting an unrevealed card alone does not count as starting the draw.

Any actual saved change to the option library invalidates an unfinished round, including option creation, deletion, activation, deactivation, name/image/address/note edits, meal-period changes, and category management, even in another scenario. Returning to Decide shows a notice that the library changed, clears unconfirmed results and progress, releases the mode lock, and returns to the initial draw state using the updated library. Preserve session exclusions. Browsing, canceling an edit, or saving without an actual content change preserves the round. This supersedes the earlier distinction between related and unrelated library changes.

If no alternative option is eligible to replace a result after excluding other already-drawn results, tapping either Redraw or Exclude it only shows an explanation that no other replacement is available. Keep both actions tappable for this feedback rather than disabling them. Do not start replacement, remove the outgoing result, or apply a temporary exclusion in this case. Android system Back dismisses the replacement prompt and returns to the unchanged round. This preflight failure is not cancellation of a started replacement. It also applies when Redraw could only return the outgoing option; when alternatives exist, the usual Redraw rule still allows drawing that same option again.
If no candidates remain, offer adjusting conditions or restoring session exclusions. Keep long-term deactivations intact. Restoring exclusions does not promise candidates will exist if other filters still rule them out.

## Option library

- Provide built-in content and user-created options.
- Built-in options cannot be deleted and can be deactivated and reactivated. Built-in food/dish edits are limited to display information, such as names and images; their system-maintained category membership is read-only. This supersedes unrestricted editing of built-in food/dish options. Restaurant meal-period editing remains governed by the separately confirmed restaurant rule.
- Custom options can be edited and deleted. Deleting one removes it from the library and draw pool while retaining backing data for existing history references.
- Food/dish names are required. For user-created food/dish options, classification is inferred as described above and applicable meal periods are editable through multi-selection. Built-in food/dish editing follows the display-only restriction above.
- Prevent duplicates within the same scenario on both creation and rename, including confidently recognized alternate names for the same dish. For example, Tomato scrambled eggs (番茄炒蛋 / 西红柿炒蛋) represents one dish: block the duplicate and offer access to the existing option, with no add-anyway override for a confirmed match. Cross-scenario pools remain independent.
- Similar wording alone does not establish dish identity: tomato scrambled eggs and tomato egg soup are different dishes. For an uncertain match, show a possible-duplicate warning with View existing (查看已有) and Add anyway (仍然添加) actions. Let the user proceed despite the uncertain match; mandatory blocking applies only to confirmed matches.
- Deactivated options still participate in duplicate detection within their scenario. A confirmed match blocks creating a second option, explains that the existing option is deactivated, and offers View (查看) and Reactivate (重新启用). Deactivation changes draw eligibility, not option identity.
- When adding a dish confidently matches a deleted custom option in the same scenario, prompt to restore that original option instead of creating a new identity. Restoration retains its history references and eligibility for yesterday filtering: deleting and restoring yesterday's confirmed dish does not bypass the active filter. An uncertain match may still be created as a new option under the warning rule above.
- For name comparison, trim leading/trailing whitespace, collapse consecutive internal spaces to one, compare English letters case-insensitively, and equate full-width and half-width forms. Preserve internal word boundaries instead of deleting all spaces. Punctuation and other wording differences require alias recognition rather than unconditional equality. For display, retain the entered name except for leading/trailing whitespace trimming. These rules complement dish-identity recognition.
- Renaming an option preserves its food identity: allow spelling corrections and alternate names, but not changing it into a different food under the original identity and history references. If recognition clearly identifies a different food, block the rename and suggest creating a separate option. If identity cannot be determined, ask the user to confirm that it is still the same food before saving. This rule applies to built-in and user-created food/dish options, in addition to duplicate checks.
- The recognition mechanism and alias-data source remain unresolved; an alias table is a proposal, not an adopted implementation.
- Built-in food/dish edit forms display category membership as read-only; editing the name or image preserves those memberships. User-created option forms retain a single editable category.

### Settings entry

- Place a Settings entry at the top right of Option library. Keep the existing three bottom-navigation destinations: Option library, Decide, and History.
- Settings includes an Online recognition (在线识别) toggle so users can enable or disable online recognition later. Disabling it uses local recognition. Enabling it without prior agreement first presents the existing purpose and data-transmission explanation and obtains agreement before any online transmission.

### Library search and activation filters

- Provide a search field in each of the three scenario libraries. Search option names and confidently recognized aliases; for example, searching 西红柿炒蛋 can find the existing 番茄炒蛋 option.
- Search only the currently selected scenario. Switching scenarios changes the searched library to that scenario.
- By default, display active options. Provide Deactivated (已停用) and All (全部) status filters as well; All includes active and deactivated options, not deleted ones.
- Deleted options are absent from ordinary library search. Adding a matching option follows the existing restoration and uncertain-match rules.

## History

- Default to records from all scenarios, ordered by confirmation time from newest to oldest and grouped by date.
- Provide scenario filters for What to eat, What to cook, and Where to eat.
- Display a confirmed multi-dish meal as one record. Tapping a record opens its complete contents; record deletion follows the whole-record confirmation rule below.
- The first version does not include a calendar view, statistical charts, or check-in streaks.

- Automatically record date/time, result and scenario when the user confirms. Spinning or revealing alone creates no record.
- Confirmed multi-dish cooking results form one meal record with multiple referenced options and one confirmation time.
- History references option identities and displays updated option information. Renaming an option updates its display in older records; timestamps remain unchanged. Yesterday filtering continues to recognize the same option after renaming.
- Delete whole history records after confirmation. No per-dish deletion inside a multi-dish record in v1. Deleted records no longer contribute to yesterday filtering.
- Any completed history-record deletion invalidates an unfinished draw, regardless of the deleted record's date or scenario and whether the yesterday filter is active. On returning to Decide, restart at the initial draw state, clearing unconfirmed results, progress, pending replacement, and the round's mode lock while preserving session exclusions. Merely viewing history or canceling deletion preserves the round.
- Preserve history when a custom option is deleted, through retained reference data. Storage implementation is not fixed.
- Polish history presentation and Chinese copy during design. The user's example “September 20, 14:00, chose yellow braised chicken” specifies information, not final wording or layout.

## Superseded proposals: do not restore

- Only one scenario in v1 → all three scenarios are included.
- Both platforms in the initial release → Android first, iPhone later.
- Dining out starts empty → built-in chain brands plus custom places.
- Dinner spans the entire night → four periods including late-night meals.
- Temporary exclusion resets at confirmation/scene exit → resets at app close and reopen.
- Automatic consecutive wheel spins → one explicit press per dish.
- Allow switching wheel/cards mid-round → locked with an explanatory prompt.
- Lock all filters mid-round → permit changes after restart confirmation.
- Immutable built-in options → built-in food/dish display information is editable, category membership is system-maintained, and deletion is unavailable; activation controls remain available.
- Historical name snapshots → live option references with updated display.
- Infer category from the library view / use Other (其他) → infer from input, otherwise Unclassified.
- Multiple categories for every user-created option → one category for user-created options.

## Research and remaining work

Competitor evidence: [Meal-decision app landscape](../research/meal-decision-app-landscape.md). Its initial direction suggestions predate these decisions and do not override them. Official listing claims were checked, but apps were not installed or usability-tested.

Food-data sources examined during discussion:

- [CookBook-KG](https://github.com/ngl567/CookBook-KG): Chinese recipe graph; candidate source, not approved for integration. Data coverage, licensing and fitness still require investigation.
- [Wikidata Food project](https://www.wikidata.org/wiki/Wikidata:WikiProject_Food): potential structured food knowledge; Chinese coverage not verified.
- [USDA FoodData Central](https://fdc.nal.usda.gov/api-guide/): predominantly nutrition-oriented, less directly aligned with everyday dish categories.

The 2026-10-09 Cards decisions above close the S08 design discussion. The next session may implement S08 using current [Issue #1](https://github.com/xinlx227-ai/Whatever/issues/1) and [Issue #9](https://github.com/xinlx227-ai/Whatever/issues/9), preserving the S09/S10 boundaries and existing replacement/save contracts. This documentation session does not implement or validate them. Artwork creation, on-device layout/motion/accessibility checks, and the staging integration choice remain engineering work. Earlier unresolved inventory/framework notes are historical; consult formal issues and delivered verification reports for their current status.
