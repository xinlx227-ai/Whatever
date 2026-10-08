import 'package:flutter/material.dart';

import '../application/meal_controller.dart';
import '../domain/meal.dart';
import 'scenario_selector.dart';
import 'wheel.dart';

class CategoryManager extends StatefulWidget {
  const CategoryManager({
    super.key,
    required this.controller,
    this.scenario = MealScenario.eat,
  });

  final MealController controller;
  final MealScenario scenario;

  @override
  State<CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends State<CategoryManager> {
  late MealScenario scenario = widget.scenario;
  bool busy = false;
  bool asking = false;
  String? error;
  MealController get model => widget.controller;

  Future<void> edit([MealCategory? category]) async {
    if (busy || asking || model.isBusy) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _CategoryEditor(controller: model, category: category),
      ),
    );
  }

  Future<void> delete(MealCategory category) async {
    if (busy || asking || model.isBusy) return;
    setState(() => asking = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个分类？'),
        content: Text(
          '“${category.name}”中的选项会移到“${model.fallbackCategory(category.scenario).name}”，选项与已有足迹都会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除分类'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => asking = false);
    if (confirmed != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await model.deleteCategory(category.id);
      if (mounted && !result.succeeded) setState(() => error = result.message);
    } catch (_) {
      if (mounted) setState(() => error = '暂时无法删除分类，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final locked = busy || asking || model.isBusy;
      final categories = model.categoriesFor(scenario);
      return PopScope(
        canPop: !busy && !asking && !model.isBusy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('分类管理'),
            leading: IconButton(
              tooltip: '返回',
              onPressed: locked ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      '让灵感各归其位',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '按场景整理分类，下次挑选更轻松。',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 24),
                    ScenarioSelector(
                      page: 'categories',
                      selected: scenario,
                      onSelected: locked
                          ? null
                          : (value) => setState(() {
                              scenario = value;
                              error = null;
                            }),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const Key('create-category'),
                        onPressed: locked ? null : () => edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('添加分类'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '内置分类可改名；保留一个兜底分类，接住暂时未归类的选项。',
                      style: TextStyle(color: muted, height: 1.5),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    if (busy) ...[
                      const SizedBox(height: 16),
                      Semantics(liveRegion: true, child: const Text('正在删除分类…')),
                    ],
                    const SizedBox(height: 24),
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category.name,
                                  key: ValueKey('category-name-${category.id}'),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  category.isFallback
                                      ? '兜底分类 · 始终保留'
                                      : category.isBuiltIn
                                      ? '内置分类'
                                      : '自建分类',
                                  style: const TextStyle(color: muted),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    TextButton(
                                      key: ValueKey(
                                        'rename-category-${category.id}',
                                      ),
                                      onPressed: locked
                                          ? null
                                          : () => edit(category),
                                      child: const Text('改名'),
                                    ),
                                    if (!category.isBuiltIn &&
                                        !category.isFallback)
                                      TextButton(
                                        key: ValueKey(
                                          'delete-category-${category.id}',
                                        ),
                                        onPressed: locked
                                            ? null
                                            : () => delete(category),
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
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.controller, this.category});
  final MealController controller;
  final MealCategory? category;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.category?.name ?? '');
  late MealScenario scenario = widget.category?.scenario ?? MealScenario.eat;
  bool busy = false;
  bool asking = false;
  bool leaving = false;
  String? error;
  bool get dirty =>
      name.text != (widget.category?.name ?? '') ||
      scenario != (widget.category?.scenario ?? MealScenario.eat);

  @override
  void initState() {
    super.initState();
    name.addListener(refresh);
    widget.controller.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(refresh);
    name.removeListener(refresh);
    name.dispose();
    super.dispose();
  }

  void finish() {
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> close() async {
    if (busy || asking || widget.controller.isBusy) return;
    asking = true;
    final discard =
        !dirty ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('放弃未保存的修改？'),
                content: const Text('这次填写的分类还没有保存。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('放弃修改'),
                  ),
                ],
              ),
            ) ==
            true;
    asking = false;
    if (mounted && discard) finish();
  }

  Future<void> save() async {
    if (busy ||
        asking ||
        widget.controller.isBusy ||
        !form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.controller.saveCategory(
        id: widget.category?.id,
        name: name.text,
        scenario: scenario,
      );
      if (!mounted) return;
      if (result.succeeded) {
        finish();
      } else {
        setState(() => error = result.message);
      }
    } catch (_) {
      if (mounted) setState(() => error = '暂时无法保存分类，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = busy || asking || widget.controller.isBusy;
    return PopScope(
      canPop: leaving || (!dirty && !locked),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.category == null ? '添加分类' : '分类改名'),
          leading: IconButton(
            tooltip: '返回',
            onPressed: locked ? null : close,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '所属场景',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      if (widget.category == null)
                        ScenarioSelector(
                          page: 'category-editor',
                          selected: scenario,
                          onSelected: locked
                              ? null
                              : (value) => setState(() => scenario = value),
                        )
                      else
                        Text(scenario.label),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('category-name'),
                        controller: name,
                        enabled: !locked,
                        decoration: const InputDecoration(
                          labelText: '分类名称',
                          hintText: '例如：周末想吃的',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请填写分类名称。'
                            : null,
                      ),
                      if (widget.category != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          '改名会同步更新选项所属分类，已有足迹会保留。',
                          style: TextStyle(color: muted, height: 1.5),
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      FilledButton(
                        key: const Key('save-category'),
                        onPressed: locked ? null : save,
                        child: Text(busy ? '正在保存…' : '保存分类'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
