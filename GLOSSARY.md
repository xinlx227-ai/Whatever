# Meal decisions

The language of choosing a meal and retaining explicit choices. The current product specification lives in GitHub issue #1.

## Language

**Option (选项)**: One independently selectable food, dish, or place in a scenario. Its identity remains the same when its display name changes.

**Scenario (场景)**: The question answered by a draw: What to eat (吃什么), What to cook (做什么), or Where to eat (去哪吃).

**Meal period (餐段)**: Breakfast (早餐), Lunch (午餐), Dinner (晚餐), or Late-night meal (夜宵). An option may apply to several periods.

**Eligible pool (候选池)**: The distinct options allowed by the current scenario and conditions. Each option has equal selection probability.

**Round (轮次)**: An unfinished decision under selected conditions, beginning when drawing starts and ending on confirmation or abandonment.

**Result (结果)**: A revealed option in an unfinished round. A result is not a history record.

**Confirmation (确认)**: The user's explicit decision to retain the current results as one choice.

**History record (足迹记录)**: One successfully saved confirmation and its ordered options. It records a choice, not proof that a meal was eaten.

**Session (会话)**: One running app process and its temporary decisions. Leaving a tab or temporarily backgrounding the app does not end it.
