import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../application/meal_controller.dart';
import '../domain/meal.dart';
import 'wheel.dart';
import 'option_art.dart';
import 'option_library.dart';
import 'option_editor.dart';
import 'scenario_selector.dart';
import 'scenario_copy.dart';
import 'category_filter_sheet.dart';

class MealApp extends StatelessWidget {
  const MealApp({
    super.key,
    required this.controller,
    this.recoveredImage,
    this.imageRecoveryNotice,
  });
  final MealController controller;
  final String? recoveredImage;
  final String? imageRecoveryNotice;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '这一餐',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        surface: paper,
        primary: accent,
        onSurface: ink,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    ),
    home: _MealHome(
      controller: controller,
      recoveredImage: recoveredImage,
      imageRecoveryNotice: imageRecoveryNotice,
    ),
  );
}

class _CookingCountDialog extends StatefulWidget {
  const _CookingCountDialog({required this.initialCount});
  final int initialCount;

  @override
  State<_CookingCountDialog> createState() => _CookingCountDialogState();
}

class _CookingCountDialogState extends State<_CookingCountDialog> {
  late final TextEditingController input;
  String? error;

  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: '${widget.initialCount}');
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void submit() {
    final count = int.tryParse(input.text.trim());
    if (count == null || count < 1 || count > 10) {
      setState(() => error = '请输入 1 到 10 之间的整数');
      return;
    }
    Navigator.pop(context, count);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('这一餐做几道？'),
    content: TextField(
      key: const Key('custom-cooking-count-input'),
      controller: input,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => submit(),
      decoration: InputDecoration(
        labelText: '菜数',
        helperText: '可以选择 1–10 道菜',
        errorText: error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        key: const Key('apply-custom-cooking-count'),
        onPressed: submit,
        child: const Text('确定'),
      ),
    ],
  );
}

class _MealHome extends StatefulWidget {
  const _MealHome({
    required this.controller,
    this.recoveredImage,
    this.imageRecoveryNotice,
  });
  final MealController controller;
  final String? recoveredImage;
  final String? imageRecoveryNotice;
  @override
  State<_MealHome> createState() => _MealHomeState();
}

