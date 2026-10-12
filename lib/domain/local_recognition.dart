import 'meal.dart';

/// Confirmed identities can block duplicates; uncertain matches only suggest.
enum NameMatch { confirmed, uncertain, different, unknown }

/// Bounded local vocabulary. See docs/data/local-recognition.md for provenance.
class LocalRecognition {
  const LocalRecognition();

  static const datasetVersion = '2026-10-12.2';

  String? identity(String name, String scenario) {
    final resolved = _resolve(name, scenario);
    if (resolved == null) return null;
    return '$scenario:${resolved.entry.key}${resolved.branch}';
  }

  NameMatch compare(
    String a,
    String b,
    String scenario, {
    String? identityA,
    String? identityB,
  }) {
    final normalizedA = normalizedOptionName(a);
    final normalizedB = normalizedOptionName(b);
    if (normalizedA.isEmpty || normalizedB.isEmpty) return NameMatch.unknown;
    if (normalizedA == normalizedB) return NameMatch.confirmed;
    final keyA = _validIdentity(identityA, scenario) ?? identity(a, scenario);
    final keyB = _validIdentity(identityB, scenario) ?? identity(b, scenario);
    if (keyA != null && keyB != null) {
      if (keyA == keyB) return NameMatch.confirmed;
      if (scenario == MealScenario.restaurant.name) {
        final left = keyA.split('#branch:');
        final right = keyB.split('#branch:');
        if (left.first == right.first &&
            left.length == 2 &&
            right.length == 2) {
          // An unresolved retained branch label must not hide definite
          // location conflicts in the current names after a spelling rename.
          // Otherwise corrections still need explicit confirmation.
          return _distinctBranches(left.last, right.last) ||
                  _explicitIdentityConflict(normalizedA, normalizedB, scenario)
              ? NameMatch.different
              : NameMatch.uncertain;
        }
      }
      return NameMatch.different;
    }
    if (_explicitIdentityConflict(normalizedA, normalizedB, scenario)) {
      return NameMatch.different;
    }
    // Evidence must be lexical and bounded; punctuation and token boundaries
    // alone do not make otherwise unknown names equivalent.
    if (_related(normalizedA, normalizedB, scenario)) {
      return NameMatch.uncertain;
    }
    // A display-only rename must not remove the retained identity's warning
    // evidence when the other input cannot be resolved with certainty.
    final knownKey = keyA ?? keyB;
    if (knownKey != null) {
      final unknownName = keyA == null ? normalizedA : normalizedB;
      final entry = _entryForIdentity(knownKey)!;
      if (entry.names.any(
        (alias) => _related(normalizedOptionName(alias), unknownName, scenario),
      )) {
        return NameMatch.uncertain;
      }
    }
    return NameMatch.unknown;
  }

  bool _explicitIdentityConflict(String a, String b, String scenario) {
    if (scenario == MealScenario.restaurant.name) {
      final pattern = RegExp(r'^(.+)\(([^()]+店)\)$');
      String? branchLabel(String name) {
        final resolved = _resolve(name, scenario);
        if (resolved != null && resolved.branch.startsWith('#branch:')) {
          return resolved.branch.substring('#branch:'.length);
        }
        return pattern
            .firstMatch(name.replaceAll(RegExp(r'\s+'), ''))
            ?.group(2);
      }

      final left = branchLabel(a);
      final right = branchLabel(b);
      // Only enumerated location contrasts prove different branches. Script
      // variants or arbitrary spelling differences cannot veto a correction.
      return left != null && right != null && _distinctBranches(left, right);
    }
    String form(String value) => value
        .replaceAll('餛飩', '馄饨')
        .replaceAll('雲吞', '馄饨')
        .replaceAll('云吞', '馄饨')
        .replaceAll('麵', '面');
    final left = form(a);
    final right = form(b);
    return (left == '馄饨' && right == '馄饨面') || (right == '馄饨' && left == '馄饨面');
  }

  bool matchesSearch(FoodOption option, String query) {
    final needle = normalizedOptionName(query);
    if (needle.isEmpty) return true;
    if (normalizedOptionName(option.name).contains(needle)) return true;
    final key =
        _validIdentity(option.recognitionId, option.scenario) ??
        identity(option.name, option.scenario);
    if (key == null) return false;
    final entry = _entryForIdentity(key);
    if (entry == null) return false;
    if (entry.names.any(
      (name) => normalizedOptionName(name).contains(needle),
    )) {
      return true;
    }
    // Alias search can retrieve branches, but never merges their identities.
    final queryIdentity = identity(query, option.scenario);
    return queryIdentity != null &&
        (queryIdentity == key ||
            (option.scenario == 'restaurant' &&
                key.startsWith('$queryIdentity#branch:')));
  }

