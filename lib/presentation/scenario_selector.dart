import 'package:flutter/material.dart';

import '../domain/meal.dart';
import 'wheel.dart';

class ScenarioSelector extends StatelessWidget {
  const ScenarioSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.page,
  });

  final MealScenario selected;
  final ValueChanged<MealScenario>? onSelected;
  final String page;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final scenario in MealScenario.values)
        ChoiceChip(
          key: ValueKey('$page-scenario-${scenario.name}'),
          label: Text(scenario.label),
          selected: selected == scenario,
          onSelected: onSelected == null ? null : (_) => onSelected!(scenario),
          selectedColor: soft,
          showCheckmark: false,
          side: BorderSide(
            color: selected == scenario ? accent : const Color(0xffd6c6b3),
          ),
          labelStyle: TextStyle(color: selected == scenario ? accent : muted),
        ),
    ],
  );
}
