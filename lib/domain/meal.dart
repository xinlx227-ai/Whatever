enum MealPeriod {
  breakfast('早餐'),
  lunch('午餐'),
  dinner('晚餐'),
  lateNight('夜宵');

  const MealPeriod(this.label);

  final String label;

  static MealPeriod at(DateTime time) {
    final hour = time.hour;
    if (hour >= 5 && hour < 11) return breakfast;
    if (hour >= 11 && hour < 16) return lunch;
    if (hour >= 16 && hour < 21) return dinner;
    return lateNight;
  }
}

class FoodOption {
  const FoodOption({
    required this.id,
    required this.name,
    required this.art,
    required this.periods,
  });

  final String id;
  final String name;
  final String art;
  final Set<MealPeriod> periods;
}

const seedOptions = <FoodOption>[
  FoodOption(
    id: 'rice',
    name: '黄焖鸡米饭',
    art: 'rice',
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'noodles',
    name: '牛肉面',
    art: 'noodle',
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'buns',
    name: '小笼包',
    art: 'bun',
    periods: {MealPeriod.breakfast, MealPeriod.lunch},
  ),
  FoodOption(
    id: 'pancake',
    name: '煎饼果子',
    art: 'wrap',
    periods: {MealPeriod.breakfast, MealPeriod.lunch},
  ),
  FoodOption(
    id: 'porridge',
    name: '皮蛋瘦肉粥',
    art: 'porridge',
    periods: {MealPeriod.breakfast, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'burger',
    name: '汉堡套餐',
    art: 'burger',
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'soy-milk',
    name: '豆浆',
    art: 'drink',
    periods: {...MealPeriod.values},
  ),
  FoodOption(
    id: 'soy-beverage',
    name: '豆奶',
    art: 'drink',
    periods: {...MealPeriod.values},
  ),
];

class ConfirmationOperation {
  const ConfirmationOperation({
    required this.operationId,
    required this.confirmedAt,
    required this.period,
    required this.option,
  });

  final String operationId;
  final DateTime confirmedAt;
  final MealPeriod period;
  final FoodOption option;
}

class HistoryEntry {
  const HistoryEntry({
    required this.operationId,
    required this.confirmedAt,
    required this.period,
    required this.option,
  });

  final String operationId;
  final DateTime confirmedAt;
  final MealPeriod period;
  final FoodOption option;
}