  String inferCategoryId(
    String name,
    MealScenario scenario,
    List<MealCategory> categories,
  ) {
    final available = categories
        .where((category) => category.scenario == scenario)
        .toList();
    final fallback = available.singleWhere((category) => category.isFallback);
    final resolved = _resolve(name, scenario.name);
    if (resolved == null) return fallback.id;
    final canonical = resolved.entry.name;
    final customMatches = available
        .where(
          (category) =>
              !category.isBuiltIn &&
              _matchesCustomCategory(resolved.entry, category.name),
        )
        .toList();
    if (customMatches.length > 1) return fallback.id;
    if (customMatches.length == 1) return customMatches.single.id;

    // Category identity is stable even after a label rename.
    final sameScenario = _entries.where(
      (entry) => entry.scenario == scenario.name && entry.name == canonical,
    );
    final categoryName = sameScenario.isNotEmpty
        ? sameScenario.single.category
        : _crossScenarioCategory(resolved.entry, scenario);
    if (categoryName == null) return fallback.id;
    final index = scenarioCategories[scenario]!.indexOf(categoryName);
    if (index < 0) return fallback.id;
    final categoryId = 'builtin-category-${scenario.name}-$index';
    for (final category in available) {
      if (category.id == categoryId) return category.id;
    }
    return fallback.id;
  }

  String? _crossScenarioCategory(_Entry entry, MealScenario scenario) {
    if (scenario == MealScenario.eat) {
      if (_ingredientEvidence['noodles']!.contains(entry.key)) return '面食';
      if (_ingredientEvidence['porridge']!.contains(entry.key)) return '粥类';
      if (entry.key == 'cook-egg-pancake') return '包点饼类';
    }
    if (scenario == MealScenario.cook &&
        {'盖饭套餐', '面食', '粉类', '饺子馄饨', '包点饼类', '粥类'}.contains(entry.category)) {
      return '主食';
    }
    return null;
  }

  String? _validIdentity(String? value, String scenario) =>
      value != null &&
          value.startsWith('$scenario:') &&
          _entryForIdentity(value) != null
      ? value
      : null;

  _Entry? _entryForIdentity(String identity) {
    final separator = identity.indexOf(':');
    if (separator < 0) return null;
    final key = identity.substring(separator + 1).split('#branch:').first;
    for (final entry in _entries) {
      if (entry.key == key) return entry;
    }
    return null;
  }

  _Resolved? _resolve(String name, String scenario) {
    if (!MealScenario.values.any((value) => value.name == scenario)) {
      return null;
    }
    final normalized = normalizedOptionName(name);
    if (normalized.isEmpty) return null;
    final entries = _entries.where(
      (entry) => scenario == 'restaurant'
          ? entry.scenario == 'restaurant'
          : entry.scenario != 'restaurant',
    );
    // Prefer scenario-specific records for foods present in both inventories.
    final ordered = [
      ...entries.where((entry) => entry.scenario == scenario),
      ...entries.where((entry) => entry.scenario != scenario),
    ];
    for (final entry in ordered) {
      for (final alias in entry.names) {
        if (normalized == normalizedOptionName(alias)) {
          return _Resolved(entry, '');
        }
      }
    }
    for (final entry in ordered) {
      for (final alias in entry.names) {
        final base = normalizedOptionName(alias);
        if (!normalized.startsWith(base)) continue;
        final suffix = normalized.substring(base.length).trim();
        if (scenario == 'restaurant') {
          final branch = _branch.firstMatch(suffix);
          if (branch != null) {
            final label = (branch.group(1) ?? branch.group(2))!.trim();
            return _Resolved(entry, '#branch:$label');
          }
        } else {
          var modifiers = suffix;
          if (modifiers.startsWith('(') && modifiers.endsWith(')')) {
            modifiers = modifiers.substring(1, modifiers.length - 1);
          }
          if (_hasCompleteModifiers(modifiers)) return _Resolved(entry, '');
        }
      }
    }
    return null;
  }

