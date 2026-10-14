import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../application/meal_controller.dart';
import '../domain/meal.dart';
import '../domain/meal_preferences.dart';
import 'card_draw.dart';
import 'meal_history.dart';
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
        navigatorObservers: [optionEditorRouteObserver],
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
  late final AnimationController wheelSettle;
  late final CurvedAnimation curve;
  bool stageOpen = false;
  bool backgrounded = false;
  bool get paused => asking || backgrounded;
  int tab = 1;
  MealScenario libraryScenario = MealScenario.eat;
  MealScenario? historyScenario;
  double fromAngle = 0, toAngle = 0;
  WheelLayout? displayedWheel;
  bool asking = false;
  final wheelResultKey = GlobalKey();
  String? previousWheelResultId;
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
      !model.hasPendingReplacement &&
      !model.isDrawing &&
      !model.isBusy &&
      !model.hasConfirmationAttempt &&
      model.availableCount < model.requestedCount - model.results.length;

  @override
  void initState() {
    super.initState();
    spin = AnimationController(vsync: this, duration: Duration(seconds: 4));
    cardReveal = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    wheelSettle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    curve = CurvedAnimation(parent: spin, curve: Cubic(.12, .64, .13, 1));
    spin.addStatusListener(drawAnimationChanged);
    cardReveal.addStatusListener(drawAnimationChanged);
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
    wheelSettle.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => backgrounded = state != AppLifecycleState.resumed);
    syncAnimationPause();
    if (state == AppLifecycleState.resumed) {
      model.refreshCardAvailability();
      showCompletion();
    }
  }

  void syncAnimationPause() {
    for (final animation in [spin, cardReveal, wheelSettle]) {
      if (paused && animation.isAnimating) animation.stop(canceled: false);
    }
    if (!paused && model.isDrawing) {
      (cardsMode ? cardReveal : spin).forward();
    } else if (!paused && !cardsMode && wheelSettle.value < 1) {
      wheelSettle.forward();
    }
  }

  void drawAnimationChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !model.isDrawing || paused) {
      return;
    }
    model.finishDraw();
    if (!cardsMode) {
      if (MediaQuery.disableAnimationsOf(context)) {
        wheelSettle.value = 1;
      } else {
        wheelSettle.forward(from: 0);
      }
    }
    if (!backgrounded) HapticFeedback.lightImpact();
  }

  void modelChanged() {
    final resultId = !cardsMode && !model.isDrawing ? model.result?.id : null;
    if (resultId != previousWheelResultId) {
      previousWheelResultId = resultId;
      if (resultId != null) focusWheelResult(resultId);
    }
    if (!model.hasRound) {
      resetWheel();
      cardReveal.stop(canceled: true);
      cardReveal.value = 0;
    }
    if (model.restartNotice != null) showRestartNotice();
    if (model.restartNotice != null && stageOpen) {
      setState(() => stageOpen = false);
    }
  }

  void focusWheelResult(String optionId) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !stageOpen || paused || model.result?.id != optionId) {
        return;
      }
      final target = wheelResultKey.currentContext;
      if (target == null || !MediaQuery.accessibleNavigationOf(context)) return;
      // Only assistive navigation follows a newly revealed or reopened result.
      // Ordinary drawing keeps the user's accepted stage scroll position.
      await Scrollable.ensureVisible(target, alignment: .25);
      if (!mounted ||
          !target.mounted ||
          model.result?.id != optionId ||
          paused) {
        return;
      }
      target.findRenderObject()?.sendSemanticsEvent(const FocusSemanticEvent());
    });
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
    if (cardsMode) {
      if (!model.canDraw) return;
      setState(() => stageOpen = true);
      return;
    }
    if (!model.startDraw()) return;
    setState(() => stageOpen = true);
    final layout = WheelLayout.fromOptions(model.candidates);
    displayedWheel = layout;
    final sector = layout.sectorIndexFor(
      model.candidates[model.selectedIndex!].id,
    );
    fromAngle = toAngle % (math.pi * 2);
    final target = -(sector + .5) * math.pi * 2 / layout.sectors.length;
    toAngle =
        fromAngle + math.pi * 2 * 7 + (target - fromAngle) % (math.pi * 2);
    if (model.candidates.length == 1) {
      spin.value = 0;
      model.finishDraw();
      return;
    }
    wheelSettle.value = 0;
    spin.duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 180)
        : const Duration(seconds: 4);
    spin.forward(from: 0);
    syncAnimationPause();
  }

  Future<void> revealCard() async {
    if (paused || !model.revealSelectedCard()) return;
    cardReveal.duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 120)
        : const Duration(milliseconds: 800);
    cardReveal.forward(from: 0);
  }

  Future<void> selectMode(DrawMode mode) async {
    if (stageOpen || mode == model.preferences.mode || model.isBusy) return;
    await model.updatePreferences(model.preferences.copyWith(mode: mode));
  }

  void showCompletion() {
    // The stage remains anchored at its current scroll position during draws.
  }

  Future<bool> ask(
    String title,
    String message,
    String action, {
    String cancel = '继续抽取',
  }) async {
    if (asking) return false;
    setState(() => asking = true);
    syncAnimationPause();
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(cancel),
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
      if (mounted) setState(() => asking = false);
      syncAnimationPause();
    }
  }

  void resetWheel() {
    spin.stop(canceled: true);
    spin.value = 0;
    fromAngle = toAngle = 0;
    displayedWheel = null;
    wheelSettle.value = 1;
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
    if (asking || model.isBusy) return;
    final completeTutorial = cardsMode;
    bool saved;
    if (model.canConfirmRetained) {
      final count = model.results.length;
      if (!await ask(
        '确认已有的菜？',
        '正在替换一道菜，要继续抽取，还是直接确认已有的 $count 道菜？',
        '确认这 $count 道菜',
      )) {
        return;
      }
      if (!mounted) return;
      // Cancel the visual continuation before fixing the retained meal for retry.
      spin.stop();
      cardReveal.stop();
      saved = await model.confirmRetained();
    } else {
      saved = await model.confirm();
    }
    if (saved && mounted) {
      setState(() => stageOpen = false);
      if (completeTutorial) {
        await model.dismissCardTutorial(
          includeCollection: !model.isSingleTarget,
        );
      }
      if (!mounted) return;
      resetWheel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(scenarioCopy.confirmationNotice),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> replace(int index) async {
    if (asking || !model.canReplace(index)) return;
    final outgoingName = model.results[index].name;
    setState(() => asking = true);
    syncAnimationPause();
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
      if (mounted) setState(() => asking = false);
      syncAnimationPause();
    }
    if (!mounted || !model.hasPendingReplacement) return;
    resetWheel();
    if (!cardsMode) await draw();
    showCompletion();
  }

  Future<void> restartRound() async {
    if (model.isBusy || !stageOpen) return;
    if (!await ask('重新开始这一餐？', '当前未确认的选择会清空，本次排除仍会保留。', '清空并重新开始')) {
      return;
    }
    if (mounted && !model.isBusy && model.abandon()) {
      setState(() => stageOpen = false);
    }
  }

  Future<void> selectCategories() async {
    if (model.isBusy || asking) return;
    setState(() => asking = true);
    syncAnimationPause();
    CategoryFilterSelection? selection;
    try {
      selection = await showModalBottomSheet<CategoryFilterSelection>(
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
            excludeYesterday: model.preferences.excludeYesterday,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => asking = false);
        syncAnimationPause();
      }
    }
    if (selection == null || !mounted || model.isBusy) return;
    final unchanged =
        selection.excludeYesterday == model.preferences.excludeYesterday &&
        selection.period == model.period &&
        selection.ids.length == model.selectedCategoryIds.length &&
        selection.ids.containsAll(model.selectedCategoryIds);
    if (unchanged) return;
    if (model.hasRound &&
        !await ask('更换筛选条件？', '当前还未确认的选择会清空，按新条件重新开始。', '应用并重新开始')) {
      return;
    }
    if (!mounted || model.isBusy) return;
    if (!await model.updatePreferences(
      model.preferences.copyWith(excludeYesterday: selection.excludeYesterday),
      restartRound: true,
    )) {
      return;
    }
    if (!mounted) return;
    model.changeCategoryFilters(selection.ids, period: selection.period);
    setState(() => stageOpen = false);
  }

  Future<void> selectYesterday(bool selected) async {
    if (model.isBusy || asking) return;
    if (model.hasRound &&
        !await ask('更换筛选条件？', '当前还未确认的选择会清空，按新条件重新开始。', '应用并重新开始')) {
      return;
    }
    if (!mounted || model.isBusy) return;
    if (await model.updatePreferences(
      model.preferences.copyWith(excludeYesterday: selected),
      restartRound: true,
    )) {
      if (mounted) setState(() => stageOpen = false);
    }
  }

  Future<void> back() async {
    if (tab != 1) {
      selectTab(1);
      return;
    }
    if (model.isBusy || !stageOpen) return;
    if (await ask(
      '离开本次抽取？',
      model.hasConfirmationAttempt && model.error != null
          ? '上次保存结果尚未确认。建议返回重试；离开会清空当前选择，已保存的足迹仍会保留。'
          : '离开后，本次抽取进度和未确认的结果将丢失。',
      '离开',
    )) {
      if (mounted && model.abandon()) setState(() => stageOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => PopScope(
      canPop: tab == 1 && !stageOpen && !model.hasRound && !model.isBusy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: stageOpen
          ? drawStage()
          : Scaffold(
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
    const SizedBox(height: 20),
    Text(
      scenarioCopy.heading,
      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.3),
    ),
    SizedBox(height: 12),
    ScenarioSelector(
      page: 'decide',
      selected: model.scenario,
      onSelected: model.isBusy ? null : selectScenario,
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
    Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          key: Key('category-filter-button'),
          onPressed: model.isBusy ? null : selectCategories,
          icon: Icon(Icons.filter_list),
          label: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                model.selectedCategoryIds.isEmpty
                    ? '全部分类'
                    : '已选 ${model.selectedCategoryIds.length} 个分类',
              ),
              Text(
                '${model.availableCount} 个候选',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        FilterChip(
          key: const Key('yesterday-filter-button'),
          label: const Text('昨天选过的不选'),
          selected: model.preferences.excludeYesterday,
          onSelected: model.isBusy ? null : selectYesterday,
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
    ],
    ...entryDisplay(),
  ];

  List<Widget> entryDisplay() => [
    const SizedBox(height: 12),
    SizedBox(
      height: 250,
      child: _EntryModePages(
        mode: model.preferences.mode,
        busy: model.isBusy,
        onChanged: selectMode,
        children: [
          Center(
            child: SizedBox(
              width: 260,
              child: MealWheel(
                options: model.candidates,
                centerLabel: scenarioCopy.wheelLabel,
                angle: 0,
              ),
            ),
          ),
          const CardDeckPreview(),
        ],
      ),
    ),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final mode in DrawMode.values)
          TextButton(
            key: ValueKey('draw-mode-${mode.name}'),
            onPressed: model.isBusy
                ? null
                : () async {
                    await selectMode(mode);
                  },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  model.preferences.mode == mode
                      ? Icons.circle
                      : Icons.circle_outlined,
                  size: 8,
                ),
                const SizedBox(width: 8),
                Text(mode == DrawMode.wheel ? '转盘' : '抽卡'),
              ],
            ),
          ),
      ],
    ),
    const SizedBox(height: 12),
    FilledButton(
      key: const Key('primary-action'),
      onPressed: model.isBusy || model.availableCount == 0 ? null : draw,
      child: Text(cardsMode ? '开始抽取' : scenarioCopy.drawAction),
    ),
    if (model.error != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(model.error!, style: TextStyle(color: accent)),
      ),
    if (model.availableCount == 0) ...[
      const SizedBox(height: 12),
      const Text('没有符合条件的选项，请调整分类、餐段或昨天筛选。'),
      Wrap(
        children: [
          TextButton(
            key: const Key('adjust-empty-conditions'),
            onPressed: selectCategories,
            child: const Text('调整条件'),
          ),
          TextButton(
            key: const Key('restore-session-exclusions'),
            onPressed: model.sessionExclusions.isEmpty
                ? null
                : model.restoreSessionExclusions,
            child: const Text('恢复本次排除'),
          ),
        ],
      ),
    ],
  ];

  Widget drawStage() => Scaffold(
    key: const Key('draw-stage'),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  key: const Key('draw-back'),
                  tooltip: '返回',
                  onPressed: model.isBusy ? null : back,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      model.isSingleTarget
                          ? model.scenario.label
                          : '已选 ${model.results.length} / ${model.requestedCount} 道',
                      key: const Key('cooking-progress'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('stage-filter-button'),
                  tooltip: '调整条件',
                  onPressed: model.isBusy || model.isDrawing || asking
                      ? null
                      : selectCategories,
                  icon: const Icon(Icons.filter_list),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('draw-stage-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: cardsMode ? model.cancelCardSelection : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (cardsMode)
                          CardDraw(
                            controller: model,
                            revealAnimation: cardReveal,
                            onReveal: revealCard,
                            paused: paused,
                          )
                        else
                          ...wheelStage(),
                        if (model.error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                model.error!,
                                style: TextStyle(color: accent),
                              ),
                            ),
                          ),
                        if (hasActiveCookingShortage)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              '当前条件下还剩 ${model.availableCount} 道候选，无法补齐 ${model.requestedCount} 道菜。可以确认已选的 ${model.results.length} 道菜，或重新开始调整条件。',
                              key: const Key('active-cooking-shortage'),
                            ),
                          ),
                        ...stageActions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> wheelStage() => [
    Semantics(
      key: const Key('wheel-status'),
      container: true,
      liveRegion: true,
      label:
          '转盘，共 ${(displayedWheel?.sectors.expand((sector) => sector.optionIds).length ?? model.candidates.length)} 个候选',
      value: model.isDrawing ? '正在挑选' : '已揭晓',
      child: AnimatedBuilder(
        animation: Listenable.merge([curve, wheelSettle]),
        builder: (context, _) {
          final growing = model.isDrawing
              ? (spin.value / .05).clamp(0.0, 1.0)
              : 0.0;
          return Center(
            child: SizedBox(
              width: MediaQuery.disableAnimationsOf(context)
                  ? 180
                  : model.isDrawing
                  ? 260 + 80 * growing
                  : 340 -
                        160 * Curves.easeOutCubic.transform(wheelSettle.value),
              child: MealWheel(
                options: model.candidates,
                layout: displayedWheel,
                centerLabel: scenarioCopy.wheelLabel,
                angle: MediaQuery.disableAnimationsOf(context)
                    ? toAngle
                    : fromAngle + (toAngle - fromAngle) * curve.value,
              ),
            ),
          );
        },
      ),
    ),
    const SizedBox(height: 16),
    if (model.isDrawing)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: ExcludeSemantics(
          child: Text(
            '正在挑选…',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        ),
      )
    else ...[
      if (model.result case final option?) ...[
        Center(child: OptionArt(option: option, size: 128)),
        const SizedBox(height: 16),
        Semantics(
          key: wheelResultKey,
          container: true,
          label: '抽取结果：${option.name}',
          child: ExcludeSemantics(
            child: Text(
              option.name,
              key: const Key('draw-result'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ),
        if (option.address != null)
          Text(option.address!, textAlign: TextAlign.center),
        if (option.notes != null)
          Text(option.notes!, textAlign: TextAlign.center),
        const SizedBox(height: 20),
      ],
      if (!model.isSingleTarget && model.results.isNotEmpty)
        SingleChildScrollView(
          key: const Key('wheel-results-row'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < model.results.length; index++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        320,
                        MediaQuery.sizeOf(context).width - 48,
                      ),
                    ),
                    child: OutlinedButton(
                      key: ValueKey('cooking-result-$index'),
                      onPressed:
                          model.hasPendingReplacement ||
                              model.hasConfirmationAttempt
                          ? null
                          : () => model.focusResult(index),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: model.focusedResultIndex == index
                            ? soft
                            : null,
                      ),
                      child: Semantics(
                        selected: model.focusedResultIndex == index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              OptionArt(option: model.results[index], size: 48),
                              const SizedBox(height: 6),
                              Text(
                                model.results[index].name,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ],
  ];

  List<Widget> stageActions() {
    final focus = model.focusedResultIndex;
    final retained = model.canConfirmRetained;
    return [
      const SizedBox(height: 16),
      if (!cardsMode &&
          !model.hasPendingReplacement &&
          !model.isSingleTarget &&
          model.results.length < model.requestedCount)
        OutlinedButton(
          key: const Key('draw-next-dish'),
          onPressed: model.canDraw && !paused ? draw : null,
          child: Text(model.isDrawing ? '正在挑选…' : '再转一道'),
        ),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 8,
        children: [
          TextButton(
            key: const Key('restart-round'),
            onPressed: model.isBusy || asking ? null : restartRound,
            child: const Text('重新开始'),
          ),
          TextButton(
            key: ValueKey('replace-result-${focus ?? 0}'),
            onPressed: focus != null && model.canReplace(focus) && !paused
                ? () => replace(focus)
                : null,
            child: Text(
              '换一个',
              semanticsLabel: focus == null
                  ? '换一个'
                  : '替换「${model.results[focus].name}」',
            ),
          ),
        ],
      ),
      if (model.results.isNotEmpty) ...[
        const SizedBox(height: 4),
        FilledButton(
          key: const Key('primary-action'),
          onPressed: (model.canConfirm || retained) && !asking ? confirm : null,
          child: Text(
            model.isSaving
                ? '正在记下这一餐…'
                : model.hasConfirmationAttempt && model.error != null
                ? '重试保存'
                : model.scenario == MealScenario.cook
                ? '就做这 ${model.results.length} 道菜'
                : scenarioCopy.confirmAction,
          ),
        ),
      ],
    ];
  }

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

  List<Widget> history() => [
    MealHistory(
      controller: model,
      scenario: historyScenario,
      onScenarioChanged: (scenario) =>
          setState(() => historyScenario = scenario),
      onDecide: () => selectTab(1),
    ),
  ];
}

// Own paging state only while the entry is mounted. A drawing-stage scroll
// position must never be restored as the entry's selected mode.
class _EntryModePages extends StatefulWidget {
  const _EntryModePages({
    required this.mode,
    required this.busy,
    required this.onChanged,
    required this.children,
  });

  final DrawMode mode;
  final bool busy;
  final ValueChanged<DrawMode> onChanged;
  final List<Widget> children;

  @override
  State<_EntryModePages> createState() => _EntryModePagesState();
}

class _EntryModePagesState extends State<_EntryModePages> {
  late final PageController pages;

  @override
  void initState() {
    super.initState();
    pages = PageController(
      initialPage: widget.mode == DrawMode.cards ? 1 : 0,
      keepPage: false,
    );
  }

  @override
  void didUpdateWidget(_EntryModePages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.busy && (oldWidget.mode != widget.mode || oldWidget.busy)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.busy || !pages.hasClients) return;
        final page = widget.mode == DrawMode.cards ? 1 : 0;
        if (pages.page?.round() != page) pages.jumpToPage(page);
      });
    }
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView(
    key: const Key('entry-mode-pages'),
    controller: pages,
    physics: widget.busy
        ? const NeverScrollableScrollPhysics()
        : const BouncingScrollPhysics(),
    onPageChanged: (page) =>
        widget.onChanged(page == 0 ? DrawMode.wheel : DrawMode.cards),
    children: widget.children,
  );
}
