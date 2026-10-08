import '../domain/meal.dart';

class ScenarioCopy {
  const ScenarioCopy({
    required this.heading,
    required this.wheelLabel,
    required this.resultHint,
    required this.drawAction,
    required this.confirmAction,
    required this.confirmationNotice,
  });

  final String heading;
  final String wheelLabel;
  final String resultHint;
  final String drawAction;
  final String confirmAction;
  final String confirmationNotice;

  static ScenarioCopy forScenario(MealScenario scenario) => switch (scenario) {
    MealScenario.eat => const ScenarioCopy(
      heading: '今天，吃点什么？',
      wheelLabel: '开饭',
      resultHint: '这一餐，就吃点喜欢的',
      drawAction: '转一下，开饭',
      confirmAction: '就吃这个',
      confirmationNotice: '这一餐已记入足迹，好好享用吧',
    ),
    MealScenario.cook => const ScenarioCopy(
      heading: '今天，做点什么？',
      wheelLabel: '下厨',
      resultHint: '这一餐，做一道喜欢的',
      drawAction: '转一下，挑道菜',
      confirmAction: '就做这道',
      confirmationNotice: '这一餐已记入足迹，准备下厨吧',
    ),
    MealScenario.restaurant => const ScenarioCopy(
      heading: '今天，去哪儿吃？',
      wheelLabel: '出发',
      resultHint: '这一餐，去这里吃',
      drawAction: '转一下，选家餐厅',
      confirmAction: '就去这家',
      confirmationNotice: '这家餐厅已记入足迹，出发吧',
    ),
  };
}