  bool _related(String a, String b, String scenario) {
    if (scenario != 'restaurant') {
      for (final entry in _ambiguousFoodNames.entries) {
        if ((a.contains(entry.key) && entry.value.any(b.contains)) ||
            (b.contains(entry.key) && entry.value.any(a.contains))) {
          return true;
        }
      }
    }
    for (final entry in _entries) {
      if ((scenario == 'restaurant') != (entry.scenario == 'restaurant')) {
        continue;
      }
      final aliases = entry.names.map(normalizedOptionName);
      if (aliases.any(a.contains) && aliases.any(b.contains)) return true;
    }
    // Chinese near-spellings are warning evidence only, never hard matches.
    if (RegExp(r'^[\u3400-\u9fff]+$').hasMatch(a) &&
        RegExp(r'^[\u3400-\u9fff]+$').hasMatch(b) &&
        a.length >= 3 &&
        b.length >= 3 &&
        (identity(a, scenario) != null || identity(b, scenario) != null)) {
      return _oneEditApart(a, b);
    }
    return false;
  }

  bool _matchesCustomCategory(_Entry entry, String categoryName) {
    final category = normalizedOptionName(categoryName);
    if (entry.names.any((name) => normalizedOptionName(name) == category)) {
      return true;
    }
    if (entry.scenario == 'restaurant') return false;
    for (final concept in _customConcepts.entries) {
      if (!concept.value.contains(category)) continue;
      if (_ingredientEvidence[concept.key]?.contains(entry.key) ?? false) {
        return true;
      }
    }
    return false;
  }
}

class _Entry {
  const _Entry(
    this.key,
    this.name,
    this.scenario,
    this.category, [
    this.aliases = const [],
  ]);

  final String key;
  final String name;
  final String scenario;
  final String category;
  final List<String> aliases;
  Iterable<String> get names => [name, ...aliases];
}

class _Resolved {
  const _Resolved(this.entry, this.branch);
  final _Entry entry;
  final String branch;
}

final _branch = RegExp(r'^(?:\(([^()]+店)\)|([^()]+店))$');
// Curated negative evidence only: these labels never create positive aliases
// or change retained branch identity keys. Unlisted labels remain unresolved.
const _branchLocations = <String, String>{
  '东街店': 'east-street',
  '東街店': 'east-street',
  '西街店': 'west-street',
  '人民路店': 'people-road',
  '茶山店': 'tea-mountain',
};

bool _distinctBranches(String a, String b) {
  final left = _branchLocations[a];
  final right = _branchLocations[b];
  return left != null && right != null && left != right;
}

// Longest tokens come first. The cursor only moves forward, so malformed
// trailing text takes linear time and never triggers regex backtracking.
const _modifierTokens = [
  '加鸡蛋',
  '加牛肉',
  '加鸡肉',
  '加香菜',
  '加豆腐',
  '加青菜',
  '多油',
  '少油',
  '少糖',
  '多醋',
  '微辣',
  '不辣',
  '少辣',
  '中辣',
  '重辣',
  '特辣',
  '加辣',
  '无糖',
  '少盐',
  '多盐',
  '多糖',
  '加蛋',
  '加肉',
  '加葱',
];

bool _hasCompleteModifiers(String value) {
  var cursor = 0;
  var hasToken = false;
  while (cursor < value.length) {
    if (',，、 '.contains(value[cursor])) {
      cursor++;
      continue;
    }
    String? matched;
    for (final token in _modifierTokens) {
      if (value.startsWith(token, cursor)) {
        matched = token;
        break;
      }
    }
    if (matched == null) return false;
    hasToken = true;
    cursor += matched.length;
  }
  return hasToken;
}

bool _oneEditApart(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0;
  var j = 0;
  var edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length >= b.length) i++;
    if (b.length >= a.length) j++;
  }
  return edits + (a.length - i) + (b.length - j) == 1;
}

