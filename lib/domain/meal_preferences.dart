enum DrawMode { wheel, cards }

class MealPreferences {
  const MealPreferences({
    this.mode = DrawMode.wheel,
    this.excludeYesterday = false,
    this.cardTutorialDismissed = false,
  });

  final DrawMode mode;
  final bool excludeYesterday;
  final bool cardTutorialDismissed;

  MealPreferences copyWith({
    DrawMode? mode,
    bool? excludeYesterday,
    bool? cardTutorialDismissed,
  }) => MealPreferences(
    mode: mode ?? this.mode,
    excludeYesterday: excludeYesterday ?? this.excludeYesterday,
    cardTutorialDismissed: cardTutorialDismissed ?? this.cardTutorialDismissed,
  );
}
