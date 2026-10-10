import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/meal_controller.dart';
import '../domain/meal.dart';
import 'option_art.dart';

const celestialCardBack =
    'docs/design/assets/card-back-celestial-black-purple-gold.png';

/// Entry artwork uses the canonical back without sampling any option.
class CardDeckPreview extends StatelessWidget {
  const CardDeckPreview({super.key, this.height = 240});
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '卡牌模式',
    child: SizedBox(
      height: height,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (var index = 0; index < 4; index++)
              Transform.translate(
                offset: Offset((index - 1.5) * 6, (1.5 - index) * 3),
                child: Transform.rotate(
                  angle: (index - 1.5) * .035,
                  child: SizedBox(
                    width: height * .54,
                    height: height * .84,
                    child: const _CardBack(),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The fan exposes positions only; option identities stay hidden until reveal.
class CardDraw extends StatefulWidget {
  const CardDraw({
    super.key,
    required this.controller,
    required this.revealAnimation,
    required this.onReveal,
    this.paused = false,
  });

  final MealController controller;
  final Animation<double> revealAnimation;
  final VoidCallback onReveal;
  final bool paused;

  @override
  State<CardDraw> createState() => _CardDrawState();
}

class _CardDrawState extends State<CardDraw> with TickerProviderStateMixin {
  final browsing = ScrollController();
  final collectedBrowsing = ScrollController();
  late final AnimationController shuffle;
  late final AnimationController selection;
  late final AnimationController collection;
  final stageKey = GlobalKey();
  final collectionSourceKey = GlobalKey();
  final collectionTargetKey = GlobalKey();
  FoodOption? collectingOption;
  Offset collectionStart = Offset.zero;
  Offset collectionEnd = Offset.zero;
  Size collectionSize = Size.zero;
  double collectionEndScale = .5;
  MealController get model => widget.controller;
  static const cardWidth = 82.0;
  static const cardStep = 44.0;
  static const cardHeight = 132.0;
  // Preserve the original travel distance within the existing shuffle timing.
  static const shuffleLaps = 2;
  static double fanInset(int count, double viewport) => math.max(
    20.0,
    (viewport - cardWidth - math.max(0, count - 1) * cardStep) / 2,
  );
  int? shuffleRevision;
  int? previousSelection;
  bool initialShuffle = true;
  bool reducedMotion = false;

  bool get shuffling => shuffle.value < 1;
  bool get interactionsEnabled =>
      !widget.paused &&
      !shuffling &&
      collectingOption == null &&
      !model.isBusy &&
      !model.isDrawing;

  @override
  void initState() {
    super.initState();
    shuffle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    selection = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    );
    collection = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    )..addStatusListener(collectionChanged);
    model.addListener(modelChanged);
    browsing.addListener(scrollChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reducedMotion = MediaQuery.disableAnimationsOf(context);
    syncDeck();
    syncMotion();
  }

  @override
  void didUpdateWidget(CardDraw oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != model) {
      cancelCollection();
      oldWidget.controller.removeListener(modelChanged);
      model.addListener(modelChanged);
      shuffleRevision = null;
      previousSelection = null;
    }
    syncDeck();
    syncMotion();
    if (widget.paused && !oldWidget.paused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.paused) return;
        for (final scroll in [browsing, collectedBrowsing]) {
          if (scroll.hasClients) scroll.jumpTo(scroll.offset);
        }
      });
    }
  }

  void modelChanged() {
    if (collectingOption case final option?) {
      if (!model.hasRound ||
          model.hasConfirmationAttempt ||
          !model.results.any((result) => result.id == option.id)) {
        cancelCollection();
      }
    }
    syncDeck();
    if (previousSelection != model.selectedCardIndex) {
      previousSelection = model.selectedCardIndex;
      selection.value = model.selectedCardIndex == null ? 1 : 0;
      syncMotion();
    }
    if (mounted) setState(() {});
  }

  void scrollChanged() {
    if (mounted) setState(() {});
  }