// Every row is project-curated; seed IDs provide stable provenance.
const _entries = <_Entry>[
  _Entry('rice', '黄焖鸡米饭', 'eat', '盖饭套餐', ['黄焖鸡饭']),
  _Entry('noodles', '牛肉面', 'eat', '面食'),
  _Entry('buns', '小笼包', 'eat', '包点饼类', ['小笼包子']),
  _Entry('pancake', '煎饼果子', 'eat', '包点饼类', ['煎饼馃子']),
  _Entry('porridge', '皮蛋瘦肉粥', 'eat', '粥类', ['松花蛋瘦肉粥']),
  _Entry('burger', '汉堡套餐', 'eat', '西式快餐'),
  _Entry('soy-milk', '豆浆', 'eat', '饮品', ['豆漿']),
  _Entry('soy-beverage', '豆奶', 'eat', '饮品'),
  _Entry('eat-kung-pao-rice', '宫保鸡丁盖饭', 'eat', '盖饭套餐'),
  _Entry('eat-braised-pork-rice', '红烧肉盖饭', 'eat', '盖饭套餐'),
  _Entry('eat-zhajiang-noodles', '炸酱面', 'eat', '面食', ['炸醬面']),
  _Entry('eat-hot-dry-noodles', '热干面', 'eat', '面食'),
  _Entry('eat-fried-noodles', '炒面', 'eat', '面食'),
  _Entry('eat-guilin-noodles', '桂林米粉', 'eat', '粉类'),
  _Entry('eat-luosifen', '螺蛳粉', 'eat', '粉类', ['螺狮粉']),
  _Entry('eat-sour-noodles', '酸辣粉', 'eat', '粉类'),
  _Entry('eat-dumplings', '水饺', 'eat', '饺子馄饨'),
  _Entry('eat-potstickers', '锅贴', 'eat', '饺子馄饨'),
  _Entry('eat-wontons', '馄饨', 'eat', '饺子馄饨', ['云吞', '餛飩']),
  _Entry('eat-egg-flatbread', '鸡蛋灌饼', 'eat', '包点饼类'),
  _Entry('eat-roujiamo', '肉夹馍', 'eat', '包点饼类', ['肉夾馍']),
  _Entry('eat-mixed-porridge', '杂粮粥', 'eat', '粥类'),
  _Entry('eat-millet-porridge', '小米粥', 'eat', '粥类'),
  _Entry('eat-pumpkin-porridge', '南瓜粥', 'eat', '粥类'),
  _Entry('eat-salad', '蔬菜沙拉', 'eat', '轻食', ['蔬菜色拉']),
  _Entry('eat-chicken-grain-rice', '鸡胸肉杂粮饭', 'eat', '轻食'),
  _Entry('eat-tuna-sandwich', '金枪鱼三明治', 'eat', '轻食'),
  _Entry('eat-egg-vegetable-wrap', '鸡蛋蔬菜卷', 'eat', '轻食'),
  _Entry('eat-pizza', '披萨', 'eat', '西式快餐', ['比萨', '匹萨']),
  _Entry('eat-fried-chicken', '炸鸡套餐', 'eat', '西式快餐'),
  _Entry('eat-milk', '牛奶', 'eat', '饮品'),
  _Entry('eat-yogurt', '酸奶', 'eat', '饮品', ['酸乳']),
  _Entry('cook-tomato-eggs', '番茄炒蛋', 'cook', '家常菜', [
    '西红柿炒鸡蛋',
    '西红柿炒蛋',
    '番茄炒鸡蛋',
  ]),
  _Entry('cook-potato-beef', '土豆炖牛肉', 'cook', '家常菜', ['马铃薯炖牛肉']),
  _Entry('cook-braised-ribs', '红烧排骨', 'cook', '家常菜'),
  _Entry('cook-mushroom-chicken', '香菇滑鸡', 'cook', '家常菜'),
  _Entry('cook-pepper-eggs', '青椒炒蛋', 'cook', '快手菜', ['青椒炒鸡蛋']),
  _Entry('cook-sour-potatoes', '酸辣土豆丝', 'cook', '快手菜', ['酸辣马铃薯丝']),
  _Entry('cook-garlic-broccoli', '蒜蓉西兰花', 'cook', '快手菜'),
  _Entry('cook-cabbage', '手撕包菜', 'cook', '快手菜', ['手撕圆白菜']),
  _Entry('cook-kung-pao-chicken', '宫保鸡丁', 'cook', '下饭菜', ['宫保鸡肉丁']),
  _Entry('cook-fish-fragrant-pork', '鱼香肉丝', 'cook', '下饭菜'),
  _Entry('cook-mapo-tofu', '麻婆豆腐', 'cook', '下饭菜'),
  _Entry('cook-twice-cooked-pork', '回锅肉', 'cook', '下饭菜'),
  _Entry('cook-cucumber', '拍黄瓜', 'cook', '清爽小菜'),
  _Entry('cook-wood-ear', '凉拌木耳', 'cook', '清爽小菜', ['木耳凉拌']),
  _Entry('cook-scallion-tofu', '小葱拌豆腐', 'cook', '清爽小菜'),
  _Entry('cook-three-salad', '凉拌三丝', 'cook', '清爽小菜'),
  _Entry('cook-seaweed-egg-soup', '紫菜蛋花汤', 'cook', '汤羹', ['紫菜鸡蛋汤']),
  _Entry('cook-winter-melon-ribs', '冬瓜排骨汤', 'cook', '汤羹'),
  _Entry('cook-corn-ribs', '玉米排骨汤', 'cook', '汤羹'),
  _Entry('cook-mushroom-tofu-soup', '菌菇豆腐汤', 'cook', '汤羹'),
  _Entry('cook-steamed-egg', '鸡蛋羹', 'cook', '汤羹', ['蒸蛋羹']),
  _Entry('cook-egg-pancake', '鸡蛋饼', 'cook', '主食'),
  _Entry('cook-tomato-egg-noodles', '番茄鸡蛋面', 'cook', '主食', ['西红柿鸡蛋面', '番茄蛋面']),
  _Entry('cook-greens-egg-noodles', '青菜鸡蛋面', 'cook', '主食', ['青菜蛋面']),
  _Entry('cook-millet-porridge', '小米粥', 'cook', '主食'),
  _Entry('cook-pumpkin-porridge', '南瓜粥', 'cook', '主食'),
  _Entry('restaurant-haidilao', '海底捞', 'restaurant', '火锅'),
  _Entry('restaurant-xiabuxiabu', '呷哺呷哺', 'restaurant', '火锅'),
  _Entry('restaurant-wooden-house', '木屋烧烤', 'restaurant', '烧烤'),
  _Entry('restaurant-long-ago', '很久以前羊肉串', 'restaurant', '烧烤'),
  _Entry('restaurant-xibei', '西贝莜面村', 'restaurant', '中餐'),
  _Entry('restaurant-grandmas-home', '外婆家', 'restaurant', '中餐'),
  _Entry('restaurant-pizza-hut', '必胜客', 'restaurant', '西餐', ['Pizza Hut']),
  _Entry('restaurant-saizeriya', '萨莉亚', 'restaurant', '西餐'),
  _Entry('restaurant-kfc', '肯德基', 'restaurant', '快餐', ['KFC']),
  _Entry('restaurant-mcdonalds', '麦当劳', 'restaurant', '快餐', [
    'McDonald\'s',
    'McDonalds',
  ]),
  _Entry('restaurant-big-pizza', '比格比萨', 'restaurant', '自助餐', ['比格披萨']),
  _Entry('restaurant-han-ba-wei-de', '汉巴味德', 'restaurant', '自助餐'),
  _Entry('tomato-egg-soup', '番茄鸡蛋汤', 'cook', '汤羹', ['西红柿鸡蛋汤', '番茄蛋汤', '西红柿蛋汤']),
  _Entry('tomato-egg-rice', '番茄鸡蛋盖饭', 'eat', '盖饭套餐', [
    '西红柿鸡蛋盖饭',
    '番茄炒蛋盖饭',
    '西红柿炒鸡蛋盖饭',
  ]),
  _Entry('chicken-noodles', '鸡肉面', 'eat', '面食'),
];