class _MealHomeState extends State<_MealHome>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController spin;
  late final CurvedAnimation curve;
  int tab = 1;
  MealScenario libraryScenario = MealScenario.eat;
  final completionKey = GlobalKey();
  final resultsKey = GlobalKey();
  double fromAngle = 0, toAngle = 0;
  bool asking = false;
  MealController get model => widget.controller;
  ScenarioCopy get scenarioCopy => ScenarioCopy.forScenario(model.scenario);
  bool get pinCookingActions =>
      tab == 1 &&
      model.scenario == MealScenario.cook &&
      MediaQuery.sizeOf(context).height >= 700 &&
      MediaQuery.textScalerOf(context).scale(14) <= 18;

  @override
  void initState() {
    super.initState();
    spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    curve = CurvedAnimation(parent: spin, curve: const Cubic(.12, .64, .13, 1));
    model.addListener(modelChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => recoverImage());
  }

  Future<void> recoverImage() async {
    if (!mounted) return;
    if (widget.imageRecoveryNotice != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.imageRecoveryNotice!)));
    }
    if (widget.recoveredImage == null) return;
    final use = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('找回了刚才选择的图片'),
        content: const Text(
          '应用重新打开了，未保存的表单没有保留。可以用这张图片新建选项；如需修改已有选项，请回选项库重新编辑。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后再选'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('用图片新建'),
          ),
        ],
      ),
    );
    if (use == true && mounted) {
      selectTab(0);
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => OptionEditor(
            controller: model,
            scenario: libraryScenario,
            initialImagePath: widget.recoveredImage,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(modelChanged);
    curve.dispose();
    spin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) showCompletion();
  }

  void modelChanged() {
    if (!model.hasRound) resetWheel();
    if (model.restartNotice != null) showRestartNotice();
  }

  void showRestartNotice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || tab != 1) return;
      final notice = model.takeRestartNotice();
      if (notice == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notice)));
    });
  }

  void selectTab(int value) {
    setState(() => tab = value);
    if (value == 1) {
      showCompletion();
      showRestartNotice();
    }
  }

  Future<void> draw() async {
    if (model.isBusy || model.isDrawing || asking) return;
    if (model.hasCandidateShortage) {
      final available = model.availableCount;
      final useAvailable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('这次的菜还不够'),
          content: Text('当前条件下只有 $available 道菜，可以改为抽 $available 道，或调整筛选条件。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('调整筛选条件'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('改为 $available 道'),
            ),
          ],
        ),
      );
      if (!mounted || model.isBusy) return;
      if (useAvailable == true) {
        model.changeCookingCount(available);
      } else if (useAvailable == false) {
        await selectCategories();
      }
      return;
    }
    model.startDraw();
    if (!model.isDrawing) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    fromAngle = toAngle % (math.pi * 2);
    final target =
        math.pi * 2 -
        (model.selectedIndex! + .5) * math.pi * 2 / model.candidates.length;
    toAngle =
        fromAngle + math.pi * 2 * 7 + (target - fromAngle) % (math.pi * 2);
    spin.duration = reduced
        ? const Duration(milliseconds: 180)
        : const Duration(seconds: 4);
    try {
      await spin.forward(from: 0).orCancel;
      if (!mounted || !model.isDrawing) return;
      model.finishDraw();
      showCompletion();
      // Android's platform feedback honors the user's system haptic setting.
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
        await HapticFeedback.lightImpact();
      }
    } on TickerCanceled {
      /* Abandonment cancels the visual reveal. */
    }
  }

  void showCompletion() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || tab != 1 || model.result == null) return;
      final target = pinCookingActions
          ? resultsKey.currentContext
          : completionKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<bool> ask(String title, String message, String action) async {
    if (asking) return false;
    asking = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('继续这一餐'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      asking = false;
    }
  }

  void resetWheel() {
    spin.stop(canceled: true);
    spin.value = 0;
    fromAngle = toAngle = 0;
  }

  Future<void> selectPeriod(MealPeriod period) async {
    if (period == model.period || model.isBusy) return;
    if (model.hasRound &&
        !await ask('换个餐段？', '当前还未确认的选择会清空，再为你准备这一餐。', '切换并重新开始')) {
      return;
    }
    if (!mounted || model.isBusy) return;
    resetWheel();
    model.changePeriod(period);
  }

  Future<void> selectScenario(MealScenario scenario) async {
    if (scenario == model.scenario || model.isBusy) return;
    if (model.hasRound &&
        !await ask('换个场景？', '当前还未确认的选择会清空，再为你准备这一餐。', '切换并重新开始')) {
      return;
    }
    if (!mounted || model.isBusy) return;
    resetWheel();
    model.changeScenario(scenario);
  }

  Future<void> selectCookingCount(int count) async {
    if (count == model.cookingCount || model.isBusy || asking) return;
    if (model.hasRound &&
        !await ask('换个菜数？', '当前还未确认的菜会清空，按新的菜数重新开始。', '更改并重新开始')) {
      return;
    }
    if (!mounted || model.isBusy) return;
    resetWheel();
    model.changeCookingCount(count);
  }

  Future<void> customCookingCount() async {
    if (model.isBusy || asking) return;
    final count = await showDialog<int>(
      context: context,
      builder: (context) =>
          _CookingCountDialog(initialCount: model.cookingCount),
    );
    if (count != null && mounted) await selectCookingCount(count);
  }

  Future<void> confirm() async {
    if (await model.confirm() && mounted) {
      resetWheel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(scenarioCopy.confirmationNotice),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> selectCategories() async {
    if (model.isBusy || asking) return;
    final selection = await showModalBottomSheet<CategoryFilterSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: CategoryFilterSheet(
          categories: model.categoriesFor(model.scenario),
          selectedIds: model.selectedCategoryIds,
          period: model.period,
        ),
      ),
    );
    if (selection == null || !mounted || model.isBusy) return;
    final unchanged =
        selection.period == model.period &&
        selection.ids.length == model.selectedCategoryIds.length &&
        selection.ids.containsAll(model.selectedCategoryIds);
    if (unchanged) return;
    if (model.hasRound &&
        !await ask('更换筛选条件？', '当前还未确认的选择会清空，按新条件重新开始。', '应用并重新开始')) {
      return;
    }
    if (!mounted || model.isBusy) return;
    model.changeCategoryFilters(selection.ids, period: selection.period);
  }

  Future<void> back() async {
    if (tab != 1) {
      selectTab(1);
      return;
    }
    if (model.isBusy) return;
    if (model.hasRound &&
        await ask(
          '先放下这一餐？',
          model.error != null
              ? '上次保存结果尚未确认。建议返回重试；放弃会清空当前选择，已保存的足迹仍会保留。'
              : '放弃后，这次未确认的选择不会记入足迹。',
          '放弃这次选择',
        )) {
      if (mounted) model.abandon();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => PopScope(
      canPop: tab == 1 && !model.hasRound && !model.isBusy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                key: ValueKey('page-$tab'),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '这一餐',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: soft,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            tab == 0
                                ? libraryScenario.label
                                : '${model.period.label} · ${model.scenario.label}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    if (tab == 1)
                      ...decide()
                    else if (tab == 0)
                      ...library()
                    else
                      ...history(),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pinCookingActions)
              SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: completion(),
                  ),
                ),
              ),
            NavigationBar(
              backgroundColor: paper,
              indicatorColor: soft,
              selectedIndex: tab,
              onDestinationSelected: selectTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  label: '选项库',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  label: '决定',
                ),
                NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  label: '足迹',
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> decide() => [
    SizedBox(height: model.scenario == MealScenario.cook ? 12 : 24),
    if (model.scenario != MealScenario.cook) ...[
      const Text(
        '好好吃饭 · 好好生活',
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(height: 8),
    ],
    Text(
      scenarioCopy.heading,
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
    ),
    if (model.scenario != MealScenario.cook) ...[
      const SizedBox(height: 8),
      const Text(
        '把纠结留给转盘，把期待留给下一口。',
        style: TextStyle(color: muted, fontSize: 13),
      ),
    ],
    const SizedBox(height: 12),
    ScenarioSelector(
      page: 'decide',
      selected: model.scenario,
      onSelected: model.isBusy ? null : selectScenario,
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: MealPeriod.values
          .map(
            (period) => ChoiceChip(
              key: ValueKey('decide-period-${period.name}'),
              label: Text(period.label),
              selected: model.period == period,
              onSelected: model.isBusy ? null : (_) => selectPeriod(period),
              selectedColor: soft,
              showCheckmark: false,
              side: BorderSide(
                color: model.period == period
                    ? accent
                    : const Color(0xffd6c6b3),
              ),
              labelStyle: TextStyle(
                color: model.period == period ? accent : muted,
              ),
            ),
          )
          .toList(),
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('category-filter-button'),
              onPressed: model.isBusy ? null : selectCategories,
              icon: const Icon(Icons.filter_list),
              label: Text(
                model.selectedCategoryIds.isEmpty
                    ? '全部分类'
                    : '已选 ${model.selectedCategoryIds.length} 个分类',
              ),
            ),
          ),
        ),
        Text(
          '${model.availableCount} 个候选',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ),
    if (model.scenario == MealScenario.cook) ...[
      const SizedBox(height: 8),
      const Text('这一餐，做几道？', style: TextStyle(fontWeight: FontWeight.w700)),
      Wrap(
        key: const Key('cooking-count-controls'),
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final count in [1, 2, 3])
            ChoiceChip(
              key: ValueKey('cooking-count-$count'),
              label: Text('$count 道'),
              selected: model.cookingCount == count,
              onSelected: model.isBusy
                  ? null
                  : (_) => selectCookingCount(count),
            ),
          ChoiceChip(
            key: const Key('cooking-count-custom'),
            label: Text(
              model.cookingCount > 3 ? '${model.cookingCount} 道 · 自定义' : '自定义',
            ),
            selected: model.cookingCount > 3,
            onSelected: model.isBusy ? null : (_) => customCookingCount(),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Semantics(
        liveRegion: true,
        child: Text(
          '已选 ${model.results.length} / ${model.requestedCount} 道 · 每次转一道',
          key: const Key('cooking-progress'),
          style: const TextStyle(color: muted),
        ),
      ),
    ],
    Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              (MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(context).vertical -
                      // Reserve both control rows, confirmation and navigation.
                      604)
                  .clamp(186.0, 330.0),
        ),
        child: AnimatedBuilder(
          animation: curve,
          builder: (context, _) => MealWheel(
            options: model.candidates,
            centerLabel: scenarioCopy.wheelLabel,
            angle: MediaQuery.disableAnimationsOf(context) && model.isDrawing
                ? toAngle
                : fromAngle + (toAngle - fromAngle) * curve.value,
          ),
        ),
      ),
    ),
    Semantics(
      key: resultsKey,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: model.scenario == MealScenario.cook && model.results.isNotEmpty
            ? Column(
                children: [
                  for (var index = 0; index < model.results.length; index++)
                    Padding(
                      key: ValueKey('cooking-result-$index'),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            '${index + 1}',
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(width: 12),
                          OptionArt(option: model.results[index], size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              model.results[index].name,
                              key: index == model.results.length - 1
                                  ? const Key('draw-result')
                                  : null,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (model.isDrawing)
                    const Text('下一道正在挑选…', style: TextStyle(color: muted)),
                ],
              )
            : model.result == null
            ? Center(
                child: Text(
                  model.isDrawing ? '让好胃口，再转一会儿…' : '不必想好答案，转一下就知道。',
                  style: const TextStyle(color: muted),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OptionArt(option: model.result!, size: 64),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scenarioCopy.resultHint,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        Text(
                          model.result!.name,
                          key: const Key('draw-result'),
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (model.scenario == MealScenario.restaurant &&
                            model.result!.address != null)
                          Text(
                            model.result!.address!,
                            style: const TextStyle(color: muted),
                          ),
                        if (model.scenario == MealScenario.restaurant &&
                            model.result!.notes != null)
                          Text(
                            model.result!.notes!,
                            style: const TextStyle(color: muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    ),
    if (model.error != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          liveRegion: true,
          child: Text(model.error!, style: const TextStyle(color: accent)),
        ),
      ),
    if (model.candidates.isEmpty && !model.hasRound) ...[
      const Text('没有符合条件的选项', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('试试其他分类或餐段，也可以恢复本次排除的选项。已停用的选项仍会保持停用。'),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            key: const Key('adjust-empty-conditions'),
            onPressed: model.isBusy ? null : selectCategories,
            child: const Text('调整条件'),
          ),
          TextButton(
            key: const Key('restore-session-exclusions'),
            onPressed: model.isBusy || model.sessionExclusions.isEmpty
                ? null
                : model.restoreSessionExclusions,
            child: const Text('恢复本次排除'),
          ),
        ],
      ),
    ],
    if (!pinCookingActions) ...completion(),
  ];

  List<Widget> completion() => [
    if (model.scenario == MealScenario.cook &&
        model.results.isNotEmpty &&
        model.results.length < model.requestedCount)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton(
          key: const Key('draw-next-dish'),
          onPressed: model.canDraw ? draw : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: Text(model.isDrawing ? '正在挑选下一道…' : '再转一道'),
        ),
      ),
    FilledButton(
      key: const Key('primary-action'),
      onPressed: model.isDrawing || model.isBusy
          ? null
          : model.result == null
          ? draw
          : confirm,
      child: Text(
        model.isSaving
            ? '正在记下这一餐…'
            : model.isDrawing
            ? '正在挑选…'
            : model.result != null
            ? model.error != null
                  ? '重试保存'
                  : model.scenario == MealScenario.cook
                  ? '就做这 ${model.results.length} 道菜'
                  : scenarioCopy.confirmAction
            : scenarioCopy.drawAction,
      ),
    ),
    const SizedBox(height: 12),
    Center(
      key: completionKey,
      child: Text(
        model.result != null ? '确认之后，才会记入足迹' : '一点小期待，一顿好好吃的饭',
        style: const TextStyle(color: muted, fontSize: 12),
      ),
    ),
  ];

  Widget foodArt(String type, double size) => ExcludeSemantics(
    child: SvgPicture.asset('assets/food/$type.svg', width: size, height: size),
  );

  List<Widget> library() => [
    OptionLibrary(
      controller: model,
      scenario: libraryScenario,
      onScenarioChanged: (scenario) =>
          setState(() => libraryScenario = scenario),
    ),
  ];

  List<Widget> history() {
    final widgets = <Widget>[
      const SizedBox(height: 32),
      const Text(
        '好好吃饭的足迹',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text('记下每一次不再纠结的决定。', style: TextStyle(color: muted)),
      const SizedBox(height: 24),
    ];
    if (model.history.isEmpty) {
      widgets.add(
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                foodArt('rice', 120),
                const SizedBox(height: 24),
                const Text(
                  '第一餐，值得期待',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text('确认一次选择，就会在这里留下足迹。', style: TextStyle(color: muted)),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => selectTab(1),
                  child: const Text('去决定这一餐'),
                ),
              ],
            ),
          ),
        ),
      );
      return widgets;
    }
    String? previousDate;
    for (final entry in model.history) {
      final time = entry.confirmedAt.toLocal();
      final date = '${time.year}年${time.month}月${time.day}日';
      if (previousDate != date) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              date,
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ),
        );
        previousDate = date;
      }
      widgets.add(
        Container(
          key: ValueKey('history-${entry.operationId}'),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xffe9ddcb))),
          ),
          child: Row(
            children: [
              OptionArt(option: entry.option, size: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.options.map((option) => option.name).join('、'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} · ${entry.period.label} · ${MealScenario.fromKey(entry.option.scenario).label}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }
}
