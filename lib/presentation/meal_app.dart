import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../application/meal_controller.dart';
import '../domain/meal.dart';
import '../domain/meal_preferences.dart';
import 'card_draw.dart';
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final cards = controller.preferences.mode == DrawMode.cards;
      final background = cards ? const Color(0xff100d18) : paper;
      final foreground = cards ? const Color(0xfff6eddf) : ink;
      final primary = cards ? const Color(0xffdec183) : accent;
      final colors =
          ColorScheme.fromSeed(
            brightness: cards ? Brightness.dark : Brightness.light,
            seedColor: primary,
            surface: background,
            primary: primary,
            onPrimary: cards ? const Color(0xff21192e) : Colors.white,
            onSurface: foreground,
          ).copyWith(
            onSurfaceVariant: cards ? const Color(0xffc7bbd5) : muted,
            surfaceContainer: cards ? const Color(0xff2a1d3e) : soft,
            outlineVariant: cards
                ? const Color(0xff6d587c)
                : const Color(0xffd6c6b3),
          );
      return MaterialApp(
        title: '这一餐',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        theme: ThemeData(
          useMaterial3: true,
          brightness: colors.brightness,
          scaffoldBackgroundColor: background,
          colorScheme: colors,
          textTheme: ThemeData.light().textTheme.apply(
            bodyColor: foreground,
            displayColor: foreground,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: background,
            foregroundColor: foreground,
            systemOverlayStyle: cards
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: colors.onPrimary,
              minimumSize: const Size(double.infinity, 56),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
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
    },
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController spin;
  late final AnimationController cardReveal;
  late final CurvedAnimation curve;
  int tab = 1;
  MealScenario libraryScenario = MealScenario.eat;
  final completionKey = GlobalKey();
  final resultsKey = GlobalKey();
  final pendingReplacementKey = GlobalKey();
  final activeShortageKey = GlobalKey();
  double fromAngle = 0, toAngle = 0;
  bool asking = false;
  MealController get model => widget.controller;
  bool get cardsMode => model.preferences.mode == DrawMode.cards;
  Color get paper => Theme.of(context).colorScheme.surface;
  Color get accent => Theme.of(context).colorScheme.primary;
  Color get muted => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get soft => Theme.of(context).colorScheme.surfaceContainer;
  ScenarioCopy get scenarioCopy => ScenarioCopy.forScenario(model.scenario);
  bool get hasActiveCookingShortage =>
      model.scenario == MealScenario.cook &&
      model.hasRound &&
      model.results.isNotEmpty &&
      model.results.length < model.requestedCount &&
      model.pendingReplacementIndex == null &&
      !model.isDrawing &&
      !model.isBusy &&
      !model.hasConfirmationAttempt &&
      model.availableCount < model.requestedCount - model.results.length;
  bool get pinCookingActions =>
      tab == 1 &&
      !cardsMode &&
      model.scenario == MealScenario.cook &&
      MediaQuery.sizeOf(context).height >= 700 &&
      MediaQuery.textScalerOf(context).scale(14) <= 18;

  @override
  void initState() {
    super.initState();
    spin = AnimationController(vsync: this, duration: Duration(seconds: 4));
    cardReveal = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    curve = CurvedAnimation(parent: spin, curve: Cubic(.12, .64, .13, 1));
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
        title: Text('找回了刚才选择的图片'),
        content: Text('应用重新打开了，未保存的表单没有保留。可以用这张图片新建选项；如需修改已有选项，请回选项库重新编辑。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('稍后再选'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('用图片新建'),
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
    cardReveal.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      model.refreshCardAvailability();
      showCompletion();
    }
  }

  void modelChanged() {
    if (!model.hasRound) {
      resetWheel();
      cardReveal.stop(canceled: true);
      cardReveal.value = 0;
    }
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
          title: Text('这次的菜还不够'),
          content: Text('当前条件下只有 $available 道菜，可以改为抽 $available 道，或调整筛选条件。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('调整筛选条件'),
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
        ? Duration(milliseconds: 180)
        : Duration(seconds: 4);
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

  Future<void> revealCard() async {
    if (asking || !model.revealSelectedCard()) return;
    cardReveal.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration(milliseconds: 120)
        : Duration(milliseconds: 800);
    try {
      await cardReveal.forward(from: 0).orCancel;
      if (!mounted || !model.isDrawing) return;
      model.finishDraw();
      showCompletion();
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (tab == 1 &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
        await HapticFeedback.lightImpact();
      }
    } on TickerCanceled {
      // A shared restart cancels the visual reveal and its unsaved round.
    }
  }

  Future<void> selectMode(DrawMode mode) async {
    if (mode == model.preferences.mode || model.isBusy) return;
    if (model.isModeLocked) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('这一餐已经开始，确认或重新开始后才能切换模式。')));
      return;
    }
    await model.updatePreferences(model.preferences.copyWith(mode: mode));
  }

  void showCompletion() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          tab != 1 ||
          (model.result == null && model.pendingReplacementIndex == null)) {
        return;
      }
      final target = pinCookingActions
          ? model.pendingReplacementIndex != null
                ? pendingReplacementKey.currentContext
                : hasActiveCookingShortage
                ? activeShortageKey.currentContext
                : resultsKey.currentContext
          : completionKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Duration(milliseconds: 250),
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
                  child: Text('继续这一餐'),
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
    final completeTutorial = cardsMode;
    if (await model.confirm() && mounted) {
      if (completeTutorial) await model.dismissCardTutorial();
      if (!mounted) return;
      resetWheel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(scenarioCopy.confirmationNotice),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> replace(int index) async {
    if (asking || !model.canReplace(index)) return;
    final outgoingName = model.results[index].name;
    asking = true;
    String? shortage;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) {
            void choose(ReplacementChoice choice) {
              if (model.beginReplacement(index, choice)) {
                Navigator.pop(dialogContext);
              } else {
                updateDialog(() => shortage = model.error);
              }
            }

            return AlertDialog(
              title: Text('换一个？'),
              scrollable: true,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('替换「$outgoingName」，其他选择会保留。'),
                  SizedBox(height: 12),
                  Text('重新抽：放回候选，可能再次抽中。\n排除它：这次使用应用期间不再抽中。'),
                  SizedBox(height: 12),
                  Text(
                    cardsMode
                        ? '选择后请重新选牌，再点一次翻开；也可以重新开始整餐。'
                        : '选择后请手动开始替换，不能撤销；也可以重新开始整餐。',
                  ),
                  if (shortage != null) ...[
                    SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        shortage!,
                        key: Key('replacement-shortage'),
                        style: TextStyle(color: accent),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('暂时不换'),
                ),
                TextButton(
                  key: Key('replacement-redraw'),
                  onPressed: () => choose(ReplacementChoice.redraw),
                  child: Text('重新抽'),
                ),
                TextButton(
                  key: Key('replacement-exclude'),
                  onPressed: () => choose(ReplacementChoice.exclude),
                  child: Text('排除它'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      asking = false;
    }
    if (!mounted || model.pendingReplacementIndex == null) return;
    resetWheel();
    showCompletion();
  }

  Future<void> restartRound() async {
    if (model.isBusy || !model.hasRound) return;
    if (!await ask('重新开始这一餐？', '当前未确认的选择会清空，本次排除仍会保留。', '清空并重新开始')) {
      return;
    }
    if (mounted && !model.isBusy) model.abandon();
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
          model.hasConfirmationAttempt && model.error != null
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
              constraints: BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                key: ValueKey('page-$tab'),
                padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: cardsMode && tab == 1
                      ? model.cancelCardSelection
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
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
                            padding: EdgeInsets.symmetric(
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
                              style: TextStyle(fontSize: 13),
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
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pinCookingActions)
              SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
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
              destinations: [
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
      Text(
        '好好吃饭 · 好好生活',
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      SizedBox(height: 8),
    ],
    Text(
      scenarioCopy.heading,
      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.3),
    ),
    if (model.scenario != MealScenario.cook) ...[
      SizedBox(height: 8),
      Text(
        cardsMode ? '把答案藏进卡牌，把期待留给下一口。' : '把纠结留给转盘，把期待留给下一口。',
        style: TextStyle(color: muted, fontSize: 13),
      ),
    ],
    SizedBox(height: 12),
    ScenarioSelector(
      page: 'decide',
      selected: model.scenario,
      onSelected: model.isBusy ? null : selectScenario,
    ),
    SizedBox(height: 8),
    Wrap(
      spacing: 12,
      children: [
        for (final mode in DrawMode.values)
          ChoiceChip(
            key: ValueKey('draw-mode-${mode.name}'),
            label: Text(mode == DrawMode.wheel ? '转盘' : '抽卡'),
            selected: model.preferences.mode == mode,
            onSelected: model.isBusy ? null : (_) => selectMode(mode),
            showCheckmark: false,
          ),
      ],
    ),
    SizedBox(height: 8),
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
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
              labelStyle: TextStyle(
                color: model.period == period ? accent : muted,
              ),
            ),
          )
          .toList(),
    ),
    SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('category-filter-button'),
              onPressed: model.isBusy ? null : selectCategories,
              icon: Icon(Icons.filter_list),
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
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ),
    if (model.scenario == MealScenario.cook) ...[
      SizedBox(height: 8),
      Text('这一餐，做几道？', style: TextStyle(fontWeight: FontWeight.w700)),
      Wrap(
        key: Key('cooking-count-controls'),
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
            key: Key('cooking-count-custom'),
            label: Text(
              model.cookingCount > 3 ? '${model.cookingCount} 道 · 自定义' : '自定义',
            ),
            selected: model.cookingCount > 3,
            onSelected: model.isBusy ? null : (_) => customCookingCount(),
          ),
        ],
      ),
      SizedBox(height: 8),
      Semantics(
        liveRegion: true,
        child: Text(
          model.pendingReplacementIndex == null
              ? '已选 ${model.results.length} / ${model.requestedCount} 道 · ${cardsMode ? '亲手翻开卡牌' : '每次转一道'}'
              : '待替换第 ${model.pendingReplacementIndex! + 1} 道 · 其他选择已保留',
          key: Key('cooking-progress'),
          style: TextStyle(color: muted),
        ),
      ),
    ],
    if (cardsMode)
      ...cardDecision()
    else ...[
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                (MediaQuery.sizeOf(context).height -
                        MediaQuery.paddingOf(context).vertical -
                        // Reserve both control rows, confirmation and navigation.
                        660)
                    .clamp(136.0, 330.0),
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
          padding: EdgeInsets.symmetric(vertical: 16),
          child: model.results.isNotEmpty
              ? Column(
                  children: [
                    for (var index = 0; index < model.results.length; index++)
                      resultSlot(index),
                    if (model.isDrawing &&
                        model.pendingReplacementIndex == null)
                      Text('下一道正在挑选…', style: TextStyle(color: muted)),
                  ],
                )
              : Center(
                  child: Text(
                    model.isDrawing ? '让好胃口，再转一会儿…' : '不必想好答案，转一下就知道。',
                    style: TextStyle(color: muted),
                  ),
                ),
        ),
      ),
      if (hasActiveCookingShortage)
        Padding(
          key: activeShortageKey,
          padding: EdgeInsets.only(bottom: 12),
          child: Semantics(
            key: Key('active-cooking-shortage'),
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前条件下还剩 ${model.availableCount} 道候选，无法补齐 ${model.requestedCount} 道菜。',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text('可以确认已选的 ${model.results.length} 道菜，或调整条件重新开始。'),
                TextButton(
                  key: Key('adjust-round-conditions'),
                  onPressed: selectCategories,
                  child: Text('调整条件'),
                ),
              ],
            ),
          ),
        ),
      if (model.error != null)
        Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(model.error!, style: TextStyle(color: accent)),
          ),
        ),
      if (model.candidates.isEmpty && !model.hasRound) ...[
        Text('没有符合条件的选项', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('试试其他分类或餐段，也可以恢复本次排除的选项。已停用的选项仍会保持停用。'),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: Key('adjust-empty-conditions'),
              onPressed: model.isBusy ? null : selectCategories,
              child: Text('调整条件'),
            ),
            TextButton(
              key: Key('restore-session-exclusions'),
              onPressed: model.isBusy || model.sessionExclusions.isEmpty
                  ? null
                  : model.restoreSessionExclusions,
              child: Text('恢复本次排除'),
            ),
          ],
        ),
      ],
      if (!pinCookingActions) ...completion(),
    ],
  ];

  List<Widget> cardDecision() => [
    if (!model.isCardFlowSupported) ...[
      SizedBox(height: 24),
      Semantics(
        liveRegion: true,
        child: Text(
          '本餐计划做 ${model.requestedCount} 道菜。多张卡牌的收集流程还在准备中，可以切回转盘继续按这个菜数抽取。',
          key: Key('cards-target-many-notice'),
          style: TextStyle(height: 1.6),
        ),
      ),
      SizedBox(height: 16),
      FilledButton(
        key: Key('cards-use-wheel'),
        onPressed: model.isBusy ? null : () => selectMode(DrawMode.wheel),
        child: Text('用转盘抽 ${model.requestedCount} 道菜'),
      ),
    ] else ...[
      CardDraw(
        controller: model,
        revealAnimation: cardReveal,
        onReveal: revealCard,
      ),
      if (model.error != null)
        Semantics(
          liveRegion: true,
          child: Text(model.error!, style: TextStyle(color: accent)),
        ),
      if (model.candidates.isEmpty && !model.hasRound)
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: Key('adjust-empty-conditions'),
              onPressed: model.isBusy ? null : selectCategories,
              child: Text('调整条件'),
            ),
            TextButton(
              key: Key('restore-session-exclusions'),
              onPressed: model.isBusy || model.sessionExclusions.isEmpty
                  ? null
                  : model.restoreSessionExclusions,
              child: Text('恢复本次排除'),
            ),
          ],
        ),
      if (model.results.isNotEmpty &&
          model.pendingReplacementIndex == null &&
          !model.isDrawing) ...[
        FilledButton(
          key: Key('primary-action'),
          onPressed: model.canConfirm ? confirm : null,
          child: Text(
            model.isSaving
                ? '正在记下这一餐…'
                : model.hasConfirmationAttempt && model.error != null
                ? '重试保存'
                : model.scenario == MealScenario.cook
                ? '就做这 1 道菜'
                : scenarioCopy.confirmAction,
          ),
        ),
        SizedBox(height: 8),
        OutlinedButton(
          key: Key('replace-result-0'),
          onPressed: model.canReplace(0) ? () => replace(0) : null,
          style: OutlinedButton.styleFrom(
            minimumSize: Size(double.infinity, 48),
          ),
          child: Text('换一个'),
        ),
      ],
      SizedBox(key: completionKey, height: 12),
      if (model.hasRound)
        Center(
          child: TextButton(
            key: Key('restart-round'),
            onPressed: model.isBusy ? null : restartRound,
            child: Text('重新开始这一餐'),
          ),
        ),
    ],
  ];

  Widget resultSlot(int index) {
    final cooking = model.scenario == MealScenario.cook;
    final option = model.results[index];
    final pending = model.pendingReplacementIndex == index;
    return Padding(
      key: cooking ? ValueKey('cooking-result-$index') : null,
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Column(
        key: pending ? pendingReplacementKey : null,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pending)
            Container(
              key: ValueKey('pending-replacement-$index'),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                model.isDrawing
                    ? cooking
                          ? '第 ${index + 1} 道正在替换…'
                          : '正在替换这个选择…'
                    : cooking
                    ? '第 ${index + 1} 道等待开始替换'
                    : '等待开始替换',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: cooking
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                if (cooking) ...[
                  Text('${index + 1}', style: TextStyle(color: muted)),
                  SizedBox(width: 12),
                ],
                OptionArt(option: option, size: cooking ? 48 : 64),
                SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!cooking)
                        Text(
                          scenarioCopy.resultHint,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      Text(
                        option.name,
                        key: index == model.results.length - 1
                            ? Key('draw-result')
                            : null,
                        style: TextStyle(
                          fontSize: cooking ? 20 : 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (model.scenario == MealScenario.restaurant &&
                          option.address != null)
                        Text(option.address!, style: TextStyle(color: muted)),
                      if (model.scenario == MealScenario.restaurant &&
                          option.notes != null)
                        Text(option.notes!, style: TextStyle(color: muted)),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                label: '替换${option.name}',
                child: TextButton(
                  key: ValueKey('replace-result-$index'),
                  onPressed: model.canReplace(index)
                      ? () => replace(index)
                      : null,
                  style: TextButton.styleFrom(minimumSize: Size(48, 48)),
                  child: Text('换一个'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> completion() => [
    if (model.pendingReplacementIndex != null)
      Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: FilledButton(
          key: Key('replacement-start'),
          onPressed: model.canDraw ? draw : null,
          child: Text(model.isDrawing ? '正在替换…' : '开始替换'),
        ),
      ),
    if (model.scenario == MealScenario.cook &&
        model.results.isNotEmpty &&
        model.results.length < model.requestedCount)
      Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: OutlinedButton(
          key: Key('draw-next-dish'),
          onPressed: model.pendingReplacementIndex == null && model.canDraw
              ? draw
              : null,
          style: OutlinedButton.styleFrom(
            minimumSize: Size(double.infinity, 48),
          ),
          child: Text(model.isDrawing ? '正在挑选下一道…' : '再转一道'),
        ),
      ),
    FilledButton(
      key: Key('primary-action'),
      onPressed: model.results.isNotEmpty
          ? model.canConfirm
                ? confirm
                : null
          : model.isDrawing || model.isBusy
          ? null
          : draw,
      child: Text(
        model.isSaving
            ? '正在记下这一餐…'
            : model.isDrawing
            ? '正在挑选…'
            : model.results.isNotEmpty
            ? model.hasConfirmationAttempt && model.error != null
                  ? '重试保存'
                  : model.scenario == MealScenario.cook
                  ? '就做这 ${model.results.length} 道菜'
                  : scenarioCopy.confirmAction
            : scenarioCopy.drawAction,
      ),
    ),
    SizedBox(height: 12),
    Center(
      key: completionKey,
      child: Text(
        model.pendingReplacementIndex != null
            ? '替换完成后，才能继续抽取或确认这一餐'
            : model.result != null
            ? '确认之后，才会记入足迹'
            : '一点小期待，一顿好好吃的饭',
        style: TextStyle(color: muted, fontSize: 12),
      ),
    ),
    if (model.hasRound)
      Center(
        child: TextButton(
          key: Key('restart-round'),
          onPressed: model.isBusy ? null : restartRound,
          child: Text('重新开始这一餐'),
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
      SizedBox(height: 32),
      Text(
        '好好吃饭的足迹',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      SizedBox(height: 8),
      Text('记下每一次不再纠结的决定。', style: TextStyle(color: muted)),
      SizedBox(height: 24),
    ];
    if (model.history.isEmpty) {
      widgets.add(
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                foodArt('rice', 120),
                SizedBox(height: 24),
                Text(
                  '第一餐，值得期待',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 12),
                Text('确认一次选择，就会在这里留下足迹。', style: TextStyle(color: muted)),
                SizedBox(height: 32),
                FilledButton(
                  onPressed: () => selectTab(1),
                  child: Text('去决定这一餐'),
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
            padding: EdgeInsets.only(top: 16, bottom: 8),
            child: Text(date, style: TextStyle(color: muted, fontSize: 13)),
          ),
        );
        previousDate = date;
      }
      widgets.add(
        Container(
          key: ValueKey('history-${entry.operationId}'),
          padding: EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: [
              OptionArt(option: entry.option, size: 60),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.options.map((option) => option.name).join('、'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} · ${entry.period.label} · ${MealScenario.fromKey(entry.option.scenario).label}',
                      style: TextStyle(color: muted, fontSize: 12),
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
