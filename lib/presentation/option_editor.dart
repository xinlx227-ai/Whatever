import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../application/meal_controller.dart';
import '../data/option_images.dart';
import '../domain/meal.dart';
import '../domain/local_recognition.dart';
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
  late String categoryId;
  late final String initialCategoryId;
  String? selectedImage;
  String? ownedImage;
  final Set<String> imageCleanupCandidates = {};
  late final OptionImages images;
  String? error;
  bool busy = false;
  bool leaving = false;
  bool asking = false;
  bool manualCategory = false;
  FoodOption? get original => widget.option;
  MealScenario get scenario => original == null
      ? widget.scenario
      : MealScenario.fromKey(original!.scenario);
  bool get isRestaurant => scenario == MealScenario.restaurant;
  List<MealCategory> get categories =>
      widget.controller.categoriesFor(scenario);
  MealCategory get selectedCategory => categories.firstWhere(
    (value) => value.id == categoryId,
    orElse: () => widget.controller.fallbackCategory(scenario),
  );
  String get category => selectedCategory.name;
  FoodOption? get currentOption => original == null
      ? null
      : widget.controller.options.firstWhere(
          (value) => value.id == original!.id,
          orElse: () => original!,
        );
  bool get dirty =>
      name.text != (original?.name ?? '') ||
      address.text != (original?.address ?? '') ||
      notes.text != (original?.notes ?? '') ||
      selectedImage != null ||
      categoryId != initialCategoryId ||
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
    categoryId = categories
        .firstWhere(
          (value) => value.name == original?.category,
          orElse: () => widget.controller.fallbackCategory(scenario),
        )
        .id;
    initialCategoryId = categoryId;
    manualCategory = original != null;
    selectedImage = widget.initialImagePath;
    name.addListener(nameChanged);
    address.addListener(refresh);
    notes.addListener(refresh);
    widget.controller.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void nameChanged() {
    if (!manualCategory) {
      categoryId = const LocalRecognition().inferCategoryId(
        name.text,
        scenario,
        categories,
      );
    }
    refresh();
  }

  @override
  void dispose() {
    widget.controller.removeListener(refresh);
    unawaited(
      images.discardUnreferenced(
        imageCleanupCandidates,
        widget.controller.imagePathsInUse,
      ),
    );
    name.removeListener(nameChanged);
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
          scrollable: true,
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

  Future<void> viewOption(FoodOption option) async {
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
  }

  Future<FoodOption?> chooseMatch(
    List<FoodOption> matches, {
    required String title,
  }) async {
    if (matches.length == 1) return matches.single;
    return showDialog<FoodOption>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (index, option) in matches.indexed)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${index + 1}. ${option.name}\n'
                  '${option.category} · ${option.isDeleted
                      ? '已删除'
                      : option.isActive
                      ? '已启用'
                      : '已停用'}'
                  '${option.address == null ? '' : '\n${option.address}'}',
                ),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<bool> resolveUncertain(List<FoodOption> matches) async {
    while (mounted) {
      if (!mounted) return false;
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('可能已有相似选项'),
          content: Text(
            '“${matches.map((option) => option.name).join('”、“')}”与输入名称相似，'
            '但无法确定是否相同。请查看已有资料，或确认仍然${original == null ? '添加' : '保存'}。',
          ),
          scrollable: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'view'),
              child: const Text('查看已有选项'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'proceed'),
              child: Text(original == null ? '仍然添加' : '仍然保存'),
            ),
          ],
        ),
      );
      if (!mounted || action == null) return false;
      if (action == 'proceed') return true;
      final selected = await chooseMatch(matches, title: '选择要查看的选项');
      if (!mounted) return false;
      if (selected != null) await viewOption(selected);
    }
    return false;
  }

  Future<bool> resolveDuplicate(FoodOption option, String? message) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isRestaurant ? '已有相同餐厅' : '已有相同餐食'),
        scrollable: true,
        content: Text(
          '“${option.name}”${option.isDeleted
              ? '曾被删除'
              : option.isActive
              ? '已在选项库中'
              : '目前已停用'}，不会创建重复选项。'
          '${!option.isActive && !option.isDeleted ? '重新启用会保留原有资料，本次表单内容不会保存。' : ''}'
          '${message == null ? '' : '\n$message'}',
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
      await viewOption(option);
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
      var allowUncertain = false;
      String? restoreOptionId;
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
          allowUncertainDuplicate: allowUncertain,
          restoreOptionId: restoreOptionId,
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
          final target = await chooseMatch(result.matches, title: '选择要恢复的原选项');
          if (!mounted || target == null) break;
          if (await ask(
            '恢复原来的选项？',
            '“${target.name}”曾被删除。恢复会沿用原来的身份，与已有足迹保持关联。'
                '本次表单的名称、分类和餐段会覆盖原有设置；未选择新图片时保留原图。'
                '${isRestaurant ? '地址和备注也会按表单保存，留空会清除原内容。${result.message ?? ''}' : ''}',
            '恢复并保存',
          )) {
            restore = true;
            restoreOptionId = target.id;
            if (target.imagePath != null) {
              imageCleanupCandidates.add(target.imagePath!);
            }
            continue;
          }
        } else if (result.status == OptionMutationStatus.uncertainDuplicate) {
          if (await resolveUncertain(result.matches)) {
            allowUncertain = true;
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
          final target = await chooseMatch(
            result.matches,
            title: '已有多个相同选项，请选择查看',
          );
          if (!mounted || target == null) break;
          if (await resolveDuplicate(target, result.message) && mounted) {
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
                      KeyedSubtree(
                        key: ValueKey(selectedCategory.id),
                        child: DropdownButtonFormField<String>(
                          key: const Key('option-category'),
                          initialValue: selectedCategory.id,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: '分类',
                            helperText: locked
                                ? null
                                : manualCategory
                                ? '已保留你的分类选择'
                                : selectedCategory.isFallback
                                ? '暂无法确定分类，可手动选择'
                                : '已根据名称分类，可手动修改',
                            border: const OutlineInputBorder(),
                          ),
                          items: categories
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value.id,
                                  child: Text(value.name),
                                ),
                              )
                              .toList(),
                          onChanged: busy || locked
                              ? null
                              : (value) => setState(() {
                                  manualCategory = true;
                                  categoryId = value!;
                                }),
                        ),
                      ),
                      if (locked && currentOption!.categories.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '所属分类：${currentOption!.categories.join(' · ')}',
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
