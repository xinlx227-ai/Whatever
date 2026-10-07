import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'application/meal_controller.dart';
import 'data/meal_repository.dart';
import 'presentation/meal_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  MealController? controller;
  bool failed = false;
  String? recoveredImage;
  String? imageRecoveryNotice;
  bool checkedPicker = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => failed = false);
    MealRepository? repository;
    try {
      repository = await MealRepository.open(
        factory: databaseFactory,
        path: p.join(await getDatabasesPath(), 'whatever.sqlite'),
      );
      final next = MealController(repository: repository);
      await next.initialize();
      if (!checkedPicker && Platform.isAndroid) {
        checkedPicker = true;
        try {
          final lost = await ImagePicker().retrieveLostData();
          if (lost.files?.isNotEmpty ?? false) {
            recoveredImage = lost.files!.first.path;
          } else if (lost.exception != null) {
            imageRecoveryNotice = '上次选择的图片未能读取，请在编辑时重新选择。';
          }
        } catch (_) {
          imageRecoveryNotice = '上次选择的图片未能读取，请在编辑时重新选择。';
        }
      }
      if (mounted) {
        setState(() => controller = next);
      } else {
        next.dispose();
        await repository.close();
      }
    } catch (_) {
      await repository?.close();
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return MealApp(
        controller: controller!,
        recoveredImage: recoveredImage,
        imageRecoveryNotice: imageRecoveryNotice,
      );
    }
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xfffffaf1),
        body: Center(
          child: failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('暂时无法打开本地记录，请重试'),
                    TextButton(onPressed: _open, child: const Text('重试')),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
