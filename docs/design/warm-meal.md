# Warm meal visual implementation

Authority: [S01 decisions](https://github.com/xinlx227-ai/Whatever/issues/2). The selected direction is Warm meal (温暖的一餐), variant A of the historical browser prototype. Alternative B and the browser's timing controls are comparison tools, not application settings.

The Android implementation places an illustrated pastel wheel between a left-aligned meal heading and a full-width confirmation action. The same paper surface, food drawings, and type hierarchy continue through the editable library and date-grouped history. S04 adds wrapping scenario controls above the meal-period controls, independent scenario selection in the library, and optional restaurant address/notes in the editor. Later drawing modes and management capabilities remain tracked in the parent specification.

| Token | Value | Role |
| --- | --- | --- |
| Paper | `#FFFAF1` | Application background |
| Ink | `#372E25` | Primary Chinese text |
| Orange | `#B94320` | Primary actions and selection |
| Muted | `#776658` | Supporting text |
| Soft | `#F4E9D8` | Selected navigation and chips |
| Outline | `#E9DDCB` | Decorative separators |

Use Android's system Chinese sans-serif font, with bold 28–30 logical-pixel headings, 16–18 pixel content, and 12–13 pixel supporting labels. Controls retain platform touch targets. Content scrolls above the fixed bottom navigation; enlarged text switches the library to one column.

The seven food SVGs are adapted from the reviewed prototype. They remain local assets and require no network fetch. Unrecognized food/dishes use a plate icon and restaurants use a storefront icon; optional user images take precedence. Wheel sector names are decorative duplicates; result and library names remain normal accessible text. Pools above six candidates use radial labels without removing candidates.

One explicit draw chooses from the complete eligible pool before the animation begins. The wheel rotates for approximately four seconds and stops at that choice. Reduced motion reveals the same choice without spinning. Stopping uses light platform haptic feedback, without audio. Physical feedback quality requires phone testing.
