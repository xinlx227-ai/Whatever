import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../application/meal_controller.dart';
import '../data/option_images.dart';
import '../domain/meal.dart';
import 'option_art.dart';

class OptionEditor extends StatefulWidget {
  const OptionEditor({
    super.key,
    required this.controller,
    this.option,
    this.initialImagePath,
    this.pickImage,
    this.images,
    this.scenario = MealScenario.eat,
  });
  final MealController controller;
  final FoodOption? option;
  final String? initialImagePath;
  final Future<String?> Function()? pickImage;
  final OptionImages? images;
  final MealScenario scenario;

  @override
  State<OptionEditor> createState() => _OptionEditorState();
}

class _OptionEditorState extends State<OptionEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController address;
  late final TextEditingController notes;
  late Set<MealPeriod> periods;
  late String category;
  String? selectedImage;
  String? ownedImage;
  final Set<String> imageCleanupCandidates = {};
  late final OptionImages images;
  String? error;
  bool busy = false;
  bool leaving = false;
  bool asking = false;
  FoodOption? get original => widget.option;
  MealScenario get scenario => original == null
      ? widget.scenario
      : MealScenario.fromKey(original!.scenario);
  bool get isRestaurant => scenario == MealScenario.restaurant;
  bool get dirty =>
      name.text != (original?.name ?? '') ||
      address.text != (original?.address ?? '') ||
      notes.text != (original?.notes ?? '') ||
      selectedImage != null ||
      category != (original?.category ?? '未分类') ||
      !setEqualsPeriods(periods, initialPeriods);
  late final Set<MealPeriod> initialPeriods;

  bool setEqualsPeriods(Set<MealPeriod> a, Set<MealPeriod> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  void initState() {
    super.initState();
    images = widget.images ?? OptionImages();
    name = TextEditingController(text: original?.name ?? '');
    address = TextEditingController(text: original?.address ?? '');
    notes = TextEditingController(text: original?.notes ?? '');
    initialPeriods = {...?original?.periods};
    if (original == null) {
      initialPeriods.add(widget.controller.currentLocalPeriod);
    }
    periods = {...initialPeriods};
    category = original?.category ?? '未分类';
    selectedImage = widget.initialImagePath;
    name.addListener(refresh);
    address.addListener(refresh);
    notes.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(
      images.discardUnreferenced(
        imageCleanupCandidates,
        widget.controller.imagePathsInUse,
      ),
    );
    name.removeListener(refresh);
    name.dispose();
    address.removeListener(refresh);
    address.dispose();
    notes.removeListener(refresh);
    notes.dispose();
    super.dispose();
  }

  Future<bool> ask(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> close() async {
    if (busy || asking) return;
    asking = true;
    final discard = !dirty || await ask('放弃未保存的修改？', '这次填写的内容还没有保存。', '放弃修改');
    asking = false;
    if (!mounted || !discard) return;
    setState(() => leaving = true);
    // Allow PopScope to publish the new disposition before popping.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> chooseImage() async {
    setState(() => busy = true);
    try {
      final path = widget.pickImage != null
          ? await widget.pickImage!()
          : (await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 90,
              requestFullMetadata: false,
            ))?.path;
      if (mounted && path != null) {
        setState(() {
          selectedImage = path;
          ownedImage = null;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '图片暂时无法读取，请重新选择。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> resolveDuplicate(FoodOption option) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isRestaurant ? '已有同名餐厅' : '已有同名餐食'),
        content: Text(
          '“${option.name}”${option.isActive ? '已在选项库中' : '目前已停用'}，不会创建重复选项。'
          '${!option.isActive && !option.isDeleted ? '重新启用会保留原有资料，本次表单内容不会保存。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'view'),
            child: const Text('查看已有选项'),
          ),
          if (!option.isActive && !option.isDeleted)
            TextButton(
              onPressed: () => Navigator.pop(context, 'reactivate'),
              child: const Text('重新启用'),
            ),
        ],
      ),
    );
    if (!mounted) return false;
    if (action == 'view') {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(option.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OptionArt(option: option, size: 100),
                const SizedBox(height: 12),
                Text(
                  '${option.categories.join(' / ')} · ${option.isDeleted
                      ? '已删除'
                      : option.isActive
                      ? '已启用'
                      : '已停用'}',
                ),
                Text(
                  MealPeriod.values
                      .where(option.periods.contains)
                      .map((period) => period.label)
                      .join(' · '),
                ),
                if (option.address != null) Text(option.address!),
                if (option.notes != null) Text(option.notes!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回表单'),
            ),
          ],
        ),
      );
    } else if (action == 'reactivate') {
      final result = await widget.controller.setOptionActive(option.id, true);
      if (!mounted) return false;
      if (result.succeeded) return true;
      setState(() => error = result.message);
    }
    return false;
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (periods.isEmpty) {
      setState(() => error = '请至少选择一个餐段。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (selectedImage != null && ownedImage == null) {
        ownedImage = await images.persist(
          selectedImage!,
          existingPath: original?.imagePath,
        );
        imageCleanupCandidates.add(ownedImage!);
      }
      var restore = false;
      var sameFood = false;
      while (mounted) {
        final result = await widget.controller.saveOption(
          id: original?.id,
          name: name.text,
          periods: periods,
          scenario: scenario.name,
          category: category,
          address: isRestaurant ? address.text : null,
          notes: isRestaurant ? notes.text : null,
          imagePath: ownedImage ?? original?.imagePath,
          confirmRestore: restore,
          confirmSameFood: sameFood,
        );
        if (!mounted) return;
        if (result.succeeded) {
          if (original?.imagePath != null) {
            imageCleanupCandidates.add(original!.imagePath!);
          }
          await images.discardUnreferenced(
            imageCleanupCandidates,
            widget.controller.imagePathsInUse,
          );
          if (!mounted) return;
          setState(() => leaving = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context, true);
          });
          return;
        }
        if (result.status == OptionMutationStatus.restorationRequired) {
          if (await ask(
            '恢复原来的选项？',
            '“${result.option!.name}”曾被删除。恢复会沿用原来的身份，与已有足迹保持关联。',
            '恢复并保存',
          )) {
            restore = true;
            if (result.option!.imagePath != null) {
              imageCleanupCandidates.add(result.option!.imagePath!);
            }
            continue;
          }
        } else if (result.status ==
            OptionMutationStatus.renameConfirmationRequired) {
          if (await ask(
            isRestaurant ? '还是同一家餐厅吗？' : '还是同一种餐食吗？',
            isRestaurant
                ? '如果只是修改叫法，可以保留原来的足迹关联；如果换成了另一家餐厅，请另建选项。'
                : '如果只是修改叫法，可以保留原来的足迹关联；如果换成了另一种餐食，请另建选项。',
            isRestaurant ? '是同一家，保存' : '是同一种，保存',
          )) {
            sameFood = true;
            continue;
          }
        } else if (result.status == OptionMutationStatus.duplicate) {
          if (await resolveDuplicate(result.option!) && mounted) {
            setState(() => leaving = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.pop(context, true);
            });
            return;
          }
        } else {
          setState(() => error = result.message);
        }
        break;
      }
    } catch (_) {
      if (mounted) setState(() => error = '暂时无法保存，请检查图片后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = original?.isBuiltIn ?? false;
    final preview = selectedImage ?? original?.imagePath;
    return PopScope(
      canPop: leaving || (!dirty && !busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            original == null
                ? isRestaurant
                      ? '添加喜欢的餐厅'
                      : '添一道喜欢的'
                : isRestaurant
                ? '编辑餐厅'
                : '编辑选项',
          ),
          leading: IconButton(
            tooltip: '返回',
            onPressed: busy ? null : close,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        key: const Key('option-name'),
                        controller: name,
                        enabled: !busy,
                        maxLength: 120,
                        decoration: InputDecoration(
                          labelText: isRestaurant ? '餐厅名称' : '名称',
                          hintText: isRestaurant ? '例如：街角小馆' : '例如：番茄鸡蛋面',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请填写名称。'
                            : null,
                      ),
                      if (isRestaurant) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('option-address'),
                          controller: address,
                          enabled: !busy,
                          maxLength: 300,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: '地址（选填）',
                            hintText: '填写附近门店或具体地址',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('option-notes'),
                          controller: notes,
                          enabled: !busy,
                          maxLength: 500,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: '备注（选填）',
                            hintText: '例如：想点的菜、营业时间',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text('图片（选填）'),
                      const SizedBox(height: 12),
                      if (preview != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(preview),
                            width: 144,
                            height: 144,
                            fit: BoxFit.cover,
                            cacheWidth: 432,
                            errorBuilder: (_, _, _) => const SizedBox(
                              height: 100,
                              child: Center(child: Text('图片无法显示，请重新选择')),
                            ),
                          ),
                        )
                      else
                        OptionArt(
                          option:
                              original ??
                              FoodOption(
                                id: '',
                                name: '',
                                art: isRestaurant ? 'storefront' : 'plate',
                                scenario: scenario.name,
                                periods: periods,
                              ),
                          size: 100,
                        ),
                      OutlinedButton.icon(
                        key: const Key('pick-option-image'),
                        onPressed: busy ? null : chooseImage,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(preview == null ? '选择图片' : '更换图片'),
                      ),
                      const Text('未选图片时使用系统插画。'),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        key: const Key('option-category'),
                        initialValue: category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '分类',
                          border: OutlineInputBorder(),
                        ),
                        items: {category, ...scenarioCategories[scenario]!}
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: busy || locked
                            ? null
                            : (value) => setState(() => category = value!),
                      ),
                      if (locked && original!.categories.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '所属分类：${original!.categories.join(' · ')}',
                            key: const Key('option-category-memberships'),
                            style: const TextStyle(height: 1.5),
                          ),
                        ),
                      const SizedBox(height: 24),
                      const Text(
                        '适用餐段（至少一项）',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: MealPeriod.values
                            .map(
                              (period) => FilterChip(
                                label: Text(period.label),
                                selected: periods.contains(period),
                                onSelected: busy || (locked && !isRestaurant)
                                    ? null
                                    : (selected) => setState(() {
                                        if (selected) {
                                          periods.add(period);
                                        } else {
                                          periods.remove(period);
                                        }
                                      }),
                              ),
                            )
                            .toList(),
                      ),
                      if (locked)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            isRestaurant
                                ? '内置餐厅的分类由系统维护，餐段可按门店情况调整。'
                                : '内置餐食的分类与餐段由系统维护。',
                          ),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 32),
                      FilledButton(
                        key: const Key('save-option'),
                        onPressed: busy ? null : save,
                        child: Text(busy ? '正在保存…' : '保存选项'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
