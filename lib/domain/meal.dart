enum MealScenario {
  eat('吃什么'),
  cook('做什么'),
  restaurant('去哪吃');

  const MealScenario(this.label);

  final String label;

  static MealScenario fromKey(String key) =>
      values.firstWhere((value) => value.name == key, orElse: () => eat);
}

const scenarioCategories = <MealScenario, List<String>>{
  MealScenario.eat: [
    '盖饭套餐',
    '面食',
    '粉类',
    '饺子馄饨',
    '包点饼类',
    '粥类',
    '轻食',
    '西式快餐',
    '饮品',
    '未分类',
  ],
  MealScenario.cook: ['家常菜', '快手菜', '下饭菜', '清爽小菜', '汤羹', '主食', '未分类'],
  MealScenario.restaurant: ['火锅', '烧烤', '中餐', '西餐', '快餐', '自助餐', '未分类'],
};

class MealCategory {
  const MealCategory({
    required this.id,
    required this.name,
    required this.scenario,
    required this.isBuiltIn,
    required this.isFallback,
  });

  final String id;
  final String name;
  final MealScenario scenario;
  final bool isBuiltIn;
  final bool isFallback;
}

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
    Set<String>? categories,
    this.isBuiltIn = true,
    this.isActive = true,
    this.isDeleted = false,
    this.imagePath,
    this.address,
    this.notes,
    this.recognitionId,
  }) : _categories = categories;

  final String id;
  final String name;
  final String art;
  final Set<MealPeriod> periods;
  final String scenario;
  final String category;
  final Set<String>? _categories;
  Set<String> get categories => Set.unmodifiable({category, ...?_categories});
  final bool isBuiltIn;
  final bool isActive;
  final bool isDeleted;
  final String? imagePath;
  final String? address;
  final String? notes;
  final String? recognitionId;
}

enum LibraryStatus { active, inactive, all }

enum OptionMutationStatus {
  saved,
  unchanged,
  duplicate,
  uncertainDuplicate,
  restorationRequired,
  renameConfirmationRequired,
  invalid,
  failed,
}

class OptionMutationResult {
  const OptionMutationResult(
    this.status, {
    this.option,
    this.message,
    this.matches = const [],
  });

