enum DrawMode { wheel, cards }

class MealPreferences {
  const MealPreferences({
    this.mode = DrawMode.wheel,
    this.excludeYesterday = false,
  });

  final DrawMode mode;
  final bool excludeYesterday;
}
