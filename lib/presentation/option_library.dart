import 'package:flutter/material.dart';

import '../application/meal_controller.dart';
import '../domain/meal.dart';
import 'category_manager.dart';
import 'option_art.dart';
import 'option_editor.dart';
import 'online_recognition_settings.dart';
import 'scenario_selector.dart';

class OptionLibrary extends StatefulWidget {
  const OptionLibrary({
    super.key,
    required this.controller,
    this.scenario = MealScenario.eat,
    this.onScenarioChanged,
  });
  final MealController controller;
  final MealScenario scenario;
  final ValueChanged<MealScenario>? onScenarioChanged;
  @override
  State<OptionLibrary> createState() => _OptionLibraryState();
}

class _OptionLibraryState extends State<OptionLibrary> {
  String query = '';
  LibraryStatus status = LibraryStatus.active;
  String? error;
  bool busy = false;
  MealController get model => widget.controller;

  Future<void> edit([FoodOption? option]) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OptionEditor(
          controller: model,
          option: option,
          scenario: widget.scenario,
        ),
      ),
    );
  }

  Future<void> mutate(FoodOption food, {bool delete = false}) async {
    if (busy || model.isBusy) return;
    if (delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这个选项？'),
          content: Text('“${food.name}”将从选项库移除，已有足迹会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除选项'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = delete
          ? await model.deleteOption(food.id)
          : await model.setOptionActive(food.id, !food.isActive);
      if (mounted && !result.succeeded) setState(() => error = result.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final foods = model.libraryOptions(
      scenario: widget.scenario.name,
      query: query,
      status: status,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          children: [
            const Expanded(
              child: Text(
                '每一餐的灵感',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              key: const Key('library-settings'),
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      OnlineRecognitionSettingsPage(controller: model),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '留下喜欢的，让下一餐多一点期待。',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        ScenarioSelector(
          page: 'library',
          selected: widget.scenario,
          onSelected: busy || model.isBusy ? null : widget.onScenarioChanged,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('create-option'),
              onPressed: busy || model.isBusy ? null : () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('添加选项'),
            ),
            OutlinedButton.icon(
              key: const Key('manage-categories'),
              onPressed: busy || model.isBusy
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryManager(
                          controller: model,
                          scenario: widget.scenario,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.category_outlined),
              label: const Text('分类管理'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('library-search'),
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            labelText: '搜索${widget.scenario.label}',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in {
              LibraryStatus.active: '已启用',
              LibraryStatus.inactive: '已停用',
              LibraryStatus.all: '全部',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: status == entry.key,
                onSelected: (_) => setState(() => status = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${foods.length} 个选项',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        if (foods.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              widget.scenario == MealScenario.restaurant
                  ? '暂时没有符合条件的餐厅，试试其他筛选或添加一家喜欢的。'
                  : '暂时没有符合条件的选项，试试其他筛选或添一道喜欢的。',
            ),
          ),
        for (final food in foods)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 0,
              color: dark ? colors.surfaceContainer : const Color(0xfffffdf8),
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: dark ? colors.outlineVariant : const Color(0xffe9ddcb),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OptionArt(option: food, size: 64),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                food.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${food.categories.join(' / ')} · ${food.isBuiltIn ? '内置' : '自选'} · ${food.isActive ? '已启用' : '已停用'}',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                MealPeriod.values
                                    .where(food.periods.contains)
                                    .map((period) => period.label)
                                    .join(' · '),
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              if (food.address != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  food.address!,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (food.notes != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  food.notes!,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          key: ValueKey('edit-${food.id}'),
                          onPressed: busy || model.isBusy
                              ? null
                              : () => edit(food),
                          child: const Text('编辑'),
                        ),
                        TextButton(
                          key: ValueKey('toggle-${food.id}'),
                          onPressed: busy || model.isBusy
                              ? null
                              : () => mutate(food),
                          child: Text(food.isActive ? '停用' : '启用'),
                        ),
                        if (!food.isBuiltIn)
                          TextButton(
                            key: ValueKey('delete-${food.id}'),
                            onPressed: busy || model.isBusy
                                ? null
                                : () => mutate(food, delete: true),
                            child: const Text('删除'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
