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
    this.scenario = 'eat',
    this.category = '未分类',
    this.isBuiltIn = true,
    this.isActive = true,
    this.isDeleted = false,
    this.imagePath,
  });

  final String id;
  final String name;
  final String art;
  final Set<MealPeriod> periods;
  final String scenario;
  final String category;
  final bool isBuiltIn;
  final bool isActive;
  final bool isDeleted;
  final String? imagePath;
}

enum LibraryStatus { active, inactive, all }

enum OptionMutationStatus {
  saved,
  unchanged,
  duplicate,
  restorationRequired,
  renameConfirmationRequired,
  invalid,
  failed,
}

class OptionMutationResult {
  const OptionMutationResult(this.status, {this.option, this.message});

  final OptionMutationStatus status;
  final FoodOption? option;
  final String? message;
  bool get changed => status == OptionMutationStatus.saved;
  bool get succeeded => changed || status == OptionMutationStatus.unchanged;
}

// Fold width variants only; punctuation and internal word boundaries stay intact.
String normalizedOptionName(String name) {
  const narrowKana =
      '。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン';
  const widthSymbols = {
    0xffe0: 0x00a2,
    0xffe1: 0x00a3,
    0xffe2: 0x00ac,
    0xffe3: 0x00af,
    0xffe4: 0x00a6,
    0xffe5: 0x00a5,
    0xffe6: 0x20a9,
    0xffe8: 0x2502,
    0xffe9: 0x2190,
    0xffea: 0x2191,
    0xffeb: 0x2192,
    0xffec: 0x2193,
    0xffed: 0x25a0,
    0xffee: 0x25cb,
  };
  final buffer = StringBuffer();
  for (final rune in name.runes) {
    if (rune >= 0xff01 && rune <= 0xff5e) {
      buffer.writeCharCode(rune - 0xfee0);
    } else if (rune == 0x3000) {
      buffer.write(' ');
    } else if (rune >= 0xff61 && rune <= 0xff9d) {
      buffer.write(narrowKana[rune - 0xff61]);
    } else if (rune == 0xff9e || rune == 0xff9f) {
      buffer.writeCharCode(rune == 0xff9e ? 0x3099 : 0x309a);
    } else if (rune == 0xffa0) {
      buffer.writeCharCode(0x3164);
    } else if (rune >= 0xffa1 && rune <= 0xffbe) {
      buffer.writeCharCode(rune - 0xce70);
    } else if (rune >= 0xffc2 && rune <= 0xffc7) {
      buffer.writeCharCode(rune - 0xce73);
    } else if (rune >= 0xffca && rune <= 0xffcf) {
      buffer.writeCharCode(rune - 0xce75);
    } else if (rune >= 0xffd2 && rune <= 0xffd7) {
      buffer.writeCharCode(rune - 0xce77);
    } else if (rune >= 0xffda && rune <= 0xffdc) {
      buffer.writeCharCode(rune - 0xce79);
    } else if (widthSymbols.containsKey(rune)) {
      buffer.writeCharCode(widthSymbols[rune]!);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  var value = buffer.toString();
  const voicedBase = 'ウカキクケコサシスセソタチツテトハヒフヘホワヰヱヲ';
  const voiced = 'ヴガギグゲゴザジズゼゾダヂヅデドバビブベボヷヸヹヺ';
  for (var index = 0; index < voicedBase.length; index++) {
    value = value.replaceAll('${voicedBase[index]}\u3099', voiced[index]);
  }
  const base = 'ハヒフヘホ';
  const semiVoiced = 'パピプペポ';
  for (var index = 0; index < base.length; index++) {
    value = value.replaceAll('${base[index]}\u309a', semiVoiced[index]);
  }
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
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
