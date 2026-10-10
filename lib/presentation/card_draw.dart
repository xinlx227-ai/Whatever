import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/meal_controller.dart';
import '../domain/meal.dart';
import 'option_art.dart';

const celestialCardBack =
    'docs/design/assets/card-back-celestial-black-purple-gold.png';

/// The fan exposes positions only; hidden option identities stay in the model.
class CardDraw extends StatefulWidget {
  const CardDraw({
    super.key,
    required this.controller,
    required this.revealAnimation,
    required this.onReveal,
  });

  final MealController controller;
  final Animation<double> revealAnimation;
  final VoidCallback onReveal;

  @override
  State<CardDraw> createState() => _CardDrawState();
}

class _CardDrawState extends State<CardDraw> {
  final browsing = ScrollController();
  MealController get model => widget.controller;
  static const cardWidth = 96.0;
  static const cardStep = 64.0;

  @override
  void dispose() {
    browsing.dispose();
    super.dispose();
  }

  void tapCard(int index) {
    if (model.isBusy || model.isDrawing || !model.canDraw) return;
    if (model.selectedCardIndex == index) {
      widget.onReveal();
    } else {
      model.selectCard(index);
    }
  }

  void browse(int direction) {
    if (!browsing.hasClients) return;
    browsing.animateTo(
      (browsing.offset + direction * cardStep * 3).clamp(
        0.0,
        browsing.position.maxScrollExtent,
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final deck = model.cardDeck;
    final waiting = model.pendingReplacementIndex != null;
    final completed = model.results.isNotEmpty && !waiting && !model.isDrawing;
    final front = model.isDrawing ? model.selectedCard : model.result;
    final tutorial = !model.preferences.cardTutorialDismissed;
    final hint = model.isDrawing
        ? '正在为你翻开…'
        : completed
        ? tutorial
              ? '喜欢就确认，也可以换一个；确认后才会记入足迹。'
              : '确认之后，才会记入足迹。'
        : model.selectedCardIndex != null
        ? '已选第 ${model.selectedCardIndex! + 1} 张，再点一次翻开。'
        : waiting
        ? '重新选一张，再点一次翻开，完成替换。'
        : '左右浏览，点一张选中，再点一次翻开。';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        if (tutorial)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('skip-card-tutorial'),
              onPressed: model.dismissCardTutorial,
              child: const Text('跳过引导'),
            ),
          ),
        Semantics(
          liveRegion: true,
          child: Text(
            hint,
            key: const Key('card-guidance'),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                key: const Key('browse-cards-back'),
                tooltip: '向前浏览卡牌',
                onPressed: model.isDrawing ? null : () => browse(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${deck.length} 张牌',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              IconButton(
                key: const Key('browse-cards-forward'),
                tooltip: '向后浏览卡牌',
                onPressed: model.isDrawing ? null : () => browse(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          SizedBox(
            height: 196,
            child: GestureDetector(
              key: const Key('card-fan-blank'),
              behavior: HitTestBehavior.opaque,
              onTap: model.cancelCardSelection,
              child: SingleChildScrollView(
                key: const Key('card-fan-scroll'),
                controller: browsing,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(cardWidth + 32, deck.length * cardStep + 64),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var index = 0; index < deck.length; index++)
                        if (index != model.selectedCardIndex)
                          fanCard(index, deck.length),
                      if (model.selectedCardIndex case final int selected)
                        if (!model.isDrawing && !completed)
                          fanCard(selected, deck.length),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        AnimatedBuilder(
          animation: widget.revealAnimation,
          builder: (context, _) {
            if (front == null) {
              return GestureDetector(
                key: const Key('card-center-blank'),
                behavior: HitTestBehavior.opaque,
                onTap: model.cancelCardSelection,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 240),
                  alignment: Alignment.center,
                  child: Text(
                    deck.isEmpty ? '没有符合条件的选项' : '答案，等你亲手翻开',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              );
            }
            final progress = model.isDrawing
                ? widget.revealAnimation.value
                : 1.0;
            final reduced = MediaQuery.disableAnimationsOf(context);
            final travel = Curves.easeOutCubic.transform(
              (progress / .7).clamp(0.0, 1.0),
            );
            final flip = ((progress - .3) / .7).clamp(0.0, 1.0);
            final showFace = reduced || flip >= .5;
            final offset = browsing.hasClients ? browsing.offset : 0.0;
            final startX =
                ((model.selectedCardIndex ?? 0) * cardStep -
                        offset +
                        cardWidth / 2 -
                        (MediaQuery.sizeOf(context).width - 48) / 2)
                    .clamp(-120.0, 120.0);
            final face = showFace
                ? _CardFace(option: front)
                : const SizedBox(width: 256, height: 384, child: _CardBack());
            return Semantics(
              liveRegion: !model.isDrawing,
              child: Center(
                child: Transform.translate(
                  offset: reduced
                      ? Offset.zero
                      : Offset(startX * (1 - travel), -220 * (1 - travel)),
                  child: Transform.scale(
                    scale: reduced ? 1 : .38 + .62 * travel,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, .001)
                        ..rotateY(
                          reduced ? 0 : (showFace ? flip - 1 : flip) * math.pi,
                        ),
                      child: face,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget fanCard(int index, int count) {
    final selected = model.selectedCardIndex == index;
    final relative = (index - (count - 1) / 2).clamp(-2.0, 2.0);
    final enabled = model.canDraw && !model.isDrawing;
    return AnimatedPositioned(
      key: ValueKey('fan-position-$index'),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: 16 + index * cardStep,
      top: selected ? 0 : 20 + relative.abs() * 5,
      child: Transform.rotate(
        angle: selected ? 0 : relative * .07,
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
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: cardWidth,
                height: 144,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: selected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          )
                        : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(selected ? 3 : 0),
                    child: const _CardBack(),
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
    width: 256,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      border: Border.all(color: Theme.of(context).colorScheme.primary),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xfffff1d7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: OptionArt(option: option, size: 160),
        ),
        const SizedBox(height: 20),
        Text(
          option.name,
          key: const Key('draw-result'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}
