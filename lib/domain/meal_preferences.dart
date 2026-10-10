enum DrawMode { wheel, cards }

class MealPreferences {
  const MealPreferences({
    this.mode = DrawMode.wheel,
    this.excludeYesterday = false,
    this.cardTutorialDismissed = false,
    this.cardCollectionTutorialDismissed = false,
  });

  final DrawMode mode;
  final bool excludeYesterday;
  final bool cardTutorialDismissed;
  final bool cardCollectionTutorialDismissed;

  MealPreferences copyWith({
    DrawMode? mode,
    bool? excludeYesterday,
    bool? cardTutorialDismissed,
    bool? cardCollectionTutorialDismissed,
  }) => MealPreferences(
    mode: mode ?? this.mode,
    excludeYesterday: excludeYesterday ?? this.excludeYesterday,
    cardTutorialDismissed: cardTutorialDismissed ?? this.cardTutorialDismissed,
    cardCollectionTutorialDismissed:
        cardCollectionTutorialDismissed ?? this.cardCollectionTutorialDismissed,
  );
}