  final OptionMutationStatus status;
  final FoodOption? option;
  final String? message;
  final List<FoodOption> matches;
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
    scenario: 'eat',
    category: '盖饭套餐',
    categories: {'盖饭套餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'noodles',
    name: '牛肉面',
    art: 'noodle',
    scenario: 'eat',
    category: '面食',
    categories: {'面食'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'buns',
    name: '小笼包',
    art: 'bun',
    scenario: 'eat',
    category: '包点饼类',
    categories: {'包点饼类'},
    periods: {MealPeriod.breakfast, MealPeriod.lunch},
  ),
  FoodOption(
    id: 'pancake',
    name: '煎饼果子',
    art: 'wrap',
    scenario: 'eat',
    category: '包点饼类',
    categories: {'包点饼类'},
    periods: {MealPeriod.breakfast, MealPeriod.lunch},
  ),
  FoodOption(
    id: 'porridge',
    name: '皮蛋瘦肉粥',
    art: 'porridge',
    scenario: 'eat',
    category: '粥类',
    categories: {'粥类'},
    periods: {MealPeriod.breakfast, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'burger',
    name: '汉堡套餐',
    art: 'burger',
    scenario: 'eat',
    category: '西式快餐',
    categories: {'西式快餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'soy-milk',
    name: '豆浆',
    art: 'drink',
    scenario: 'eat',
    category: '饮品',
    categories: {'饮品'},
    periods: {
      MealPeriod.breakfast,
      MealPeriod.lunch,
      MealPeriod.dinner,
      MealPeriod.lateNight,
    },
  ),
  FoodOption(
    id: 'soy-beverage',
    name: '豆奶',
    art: 'drink',
    scenario: 'eat',
    category: '饮品',
    categories: {'饮品'},
    periods: {
      MealPeriod.breakfast,
      MealPeriod.lunch,
      MealPeriod.dinner,
      MealPeriod.lateNight,
    },
  ),
  FoodOption(
    id: 'eat-kung-pao-rice',
    name: '宫保鸡丁盖饭',
    art: 'rice',
    scenario: 'eat',
    category: '盖饭套餐',
    categories: {'盖饭套餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'eat-braised-pork-rice',
    name: '红烧肉盖饭',
    art: 'rice',
    scenario: 'eat',
    category: '盖饭套餐',
    categories: {'盖饭套餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'eat-zhajiang-noodles',
    name: '炸酱面',
    art: 'noodle',
    scenario: 'eat',
    category: '面食',
    categories: {'面食'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-hot-dry-noodles',
    name: '热干面',
    art: 'noodle',
    scenario: 'eat',
    category: '面食',
    categories: {'面食'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-fried-noodles',
    name: '炒面',
    art: 'noodle',
    scenario: 'eat',
    category: '面食',
    categories: {'面食'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-guilin-noodles',
    name: '桂林米粉',
    art: 'noodle',
    scenario: 'eat',
    category: '粉类',
    categories: {'粉类'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-luosifen',
    name: '螺蛳粉',
    art: 'noodle',
    scenario: 'eat',
    category: '粉类',
    categories: {'粉类'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-sour-noodles',
    name: '酸辣粉',
    art: 'noodle',
    scenario: 'eat',
    category: '粉类',
    categories: {'粉类'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-dumplings',
    name: '水饺',
    art: 'bun',
    scenario: 'eat',
    category: '饺子馄饨',
    categories: {'饺子馄饨'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-potstickers',
    name: '锅贴',
    art: 'bun',
    scenario: 'eat',
    category: '饺子馄饨',
    categories: {'饺子馄饨'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-wontons',
    name: '馄饨',
    art: 'bun',
    scenario: 'eat',
    category: '饺子馄饨',
    categories: {'饺子馄饨'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-egg-flatbread',
    name: '鸡蛋灌饼',
    art: 'wrap',
    scenario: 'eat',
    category: '包点饼类',
    categories: {'包点饼类'},
    periods: {MealPeriod.breakfast, MealPeriod.lunch},
  ),
  FoodOption(
    id: 'eat-roujiamo',
    name: '肉夹馍',
    art: 'wrap',
    scenario: 'eat',
    category: '包点饼类',
    categories: {'包点饼类'},
    periods: {MealPeriod.breakfast, MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'eat-mixed-porridge',
    name: '杂粮粥',
    art: 'porridge',
    scenario: 'eat',
    category: '粥类',
    categories: {'粥类'},
    periods: {MealPeriod.breakfast, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-millet-porridge',
    name: '小米粥',
    art: 'porridge',
    scenario: 'eat',
    category: '粥类',
    categories: {'粥类'},
    periods: {MealPeriod.breakfast, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-pumpkin-porridge',
    name: '南瓜粥',
    art: 'porridge',
    scenario: 'eat',
    category: '粥类',
    categories: {'粥类'},
    periods: {MealPeriod.breakfast, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-salad',
    name: '蔬菜沙拉',
    art: 'plate',
    scenario: 'eat',
    category: '轻食',
    categories: {'轻食'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'eat-chicken-grain-rice',
    name: '鸡胸肉杂粮饭',
    art: 'rice',
    scenario: 'eat',
    category: '轻食',
    categories: {'轻食'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'eat-tuna-sandwich',
    name: '金枪鱼三明治',
    art: 'wrap',
    scenario: 'eat',
    category: '轻食',
    categories: {'轻食'},
    periods: {MealPeriod.breakfast, MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'eat-egg-vegetable-wrap',
    name: '鸡蛋蔬菜卷',
    art: 'wrap',
    scenario: 'eat',
    category: '轻食',
    categories: {'轻食'},
    periods: {MealPeriod.breakfast, MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'eat-pizza',
    name: '披萨',
    art: 'plate',
    scenario: 'eat',
    category: '西式快餐',
    categories: {'西式快餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'eat-fried-chicken',
    name: '炸鸡套餐',
    art: 'plate',
    scenario: 'eat',
    category: '西式快餐',
    categories: {'西式快餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'eat-milk',
    name: '牛奶',
    art: 'drink',
    scenario: 'eat',
    category: '饮品',
    categories: {'饮品'},
    periods: {
      MealPeriod.breakfast,
      MealPeriod.lunch,
      MealPeriod.dinner,
      MealPeriod.lateNight,
    },
  ),
  FoodOption(
    id: 'eat-yogurt',
    name: '酸奶',
    art: 'drink',
    scenario: 'eat',
    category: '饮品',
    categories: {'饮品'},
    periods: {
      MealPeriod.breakfast,
      MealPeriod.lunch,
      MealPeriod.dinner,
      MealPeriod.lateNight,
    },
  ),
  FoodOption(
    id: 'cook-tomato-eggs',
    name: '番茄炒蛋',
    art: 'plate',
    scenario: 'cook',
    category: '家常菜',
    categories: {'家常菜', '快手菜', '下饭菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-potato-beef',
    name: '土豆炖牛肉',
    art: 'plate',
    scenario: 'cook',
    category: '家常菜',
    categories: {'家常菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-braised-ribs',
    name: '红烧排骨',
    art: 'plate',
    scenario: 'cook',
    category: '家常菜',
    categories: {'家常菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-mushroom-chicken',
    name: '香菇滑鸡',
    art: 'plate',
    scenario: 'cook',
    category: '家常菜',
    categories: {'家常菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-pepper-eggs',
    name: '青椒炒蛋',
    art: 'plate',
    scenario: 'cook',
    category: '快手菜',
    categories: {'快手菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-sour-potatoes',
    name: '酸辣土豆丝',
    art: 'plate',
    scenario: 'cook',
    category: '快手菜',
    categories: {'快手菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-garlic-broccoli',
    name: '蒜蓉西兰花',
    art: 'plate',
    scenario: 'cook',
    category: '快手菜',
    categories: {'快手菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-cabbage',
    name: '手撕包菜',
    art: 'plate',
    scenario: 'cook',
    category: '快手菜',
    categories: {'快手菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-kung-pao-chicken',
    name: '宫保鸡丁',
    art: 'plate',
    scenario: 'cook',
    category: '下饭菜',
    categories: {'下饭菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-fish-fragrant-pork',
    name: '鱼香肉丝',
    art: 'plate',
    scenario: 'cook',
    category: '下饭菜',
    categories: {'下饭菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-mapo-tofu',
    name: '麻婆豆腐',
    art: 'plate',
    scenario: 'cook',
    category: '下饭菜',
    categories: {'下饭菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-twice-cooked-pork',
    name: '回锅肉',
    art: 'plate',
    scenario: 'cook',
    category: '下饭菜',
    categories: {'下饭菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-cucumber',
    name: '拍黄瓜',
    art: 'plate',
    scenario: 'cook',
    category: '清爽小菜',
    categories: {'清爽小菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-wood-ear',
    name: '凉拌木耳',
    art: 'plate',
    scenario: 'cook',
    category: '清爽小菜',
    categories: {'清爽小菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-scallion-tofu',
    name: '小葱拌豆腐',
    art: 'plate',
    scenario: 'cook',
    category: '清爽小菜',
    categories: {'清爽小菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-three-salad',
    name: '凉拌三丝',
    art: 'plate',
    scenario: 'cook',
    category: '清爽小菜',
    categories: {'清爽小菜'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-seaweed-egg-soup',
    name: '紫菜蛋花汤',
    art: 'porridge',
    scenario: 'cook',
    category: '汤羹',
    categories: {'汤羹'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-winter-melon-ribs',
    name: '冬瓜排骨汤',
    art: 'porridge',
    scenario: 'cook',
    category: '汤羹',
    categories: {'汤羹'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-corn-ribs',
    name: '玉米排骨汤',
    art: 'porridge',
    scenario: 'cook',
    category: '汤羹',
    categories: {'汤羹'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-mushroom-tofu-soup',
    name: '菌菇豆腐汤',
    art: 'porridge',
    scenario: 'cook',
    category: '汤羹',
    categories: {'汤羹'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'cook-steamed-egg',
    name: '鸡蛋羹',
    art: 'porridge',
    scenario: 'cook',
    category: '汤羹',
    categories: {'汤羹'},
    periods: {MealPeriod.breakfast, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'cook-egg-pancake',
    name: '鸡蛋饼',
    art: 'wrap',
    scenario: 'cook',
    category: '主食',
    categories: {'主食', '快手菜'},
    periods: {MealPeriod.breakfast, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'cook-tomato-egg-noodles',
    name: '番茄鸡蛋面',
    art: 'noodle',
    scenario: 'cook',
    category: '主食',
    categories: {'主食'},
    periods: {MealPeriod.breakfast, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'cook-greens-egg-noodles',
    name: '青菜鸡蛋面',
    art: 'noodle',
    scenario: 'cook',
    category: '主食',
    categories: {'主食'},
    periods: {MealPeriod.breakfast, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'cook-millet-porridge',
    name: '小米粥',
    art: 'porridge',
    scenario: 'cook',
    category: '主食',
    categories: {'主食'},
    periods: {MealPeriod.breakfast, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'cook-pumpkin-porridge',
    name: '南瓜粥',
    art: 'porridge',
    scenario: 'cook',
    category: '主食',
    categories: {'主食'},
    periods: {MealPeriod.breakfast, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'restaurant-haidilao',
    name: '海底捞',
    art: 'storefront',
    scenario: 'restaurant',
    category: '火锅',
    categories: {'火锅'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'restaurant-xiabuxiabu',
    name: '呷哺呷哺',
    art: 'storefront',
    scenario: 'restaurant',
    category: '火锅',
    categories: {'火锅'},
    periods: {MealPeriod.lunch, MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'restaurant-wooden-house',
    name: '木屋烧烤',
    art: 'storefront',
    scenario: 'restaurant',
    category: '烧烤',
    categories: {'烧烤'},
    periods: {MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'restaurant-long-ago',
    name: '很久以前羊肉串',
    art: 'storefront',
    scenario: 'restaurant',
    category: '烧烤',
    categories: {'烧烤'},
    periods: {MealPeriod.dinner, MealPeriod.lateNight},
  ),
  FoodOption(
    id: 'restaurant-xibei',
    name: '西贝莜面村',
    art: 'storefront',
    scenario: 'restaurant',
    category: '中餐',
    categories: {'中餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'restaurant-grandmas-home',
    name: '外婆家',
    art: 'storefront',
    scenario: 'restaurant',
    category: '中餐',
    categories: {'中餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'restaurant-pizza-hut',
    name: '必胜客',
    art: 'storefront',
    scenario: 'restaurant',
    category: '西餐',
    categories: {'西餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'restaurant-saizeriya',
    name: '萨莉亚',
    art: 'storefront',
    scenario: 'restaurant',
    category: '西餐',
    categories: {'西餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'restaurant-kfc',
    name: '肯德基',
    art: 'storefront',
    scenario: 'restaurant',
    category: '快餐',
    categories: {'快餐'},
    periods: {
      MealPeriod.breakfast,
      MealPeriod.lunch,
      MealPeriod.dinner,
      MealPeriod.lateNight,
    },
  ),
  FoodOption(
    id: 'restaurant-mcdonalds',
    name: '麦当劳',
    art: 'storefront',
    scenario: 'restaurant',
    category: '快餐',
    categories: {'快餐'},
    periods: {
      MealPeriod.breakfast,
      MealPeriod.lunch,
      MealPeriod.dinner,
      MealPeriod.lateNight,
    },
  ),
  FoodOption(
    id: 'restaurant-big-pizza',
    name: '比格比萨',
    art: 'storefront',
    scenario: 'restaurant',
    category: '自助餐',
    categories: {'自助餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
  FoodOption(
    id: 'restaurant-han-ba-wei-de',
    name: '汉巴味德',
    art: 'storefront',
    scenario: 'restaurant',
    category: '自助餐',
    categories: {'自助餐'},
    periods: {MealPeriod.lunch, MealPeriod.dinner},
  ),
];

class ConfirmationOperation {
  ConfirmationOperation({
    required this.operationId,
    required this.confirmedAt,
    required this.period,
    FoodOption? option,
    List<FoodOption>? options,
  }) : options = _orderedOptions(option, options);

  final String operationId;
  final DateTime confirmedAt;
  final MealPeriod period;
  final List<FoodOption> options;
  FoodOption get option => options.first;
}

class HistoryEntry {
  HistoryEntry({
    required this.operationId,
    required this.confirmedAt,
    required this.period,
    FoodOption? option,
    List<FoodOption>? options,
  }) : options = _orderedOptions(option, options);

  final String operationId;
  final DateTime confirmedAt;
  final MealPeriod period;
  final List<FoodOption> options;
  FoodOption get option => options.first;
}

List<FoodOption> _orderedOptions(
  FoodOption? option,
  List<FoodOption>? options,
) {
  if ((option == null) == (options == null)) {
    throw ArgumentError('Provide either option or options.');
  }
  return List.unmodifiable(options ?? [option!]);
}
