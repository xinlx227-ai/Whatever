import 'package:flutter/material.dart';

import '../application/meal_controller.dart';

Future<bool> requestOnlineConsent(
  BuildContext context,
  MealController controller,
) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('开启在线识别？'),
      scrollable: true,
      content: const Text(
        '本地无法确定时，由小米 MiMo 辅助分类和查找可能重复的选项。\n\n'
        '将发送当前名称、场景、可用分类名称，以及同场景中必要的候选名称与临时编号；'
        '不发送足迹、照片、地址或备注。小米也会接收网络连接所需的 IP 信息。\n\n'
        '结果可能有误，分类可手动修改；重复提示由你决定。等待最多 3 秒，随时可直接保存。'
        '每台设备每天最多 30 次、每分钟最多 6 次，失败或超限仍可本地添加。\n\n'
        '境内使用时数据存储在境内。小米声明未经事先同意不将提交的文本用于模型训练。数据按服务需要及法律要求保留，'
        '不承诺零留存。可在选项库右上角的设置中随时关闭。拒绝不影响本地功能。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('仅用本地'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('同意并开启'),
        ),
      ],
    ),
  );
  return controller.setOnlineRecognition(
    enabled: agreed == true,
    consent: agreed == true,
  );
}

class OnlineRecognitionSettingsPage extends StatefulWidget {
  const OnlineRecognitionSettingsPage({super.key, required this.controller});
  final MealController controller;

  @override
  State<OnlineRecognitionSettingsPage> createState() =>
      _OnlineRecognitionSettingsPageState();
}

class _OnlineRecognitionSettingsPageState
    extends State<OnlineRecognitionSettingsPage> {
  bool busy = false;
  String? error;

  Future<void> change(bool value) async {
    setState(() {
      busy = true;
      error = null;
    });
    final controller = widget.controller;
    final saved = value && !controller.onlineSettings.consentGranted
        ? await requestOnlineConsent(context, controller)
        : await controller.setOnlineRecognition(enabled: value);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = saved ? null : '设置暂时无法保存，请重试。';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('在线识别'),
            subtitle: const Text('由小米 MiMo 辅助分类与查重；关闭后仅使用本地识别。'),
            value: widget.controller.onlineSettings.enabled,
            onChanged: busy ? null : change,
          ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        ],
      ),
    ),
  );
}
