import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../application/meal_controller.dart';
import '../domain/meal.dart';
import 'wheel.dart';

class MealApp extends StatelessWidget {
  const MealApp({super.key, required this.controller});
  final MealController controller;

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
    home: _MealHome(controller: controller),
  );
}

class _MealHome extends StatefulWidget {
  const _MealHome({required this.controller});
  final MealController controller;
  @override
  State<_MealHome> createState() => _MealHomeState();
}

class _MealHomeState extends State<_MealHome>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController spin;
  late final CurvedAnimation curve;
  int tab = 1;
  final completionKey = GlobalKey();
  double fromAngle = 0, toAngle = 0;
  bool asking = false;
  MealController get model => widget.controller;

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
    if (model.hasRound) return;
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
      final target = completionKey.currentContext;
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

  Future<void> confirm() async {
    if (await model.confirm() && mounted) {
      resetWheel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这一餐已记入足迹，好好享用吧'),
          duration: Duration(seconds: 2),
        ),
      );
    }
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
                            '${model.period.label} · 吃什么',
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
        bottomNavigationBar: NavigationBar(
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
      ),
    ),
  );

  List<Widget> decide() => [
    const SizedBox(height: 24),
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
    const Text(
      '今天，吃点什么？',
      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.3),
    ),
    const SizedBox(height: 8),
    const Text(
      '把纠结留给转盘，把期待留给下一口。',
      style: TextStyle(color: muted, fontSize: 13),
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: MealPeriod.values
          .map(
            (period) => ChoiceChip(
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
          child: Text(
            '为${model.period.label}准备的灵感',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ),
        Text(
          '${model.candidates.length} 个候选',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ),
    Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              (MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(context).vertical -
                      470)
                  .clamp(220.0, 330.0),
        ),
        child: AnimatedBuilder(
          animation: curve,
          builder: (context, _) => MealWheel(
            options: model.candidates,
            angle: MediaQuery.disableAnimationsOf(context) && model.isDrawing
                ? toAngle
                : fromAngle + (toAngle - fromAngle) * curve.value,
          ),
        ),
      ),
    ),
    Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: model.result == null
            ? Center(
                child: Text(
                  model.isDrawing ? '让好胃口，再转一会儿…' : '不必想好答案，转一下就知道。',
                  style: const TextStyle(color: muted),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  foodArt(model.result!.art, 64),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '这一餐，就吃点喜欢的',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        Text(
                          model.result!.name,
                          key: const Key('draw-result'),
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                          ),
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
                  : '就吃这个'
            : '转一下，开饭',
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
    const SizedBox(height: 32),
    const Text(
      '每一餐的灵感',
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
    ),
    const SizedBox(height: 8),
    const Text('8 个小小提案，总有一口合心意。', style: TextStyle(color: muted)),
    const SizedBox(height: 24),
    LayoutBuilder(
      builder: (context, constraints) {
        final single =
            MediaQuery.textScalerOf(context).scale(14) > 21 ||
            constraints.maxWidth < 280;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: model.options
              .map(
                (food) => Container(
                  width: single
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xfffffdf8),
                    border: Border.all(color: const Color(0xffe9ddcb)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: foodArt(food.art, 76)),
                      const SizedBox(height: 8),
                      Text(
                        food.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        MealPeriod.values
                            .where(food.periods.contains)
                            .map((period) => period.label)
                            .join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
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
              foodArt(entry.option.art, 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.option.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} · ${entry.period.label} · 吃什么',
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
