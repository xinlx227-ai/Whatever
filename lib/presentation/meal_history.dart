import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../application/meal_controller.dart';
import '../domain/meal.dart';
import 'option_art.dart';

String _date(DateTime time) => '${time.year}年${time.month}月${time.day}日';
String _time(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String _summary(HistoryEntry entry) =>
    '${_time(entry.confirmedAt.toLocal())} · ${entry.period.label} · ${MealScenario.fromKey(entry.option.scenario).label}';

class MealHistory extends StatelessWidget {
  const MealHistory({
    super.key,
    required this.controller,
    required this.scenario,
    required this.onScenarioChanged,
    required this.onDecide,
  });

  final MealController controller;
  final MealScenario? scenario;
  final ValueChanged<MealScenario?> onScenarioChanged;
  final VoidCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final entries = controller.history.where(
      (entry) => scenario == null || entry.option.scenario == scenario!.name,
    );
    String? previousDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Text(
          '好好吃饭的足迹',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text('记下每一次不再纠结的决定。', style: TextStyle(color: muted)),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in <MealScenario?>[null, ...MealScenario.values])
              ChoiceChip(
                key: ValueKey('history-filter-${value?.name ?? 'all'}'),
                label: Text(value?.label ?? '全部'),
                selected: scenario == value,
                onSelected: (_) => onScenarioChanged(value),
              ),
          ],
        ),
        if (controller.needsDataRefresh) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              '本地数据暂时未能刷新，请重试。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton.icon(
            key: const Key('retry-history-refresh'),
            onPressed: controller.isBusy ? null : controller.retryDataRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(controller.isBusy ? '正在刷新…' : '重试刷新'),
          ),
        ],
        if (entries.isEmpty && !controller.needsDataRefresh)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                if (controller.history.isEmpty) ...[
                  ExcludeSemantics(
                    child: SvgPicture.asset(
                      'assets/food/rice.svg',
                      width: 120,
                      height: 120,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                Text(
                  controller.history.isEmpty ? '第一餐，值得期待' : '这个场景还没有足迹',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text('确认一次选择，就会在这里留下足迹。', style: TextStyle(color: muted)),
                const SizedBox(height: 24),
                if (controller.history.isEmpty)
                  FilledButton(onPressed: onDecide, child: const Text('去决定这一餐'))
                else
                  TextButton(
                    onPressed: () => onScenarioChanged(null),
                    child: const Text('查看全部足迹'),
                  ),
              ],
            ),
          ),
        for (final entry in entries) ...[
          if (previousDate != _date(entry.confirmedAt.toLocal()))
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: Text(
                previousDate = _date(entry.confirmedAt.toLocal()),
                style: TextStyle(color: muted, fontSize: 14),
              ),
            ),
          ListTile(
            key: ValueKey('history-${entry.operationId}'),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            leading: OptionArt(option: entry.option, size: 52),
            title: Text(
              entry.options.map((option) => option.name).join('、'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(_summary(entry)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => _HistoryDetail(
                  controller: controller,
                  operationId: entry.operationId,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _HistoryDetail extends StatefulWidget {
  const _HistoryDetail({required this.controller, required this.operationId});
  final MealController controller;
  final String operationId;

  @override
  State<_HistoryDetail> createState() => _HistoryDetailState();
}

class _HistoryDetailState extends State<_HistoryDetail> {
  bool deleting = false;
  String? error;

  Future<void> delete(HistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条足迹？'),
        content: Text(
          '将删除这次选择的完整记录（共 ${entry.options.length} 项），无法恢复。选项库中的内容会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('confirm-history-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除整条记录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      deleting = true;
      error = null;
    });
    try {
      final changed = await widget.controller.deleteHistory(widget.operationId);
      if (!mounted) return;
      final notice = widget.controller.needsDataRefresh
          ? changed
                ? '足迹已删除，但本地数据刷新失败，请重试刷新。'
                : '这条足迹已不存在，但本地数据刷新失败，请重试刷新。'
          : changed
          ? '已删除这条足迹'
          : '这条足迹已不存在';
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notice)));
    } catch (_) {
      if (mounted) {
        setState(() {
          deleting = false;
          error = '删除失败，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final matches = widget.controller.history.where(
        (entry) => entry.operationId == widget.operationId,
      );
      final entry = matches.firstOrNull;
      return PopScope(
        canPop: !deleting,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('足迹详情'),
            automaticallyImplyLeading: !deleting,
          ),
          body: SafeArea(
            child: entry == null
                ? const Center(child: Text('这条足迹已删除'))
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        _date(entry.confirmedAt.toLocal()),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(_summary(entry)),
                      const SizedBox(height: 24),
                      Text(
                        '这次选择 · 共 ${entry.options.length} 项',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      for (final option in entry.options)
                        Padding(
                          key: ValueKey('history-detail-${option.id}'),
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OptionArt(option: option, size: 72),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      option.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    if (option.address?.isNotEmpty == true) ...[
                                      const SizedBox(height: 8),
                                      Text('地址：${option.address}'),
                                    ],
                                    if (option.notes?.isNotEmpty == true) ...[
                                      const SizedBox(height: 8),
                                      Text('备注：${option.notes}'),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (error != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        key: const Key('delete-history-record'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 56),
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: deleting || widget.controller.isBusy
                            ? null
                            : () => delete(entry),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(deleting ? '正在删除…' : '删除这条足迹'),
                      ),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