  void syncDeck() {
    model.cardDeck;
    final revision = model.cardDeckShuffleRevision;
    if (revision == shuffleRevision) return;
    initialShuffle = shuffleRevision == null || !model.hasRound;
    shuffleRevision = revision;
    shuffle.duration = Duration(milliseconds: initialShuffle ? 1800 : 700);
    shuffle.value = reducedMotion || model.cardDeck.isEmpty ? 1 : 0;
    // Center the full deck after its new extent is laid out. Ordinary draws do
    // not change the shuffle revision, so browsing stays where the user left it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || shuffleRevision != revision || !browsing.hasClients) {
        return;
      }
      browsing.jumpTo(browsing.position.maxScrollExtent / 2);
    });
    syncMotion();
  }

  void syncMotion() {
    if (reducedMotion) {
      shuffle.value = 1;
      selection.value = 1;
      collection.value = 1;
    } else if (widget.paused) {
      shuffle.stop(canceled: false);
      selection.stop(canceled: false);
      collection.stop(canceled: false);
    } else {
      if (shuffle.value < 1 && !shuffle.isAnimating) shuffle.forward();
      if (selection.value < 1 && !selection.isAnimating) selection.forward();
      if (collectingOption != null &&
          collection.value < 1 &&
          !collection.isAnimating) {
        collection.forward();
      }
    }
  }

  @override
  void dispose() {
    model.removeListener(modelChanged);
    browsing.dispose();
    collectedBrowsing.dispose();
    shuffle.dispose();
    selection.dispose();
    collection.dispose();
    super.dispose();
  }

  void tapCard(int index) {
    if (!interactionsEnabled || !model.canDraw) return;
    if (model.selectedCardIndex == index) {
      widget.onReveal();
    } else {
      if (model.selectCard(index)) HapticFeedback.selectionClick();
    }
  }

  void browse(int direction) {
    if (!browsing.hasClients || !interactionsEnabled) return;
    browsing.animateTo(
      (browsing.offset + direction * cardStep * 4).clamp(
        0.0,
        browsing.position.maxScrollExtent,
      ),
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void collectCentralCard() {
    if (!interactionsEnabled || !model.canCollectCard) return;
    if (reducedMotion) {
      model.collectCardResult();
      return;
    }
    final source = collectionSourceKey.currentContext?.findRenderObject();
    final stage = stageKey.currentContext?.findRenderObject();
    if (source is! RenderBox || stage is! RenderBox) return;
    collectingOption = model.cardCentralResult;
    collectionStart = source.localToGlobal(Offset.zero, ancestor: stage);
    collectionEnd = collectionStart;
    collectionSize = source.size;
    collectionEndScale = .5;
    collection.value = 0;
    // Collection is a presentation step. The revealed result remains valid for
    // confirmation immediately, and completing this ticker never mutates state.
    if (!model.collectCardResult()) {
      cancelCollection();
      return;
    }
    syncMotion();
    final incomingId = collectingOption!.id;
    void measureDestination() {
      if (!mounted || collectingOption?.id != incomingId) return;
      final target = collectionTargetKey.currentContext?.findRenderObject();
      final currentStage = stageKey.currentContext?.findRenderObject();
      if (target is RenderBox && currentStage is RenderBox) {
        setState(() {
          collectionEnd = target.localToGlobal(
            Offset.zero,
            ancestor: currentStage,
          );
          collectionEndScale = target.size.width / collectionSize.width;
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || collectingOption?.id != incomingId) return;
      final indexes = model.collectedCardResultIndexes;
      final slot = indexes.indexWhere(
        (index) => model.results[index].id == collectingOption!.id,
      );
      if (collectedBrowsing.hasClients && slot >= 0) {
        final destination = (slot * 122.0).clamp(
          0.0,
          collectedBrowsing.position.maxScrollExtent,
        );
        if (collectedBrowsing.offset != destination) {
          collectedBrowsing.jumpTo(destination);
          // Read the destination after the row lays out at its new offset.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => measureDestination(),
          );
          return;
        }
      }
      measureDestination();
    });
  }

  void collectionChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && collectingOption != null) {
      setState(() => collectingOption = null);
    }
  }

  void cancelCollection() {
    collection.stop(canceled: false);
    collectingOption = null;
  }

  Widget collectingCard() {
    final progress = Curves.easeInOutCubic.transform(collection.value);
    final position = Offset.lerp(collectionStart, collectionEnd, progress)!;
    return Positioned(
      key: const Key('collecting-card-position'),
      left: position.dx,
      top: position.dy,
      width: collectionSize.width,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Transform.scale(
            key: const Key('collecting-card-scale'),
            alignment: Alignment.topLeft,
            scale: 1 + (collectionEndScale - 1) * progress,
            child: Opacity(
              opacity: (1 - (progress - .8) / .2).clamp(0.0, 1.0),
              child: _CardFace(option: collectingOption!),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      shuffle,
      selection,
      collection,
      widget.revealAnimation,
    ]),
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final deck = model.cardDeck;
      return Stack(
        key: stageKey,
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              centralCard(),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = constraints.maxWidth;
                  return SizedBox(
                    height: 188,
                    child: GestureDetector(
                      key: const Key('card-fan-blank'),
                      behavior: HitTestBehavior.opaque,
                      onTap: interactionsEnabled
                          ? model.cancelCardSelection
                          : null,
                      child: SingleChildScrollView(
                        key: const Key('card-fan-scroll'),
                        controller: browsing,
                        scrollDirection: Axis.horizontal,
                        physics: interactionsEnabled
                            ? const ClampingScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: math.max(
                            viewport,
                            cardWidth +
                                40 +
                                math.max(0, deck.length - 1) * cardStep,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (final index in fanOrder(deck.length))
                                if (index != model.selectedCardIndex)
                                  fanCard(index, deck.length, viewport),
                              if (model.selectedCardIndex
                                  case final int selected)
                                if (!model.isDrawing)
                                  fanCard(selected, deck.length, viewport),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    key: const Key('browse-cards-back'),
                    tooltip: '向前浏览卡牌',
                    onPressed: interactionsEnabled ? () => browse(-1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      shuffling ? '正在洗牌…' : '${deck.length} 张牌',
                      key: const Key('card-deck-status'),
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                  IconButton(
                    key: const Key('browse-cards-forward'),
                    tooltip: '向后浏览卡牌',
                    onPressed: interactionsEnabled ? () => browse(1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              if (!model.isSingleTarget) collectedRow(),
              if (!model.preferences.cardTutorialDismissed ||
                  (!model.isSingleTarget &&
                      !model.preferences.cardCollectionTutorialDismissed))
                tutorialGuidance(),
              const SizedBox(height: 8),
            ],
          ),
          if (collectingOption != null) collectingCard(),
        ],
      );
    },
  );

  Widget centralCard() {
    if (collectingOption != null) {
      return SizedBox(height: collectionSize.height);
    }
    final front = model.isDrawing
        ? model.selectedCard
        : model.cardCentralResult;
    if (front == null) {
      return GestureDetector(
        key: const Key('card-center-blank'),
        behavior: HitTestBehavior.opaque,
        onTap: interactionsEnabled ? model.cancelCardSelection : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 264),
          alignment: Alignment.center,
          child: model.cardDeck.isEmpty
              ? Text(
                  model.results.isEmpty ? '没有符合条件的选项' : '本餐已选好',
                  textAlign: TextAlign.center,
                )
              : const Opacity(
                  opacity: .22,
                  child: SizedBox(width: 162, height: 248, child: _CardBack()),
                ),
        ),
      );
    }
    final progress = model.isDrawing ? widget.revealAnimation.value : 1.0;
    final travel = Curves.easeOutCubic.transform(
      (progress / .65).clamp(0.0, 1.0),
    );
    final flip = ((progress - .3) / .7).clamp(0.0, 1.0);
    final showFace = reducedMotion || flip >= .5;
    final offset = browsing.hasClients ? browsing.offset : 0.0;
    final viewport = MediaQuery.sizeOf(context).width - 48;
    final startX =
        (fanInset(model.cardDeck.length, viewport) +
                (model.selectedCardIndex ?? 0) * cardStep -
                offset +
                cardWidth / 2 -
                viewport / 2)
            .clamp(-140.0, 140.0);
    final canCollect = interactionsEnabled && model.canCollectCard;
    return Center(
      child: Transform.translate(
        offset: reducedMotion
            ? Offset.zero
            : Offset(startX * (1 - travel), 250 * (1 - travel)),
        child: Transform.scale(
          scale: reducedMotion ? 1 : .38 + .62 * travel,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .001)
              ..rotateY(
                reducedMotion ? 0 : (showFace ? flip - 1 : flip) * math.pi,
              ),
            child: ExcludeSemantics(
              excluding: model.isDrawing,
              child: Semantics(
                liveRegion: !model.isDrawing,
                button: canCollect,
                hint: canCollect ? '点击大卡，收入本餐' : null,
                child: KeyedSubtree(
                  key: collectionSourceKey,
                  child: GestureDetector(
                    key: const Key('collect-central-card'),
                    onTap: canCollect ? collectCentralCard : null,
                    child: showFace
                        ? _CardFace(option: front)
                        : const SizedBox(
                            width: 222,
                            height: 300,
                            child: _CardBack(),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget tutorialGuidance() {
    final collect = !model.isSingleTarget && model.cardCentralResult != null;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              collect
                  ? '点击大卡，收入本餐'
                  : model.cardCentralResult != null
                  ? '喜欢就确认，也可以换一个'
                  : '点一下选中，再点一下翻开',
              key: const Key('card-guidance'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ),
        TextButton(
          key: const Key('skip-card-tutorial'),
          onPressed: widget.paused || model.isBusy
              ? null
              : () => model.dismissCardTutorial(includeCollection: true),
          child: const Text('跳过引导'),
        ),
      ],
    );
  }

  Widget collectedRow() {
    final colors = Theme.of(context).colorScheme;
    final indexes = model.collectedCardResultIndexes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '本餐已收 ${indexes.length} 道',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
        SingleChildScrollView(
          key: const Key('collected-card-scroll'),
          controller: collectedBrowsing,
          scrollDirection: Axis.horizontal,
          physics: widget.paused || collectingOption != null
              ? const NeverScrollableScrollPhysics()
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final index in indexes)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Semantics(
                    selected: model.focusedResultIndex == index,
                    button: true,
                    child: InkWell(
                      key: ValueKey('collected-card-$index'),
                      onTap: interactionsEnabled && !model.hasPendingReplacement
                          ? () => model.focusResult(index)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      child: Opacity(
                        opacity: collectingOption?.id == model.results[index].id
                            ? ((Curves.easeInOutCubic.transform(
                                            collection.value,
                                          ) -
                                          .8) /
                                      .2)
                                  .clamp(0.0, 1.0)
                            : 1,
                        child: Container(
                          key: collectingOption?.id == model.results[index].id
                              ? collectionTargetKey
                              : null,
                          width: 112,
                          constraints: const BoxConstraints(minHeight: 110),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: model.focusedResultIndex == index
                                  ? colors.primary
                                  : colors.outlineVariant,
                            ),
                          ),
                          child: Column(
                            children: [
                              OptionArt(option: model.results[index], size: 50),
                              const SizedBox(height: 6),
                              Text(
                                model.results[index].name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 14,
                                  height: 1.3,
                                ),
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
        const SizedBox(height: 12),
      ],
    );
  }

  Widget fanCard(int index, int count, double viewport) {
    final selected = model.selectedCardIndex == index;
    final enabled = interactionsEnabled && model.canDraw;
    final offset = browsing.hasClients ? browsing.offset : 0.0;
    final viewCenter = offset + viewport / 2;
    final progress = shuffle.value;
    final spread = !initialShuffle || progress >= .32
        ? 1.0
        : Curves.easeOutCubic.transform((progress / .32).clamp(0.0, 1.0));
    final flowProgress = initialShuffle
        ? ((progress - .32) / .68).clamp(0.0, 1.0)
        : progress;
    final slot = shuffleSlot(index, count, flowProgress);
    final flowing = shuffling && flowProgress > 0;
    final horizontalIndex = flowing ? slot : index.toDouble();
    final left = fanInset(count, viewport) + horizontalIndex * cardStep;
    final relative = ((left + cardWidth / 2 - viewCenter) / cardStep).clamp(
      -4.0,
      4.0,
    );
    final angle = relative * .105;
    final lift = selected ? 18 * selection.value : 0.0;
    final top = 25 + relative.abs() * relative.abs() - lift;
    final wrap = math.min(slot, count - slot);
    // Hide each return from the left edge to the right. Blend this edge fade
    // in and out while circulation accelerates/settles, leaving all cards fully
    // visible in the resting fan without an endpoint flash.
    final edgeFade = (wrap / 1.1).clamp(0.0, 1.0);
    final fadeWeight = math.min(
      (flowProgress / .12).clamp(0.0, 1.0),
      ((1 - flowProgress) / .12).clamp(0.0, 1.0),
    );
    final opacity = flowing && count > 1
        ? 1 - fadeWeight * (1 - edgeFade)
        : 1.0;
    return Positioned(
      key: ValueKey('fan-position-$index'),
      left: (viewCenter - cardWidth / 2) * (1 - spread) + left * spread,
      top: 28 * (1 - spread) + top * spread,
      child: Transform.rotate(
        angle: selected ? angle * (1 - selection.value) : angle * spread,
        child: Opacity(
          opacity: opacity,
          child: Semantics(
            label: '第 ${index + 1} 张牌',
            hint: selected ? '再点一次翻开' : '点一下选中',
            selected: selected,
            button: true,
            enabled: enabled,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('candidate-card-$index'),
                onTap: enabled ? () => tapCard(index) : null,
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const _CardBack(),
                      if (selected)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                      if (selected)
                        Positioned(
                          bottom: 8,
                          left: 29,
                          child: ExcludeSemantics(
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              child: Icon(
                                Icons.check,
                                size: 16,
                                color: Theme.of(context).colorScheme.onPrimary,
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
        ),
      ),
    );
  }

  double shuffleSlot(int index, int count, double progress) {
    // One continuous fan avoids internal wrap/fade seams when browsing is
    // centered. Keep the original nine-card travel distance, regardless of
    // deck size. Integer travel ends on the same grid of identical card backs;
    // identities resume their resting positions before selection is enabled.
    final travel = math.min(9, count) * shuffleLaps;
    return (index - Curves.easeInOut.transform(progress) * travel) % count;
  }

  Iterable<int> fanOrder(int count) {
    final indexes = List.generate(count, (index) => index);
    if (!shuffling) return indexes;
    final progress = initialShuffle
        ? ((shuffle.value - .32) / .68).clamp(0.0, 1.0)
        : shuffle.value;
    // Arc circulation follows the visible slot's depth, as in the approved
    // prototype; wrapped cards fade at the edge rather than returning behind.
    indexes.sort(
      (left, right) => shuffleSlot(
        left,
        count,
        progress,
      ).compareTo(shuffleSlot(right, count, progress)),
    );
    return indexes;
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        celestialCardBack,
        fit: BoxFit.contain,
        cacheWidth: 512,
      ),
    ),
  );
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.option});
  final FoodOption option;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('central-card-face'),
    width: 222,
    constraints: const BoxConstraints(minHeight: 264),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      border: Border.all(color: Theme.of(context).colorScheme.primary),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xfffff1d7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: OptionArt(option: option, size: 126),
        ),
        const SizedBox(height: 16),
        Text(
          option.name,
          key: const Key('draw-result'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
        if (option.scenario == MealScenario.restaurant.name) ...[
          if (option.address?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Text(option.address!, textAlign: TextAlign.center),
          ],
          if (option.notes?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(option.notes!, textAlign: TextAlign.center),
          ],
        ],
      ],
    ),
  );
}
