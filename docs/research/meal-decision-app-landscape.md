# Meal-decision app landscape

Research date: 2026-10-03 (Asia/Shanghai).

Planning update (2026-10-04): the proposals below are historical research suggestions. Read [the planning handoff](../planning/meal-app-handoff.md) for subsequent user-confirmed decisions and the current discussion frontier.

## Purpose and evidence boundary

Inform the first product-direction discussion for a mobile app that helps young adults choose everyday meals. A roulette wheel is a proposed interaction, not a confirmed requirement. The user requested research before detailed discussion or implementation.

A researcher subagent investigated official store listings and first-party websites. The root checked the linked sources and integrated this report. No apps were installed or tested. Features below are publisher claims, not verified runtime behavior. Storefront visibility does not establish availability for a particular user's account, device, or region. This survey does not establish demand, retention, willingness to pay, or decision effectiveness.

## Documented examples

| Example and primary source | Documented behavior | Design lesson (inference) | Availability caveat |
| --- | --- | --- | --- |
| [Lunch roulette (午餐转盘 - 今天吃什么)](https://play.google.com/store/apps/details?hl=zh&id=com.nfm.aval004) | Preset breakfast/lunch/dinner/takeout/dining-out packs; custom dishes or stores; disable entries; roulette; actual-eaten calendar; result sharing; map handoff. | Seed the pool, allow practical exclusions, distinguish the drawn result from what was actually eaten. | Android Google Play listing with Chinese localization; mainland distribution was not verified. |
| [What to eat: random dishes (今天吃什么：随机选菜)](https://apps.apple.com/cn/app/今天吃什么-随机选菜/id6774045721) | Record ingredients, dishes, takeout and restaurants; custom preference tags; flip-card selection; keep/replace/save dishes; record eaten food. Global dish discovery and cuisine filters are also listed. | Compare personal familiar choices with discovery; a card reveal is an alternative to a wheel. | Chinese App Store listing, iOS 17+; global catalogue is described as available in supported regions. |
| [What to eat (吃个啥)](https://apps.apple.com/cn/app/吃个啥/id1632794552) | Randomly chooses a nearby restaurant. Detailed filters, rejection feedback and history are not documented in the listing. | A very narrow location-based decision flow is possible, but local data coverage becomes central. | iPhone listing; regional restaurant coverage was not verified. |
| [Spinowheel Random Food Generator](https://spinowheel.com/random-food-generator) | Editable food entries; meal/cuisine/craving filters; wheel selection; no-repeat control; remove a drawn result. The website explicitly does not evaluate restaurant availability. | Filter before drawing; remove an unsuitable result before another draw. | Browser reference; runtime and mobile usability were not tested. |
| [Food-Roulette](https://apps.apple.com/us/app/food-roulette/id6779062643) | Current/custom location, distance and cuisine filters; custom restaurant wheel; favorites, hide/skip and personal ratings; Maps handoff. Version 1.7 notes describe a 24-hour exclusion after “Not today.” | Temporary rejection and permanent dislike need different meanings. A result should support a next action. | US App Store reference; iOS 26.5+ and English listed. Group dining is a stated use case, not evidence of shared voting. |
| [Potto - meal planner](https://apps.apple.com/us/app/potto-meal-planner/id6778760884) | Weekly planning using store, budget, dietary needs and appliances; optional fridge photo; meal swaps, favorites, recipes and shopping list. | An adjacent planning flow connects constraints to an actionable result, but solves a broader problem than choosing this meal. | English iPhone listing with subscription features; local supermarket coverage was not verified. |

[Mealime's official homepage](https://www.mealime.com/) currently announces shutdown on October 21, 2026. It was excluded from active-product recommendations.

## Interaction references to inspect

These are documented flows to examine, not completed usability tests:

1. Personal food pool: inspect the What to eat: random dishes listing for saved choices, tags, flip-card selection and eaten records.
2. Wheel rejection: inspect Spinowheel for filtering, spinning, removing a result and avoiding repeats.
3. Nearby restaurant action: inspect Food-Roulette for distance/cuisine filters, “Not today,” and Maps handoff.

## Proposed direction, pending user discussion

Help a young adult choose one acceptable, practically available meal quickly from a manageable set of options. Start the discussion with everyday solo takeout/canteen meals; this audience and setting are recommendations, not user decisions.

Proposed loop: choose meal context → apply a few exclusions → draw one candidate → accept or reject with a lightweight reason → record the actual choice.

The design hypothesis is that accepted results matter more than the spectacle of randomization. Existing products already document custom pools, filters and rejection, so those features alone are not demonstrated differentiation. A possible emphasis is reducing repeated indecision through a well-curated local/personal pool and useful rejection feedback. This remains unvalidated.

For example, “not spicy today” could exclude spicy entries for this decision, while “never suggest this” could persistently exclude one entry. This behavior requires sufficiently reliable candidate tags; it should not be assumed from dish names alone.

Suggested evaluation: time to an accepted choice, number of redraws, whether the accepted result was actually eaten, and voluntary reuse at subsequent meals. No numeric targets or market claims are established yet.

## Decision frontier

First discuss which setting is primary: everyday takeout/canteen, home cooking, or group restaurant choice. These imply different candidate data and different completion criteria.

Then clarify whether a successful result is a food category, a dish, or a specific restaurant-and-dish choice; how much initial list setup is acceptable; and whether novelty or familiarity matters more.

Platform/distribution, candidate data sourcing, monetization, richer personalization and group coordination remain later questions. No architecture or MVP scope has been accepted. Use GitHub Issues as the canonical decision tracker after the user and root agree the wayfinding destination; this report is evidence, not a substitute decision map.
