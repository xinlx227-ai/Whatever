import 'package:flutter/material.dart';

import '../domain/meal.dart';

class CategoryFilterSelection {
  const CategoryFilterSelection(this.ids, this.period, this.excludeYesterday);
  final Set<String> ids;
  final MealPeriod period;
  final bool excludeYesterday;
}

class CategoryFilterSheet extends StatefulWidget {
  const CategoryFilterSheet({
    super.key,
    required this.categories,
    required this.selectedIds,
    required this.period,
    required this.excludeYesterday,
  });

  final List<MealCategory> categories;
  final Set<String> selectedIds;
  final MealPeriod period;
  final bool excludeYesterday;

  @override
  State<CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<CategoryFilterSheet> {
  late final Set<String> ids = {...widget.selectedIds};
  late MealPeriod period = widget.period;
  late bool excludeYesterday = widget.excludeYesterday;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '选择条件',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '取消筛选',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('餐段'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final value in MealPeriod.values)
                ChoiceChip(
                  key: ValueKey('filter-period-${value.name}'),
                  label: Text(value.label),
                  selected: period == value,
                  onSelected: (_) => setState(() => period = value),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('分类（可多选）', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('符合任一分类即可；同时属于多个分类，也只算一个候选。'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                key: const Key('filter-all'),
                label: const Text('全部'),
                selected: ids.isEmpty,
                onSelected: (_) => setState(ids.clear),
              ),
              for (final category in widget.categories)
                FilterChip(
                  key: ValueKey('filter-category-${category.id}'),
                  label: Text(category.name),
                  selected: ids.contains(category.id),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      ids.add(category.id);
                    } else {
                      ids.remove(category.id);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilterChip(
            key: const Key('filter-yesterday'),
            label: const Text('昨天选过的不选'),
            selected: excludeYesterday,
            onSelected: (value) => setState(() => excludeYesterday = value),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('apply-category-filters'),
            onPressed: () => Navigator.pop(
              context,
              CategoryFilterSelection(Set.of(ids), period, excludeYesterday),
            ),
            child: const Text('应用条件'),
          ),
        ],
      ),
    ),
  );
}