// This wording has competing meanings across the protected soy identities.
const _ambiguousFoodNames = <String, List<String>>{
  '豆乳': ['豆浆', '豆漿', '豆奶'],
};

const _customConcepts = <String, Set<String>>{
  'egg': {'鸡蛋', '鸡蛋类', '蛋类'},
  'tomato': {'番茄', '番茄类', '西红柿', '西红柿类'},
  'beef': {'牛肉', '牛肉类'},
  'tofu': {'豆腐', '豆腐类', '豆制品'},
  'noodles': {'面条', '面条类', '面类'},
  'porridge': {'粥', '粥类'},
};

const _ingredientEvidence = <String, Set<String>>{
  'egg': {
    'cook-tomato-eggs',
    'cook-pepper-eggs',
    'cook-seaweed-egg-soup',
    'cook-steamed-egg',
    'cook-egg-pancake',
    'cook-tomato-egg-noodles',
    'cook-greens-egg-noodles',
    'eat-egg-flatbread',
    'eat-egg-vegetable-wrap',
    'tomato-egg-soup',
    'tomato-egg-rice',
  },
  'tomato': {
    'cook-tomato-eggs',
    'cook-tomato-egg-noodles',
    'tomato-egg-soup',
    'tomato-egg-rice',
  },
  'beef': {'noodles', 'cook-potato-beef'},
  'tofu': {'cook-mapo-tofu', 'cook-scallion-tofu', 'cook-mushroom-tofu-soup'},
  'noodles': {
    'noodles',
    'eat-zhajiang-noodles',
    'eat-hot-dry-noodles',
    'eat-fried-noodles',
    'cook-tomato-egg-noodles',
    'cook-greens-egg-noodles',
    'chicken-noodles',
  },
  'porridge': {
    'porridge',
    'eat-mixed-porridge',
    'eat-millet-porridge',
    'eat-pumpkin-porridge',
    'cook-millet-porridge',
    'cook-pumpkin-porridge',
  },
};
