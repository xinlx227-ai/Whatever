import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/meal_repository.dart';
import '../domain/meal.dart';
import '../domain/meal_preferences.dart';

class MealController extends ChangeNotifier {
  MealController({
    required MealRepository repository,
    DateTime Function()? clock,
    Random? random,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random(),
       _period = MealPeriod.at((clock ?? DateTime.now)().toLocal());

  final MealRepository _repository;
  final DateTime Function() _clock;
  final Random _random;
  final Random _operationRandom = Random.secure();
  MealPeriod _period;
  MealScenario _scenario = MealScenario.eat;
  List<FoodOption> _options = const [];
  List<MealCategory> _categories = const [];
  Set<String> _selectedCategoryIds = {};
  List<HistoryEntry> _history = const [];
  FoodOption? _chosen;
  FoodOption? _result;
  List<FoodOption> _results = const [];
  int _cookingCount = 1;
  int? _selectedIndex;
  ConfirmationOperation? _operation;
  bool _isDrawing = false;
  bool _isSaving = false;
  bool _disposed = false;
  String? _error;
  MealPreferences _preferences = const MealPreferences();
  final Set<String> _sessionExclusions = {};
  List<FoodOption>? _roundCandidates;
  List<FoodOption>? _roundScope;
  bool _isUpdatingPreferences = false;
  int _pendingDataChanges = 0;
  Future<void> _dataChanges = Future.value();
  Future<void> _libraryChanges = Future.value();
  int _pendingLibraryChanges = 0;
  Completer<void>? _confirmationFinished;
  String? _restartNotice;
  bool _dataUnavailable = false;

  MealPeriod get period => _period;
  MealScenario get scenario => _scenario;
  MealPeriod get currentLocalPeriod => MealPeriod.at(_clock().toLocal());
  List<FoodOption> get options => _options;
  List<MealCategory> categoriesFor(MealScenario scenario) => List.unmodifiable(
    _categories.where((category) => category.scenario == scenario),
  );
  MealCategory fallbackCategory(MealScenario scenario) =>
      _categories.firstWhere(
        (category) => category.scenario == scenario && category.isFallback,
      );
  Set<String> get selectedCategoryIds => Set.unmodifiable(_selectedCategoryIds);
  List<FoodOption> get candidates => _roundCandidates ?? _eligibleCandidates();
  int get cookingCount => _cookingCount;
  int get requestedCount => _scenario == MealScenario.cook ? _cookingCount : 1;
  List<FoodOption> get results => _results;
  int get availableCount => _remainingCandidates().length;
  bool get hasCandidateShortage =>
      !hasRound && availableCount > 0 && availableCount < requestedCount;
  bool get canDraw =>
      !isBusy &&
      !_dataUnavailable &&
      !_isDrawing &&
      _operation == null &&
      _results.length < requestedCount &&
      (hasRound ? availableCount > 0 : availableCount >= requestedCount);
  MealPreferences get preferences => _preferences;
  Set<String> get sessionExclusions => Set.unmodifiable(_sessionExclusions);
  bool get isModeLocked => hasRound;
  bool get isBusy =>
      _isSaving ||
      _isUpdatingPreferences ||
      _pendingDataChanges > 0 ||
      _pendingLibraryChanges > 0;
  String? get restartNotice => _restartNotice;

  List<FoodOption> _eligibleCandidates() {
    if (_dataUnavailable) return const [];
    final selectedNames = _categories
        .where((category) => _selectedCategoryIds.contains(category.id))
        .map((category) => category.name)
        .toSet();
    final now = _clock().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final yesterdayIds = _preferences.excludeYesterday
        ? _history
              .where((entry) {
                final time = entry.confirmedAt.toLocal();
                return !time.isBefore(yesterday) && time.isBefore(today);
              })
              .expand((entry) => entry.options.map((option) => option.id))
              .toSet()
        : const <String>{};
    return List.unmodifiable(
      _options.where(
        (option) =>
            option.scenario == _scenario.name &&
            option.isActive &&
            !option.isDeleted &&
            option.periods.contains(_period) &&
            (_selectedCategoryIds.isEmpty ||
                option.categories.any(selectedNames.contains)) &&
            !_sessionExclusions.contains(option.id) &&
            !yesterdayIds.contains(option.id),
      ),
    );
  }

  List<FoodOption> _remainingCandidates() {
    final scope = _roundScope;
    if (scope == null) return _eligibleCandidates();
    final selectedIds = _results.map((option) => option.id).toSet();
    return List.unmodifiable(
      scope.where((option) => !selectedIds.contains(option.id)),
    );
  }

  FoodOption? get result => _result;
  int? get selectedIndex => _selectedIndex;
  bool get isDrawing => _isDrawing;
  bool get isSaving => _isSaving;
  bool get hasRound => _roundScope != null;
  String? get error => _dataUnavailable ? '更新后的本地数据暂时无法读取，请重新打开应用。' : _error;
  List<HistoryEntry> get history => _history;

  // Include retained deleted options; cleanup must never rely on a filtered UI.
  Future<Set<String>> imagePathsInUse() async => {
    for (final option in await _repository.options())
      if (option.imagePath != null) option.imagePath!,
  };

  List<FoodOption> libraryOptions({
    String scenario = 'eat',
    String query = '',
    LibraryStatus status = LibraryStatus.active,
  }) {
    final search = normalizedOptionName(query);
    return List.unmodifiable(
      _options.where(
        (option) =>
            option.scenario == scenario &&
            !option.isDeleted &&
            (status == LibraryStatus.all ||
                option.isActive == (status == LibraryStatus.active)) &&
            normalizedOptionName(option.name).contains(search),
      ),
    );
  }

  Future<OptionMutationResult> saveOption({
    String? id,
    required String name,
    required Set<MealPeriod> periods,
    String? category,
    String scenario = 'eat',
    String? imagePath,
    String? address,
    String? notes,
    bool confirmRestore = false,
    bool confirmSameFood = false,
  }) {
    // Snapshot mutable form input before entering the serialized write queue.
    final selectedPeriods = Set<MealPeriod>.of(periods);
    return _mutateLibrary(
      () => _repository.saveOption(
        id: id,
        name: name,
        periods: selectedPeriods,
        category: category,
        scenario: scenario,
        imagePath: imagePath,
        address: address,
        notes: notes,
        confirmRestore: confirmRestore,
        confirmSameFood: confirmSameFood,
      ),
    );
  }

  Future<OptionMutationResult> setOptionActive(String id, bool active) =>
      _mutateLibrary(() => _repository.setOptionActive(id, active));

  Future<OptionMutationResult> deleteOption(String id) =>
      _mutateLibrary(() => _repository.deleteOption(id));

  Future<OptionMutationResult> saveCategory({
    String? id,
    required String name,
    MealScenario scenario = MealScenario.eat,
  }) => _mutateLibrary(
    () => _repository.saveCategory(id: id, name: name, scenario: scenario),
  );

  Future<OptionMutationResult> deleteCategory(String id) =>
      _mutateLibrary(() => _repository.deleteCategory(id));

  Future<OptionMutationResult> _mutateLibrary(
    Future<OptionMutationResult> Function() mutation,
  ) {
    final result = Completer<OptionMutationResult>();
    _pendingLibraryChanges++;
    _notify();
    _libraryChanges = _libraryChanges.then((_) async {
      try {
        // Reserve the action boundary before waiting: a confirmation cannot start
        // between the durable write and the invalidation of its old draw pool.
        await _confirmationFinished?.future;
        await _dataChanges;
        final outcome = await mutation();
        if (outcome.changed) await applyDataChange(changed: true);
        result.complete(outcome);
      } catch (_) {
        result.complete(
          const OptionMutationResult(
            OptionMutationStatus.failed,
            message: '选项暂时无法保存，请重试。',
          ),
        );
      } finally {
        _pendingLibraryChanges--;
        _notify();
      }
    });
    return result.future;
  }

  Future<void> initialize() async {
    try {
      _options = await _repository.options();
      _categories = await _repository.categories();
      _history = await _repository.history();
      _preferences = await _repository.preferences();
      _dataUnavailable = false;
      _error = null;
    } catch (_) {
      _error = '本地数据暂时无法读取，请重新打开应用。';
      _notify();
      rethrow;
    }
    _notify();
  }

  bool startDraw() {
    if (isBusy ||
        _isDrawing ||
        _operation != null ||
        _results.length >= requestedCount) {
      return false;
    }
    if (_dataUnavailable) return false;
    final pool = _remainingCandidates();
    if (pool.isEmpty) {
      _error = '没有符合条件的选项，请调整条件或恢复本次排除。';
      _notify();
      return false;
    }
    if (!hasRound && pool.length < requestedCount) {
      _error = '当前只有 ${pool.length} 道符合条件的菜，请减少数量或调整条件。';
      _notify();
      return false;
    }
    // Freeze eligibility once for the whole batch, including the local date.
    _roundScope ??= pool;
    _selectedIndex = _random.nextInt(pool.length);
    // Keep this spin's ordered pool until the next draw so its index stays valid.
    _roundCandidates = pool;
    _chosen = pool[_selectedIndex!];
    _isDrawing = true;
    _error = null;
    _notify();
    return true;
  }

  void finishDraw() {
    if (!_isDrawing) return;
    _isDrawing = false;
    _result = _chosen;
    _results = List.unmodifiable([..._results, _chosen!]);
    _notify();
  }

  Future<bool> confirm() async {
    if (isBusy || _isDrawing || _results.isEmpty) return false;
    _operation ??= ConfirmationOperation(
      operationId: List.generate(
        16,
        (_) => _operationRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      confirmedAt: _clock(),
      period: _period,
      options: _results,
    );
    _isSaving = true;
    _confirmationFinished = Completer<void>();
    _error = null;
    _notify();
    try {
      await _repository.confirm(_operation!);
      _history = await _repository.history();
      _clearRound();
      return true;
    } catch (_) {
      _error = '暂时无法确认保存结果，请重试，不会重复记录。';
      try {
        _history = await _repository.history();
      } catch (_) {
        // Keep the last readable history snapshot if reconciliation also fails.
      }
      return false;
    } finally {
      _isSaving = false;
      _confirmationFinished!.complete();
      _confirmationFinished = null;
      _notify();
    }
  }

  bool changePeriod(MealPeriod period) {
    if (isBusy) return false;
    if (_period == period) return true;
    _clearRound();
    _period = period;
    _error = null;
    _notify();
    return true;
  }

  // Presentation obtains restart consent before applying a changed count.
  bool changeCookingCount(int count) {
    if (isBusy || _scenario != MealScenario.cook || count < 1 || count > 10) {
      return false;
    }
    if (_cookingCount == count) return true;
    _clearRound();
    _cookingCount = count;
    _error = null;
    _notify();
    return true;
  }

  // Presentation obtains restart consent before changing a started round.
  bool changeScenario(MealScenario scenario) {
    if (isBusy) return false;
    if (_scenario == scenario) return true;
    _clearRound();
    _scenario = scenario;
    _selectedCategoryIds = {};
    _error = null;
    _notify();
    return true;
  }

  bool abandon() {
    if (isBusy) return false;
    _clearRound();
    _error = null;
    _notify();
    return true;
  }

  // Presentation applies the staged filters only after restart consent.
  bool changeCategoryFilters(Set<String> ids, {MealPeriod? period}) {
    if (isBusy) return false;
    final validIds = categoriesFor(
      _scenario,
    ).map((category) => category.id).toSet();
    if (!validIds.containsAll(ids)) return false;
    final nextPeriod = period ?? _period;
    if (setEquals(ids, _selectedCategoryIds) && nextPeriod == _period) {
      return true;
    }
    _clearRound();
    _selectedCategoryIds = Set.of(ids);
    _period = nextPeriod;
    _error = null;
    _notify();
    return true;
  }

  void _clearRound() {
    _roundCandidates = null;
    _roundScope = null;
    _chosen = null;
    _result = null;
    _results = const [];
    _selectedIndex = null;
    _operation = null;
    _isDrawing = false;
  }

  // Future controls restart a started round explicitly before changing conditions.
  Future<bool> updatePreferences(MealPreferences preferences) async {
    if (isBusy) return false;
    if (preferences.mode == _preferences.mode &&
        preferences.excludeYesterday == _preferences.excludeYesterday) {
      return true;
    }
    if (hasRound) return false;
    _isUpdatingPreferences = true;
    _notify();
    try {
      await _repository.savePreferences(preferences);
      _preferences = preferences;
      _error = null;
      return true;
    } catch (_) {
      _error = '偏好暂时无法保存，请重试。';
      return false;
    } finally {
      _isUpdatingPreferences = false;
      _notify();
    }
  }

  // Between-round session actions; replacement will add its own slot transition.
  bool excludeForSession(String optionId) {
    if (isBusy ||
        hasRound ||
        !_options.any((option) => option.id == optionId)) {
      return false;
    }
    _sessionExclusions.add(optionId);
    _notify();
    return true;
  }

  bool restoreSessionExclusions() {
    if (isBusy || hasRound) return false;
    _sessionExclusions.clear();
    _error = null;
    _notify();
    return true;
  }

  // Call after a committed library mutation or history deletion in any scenario.
  // A canceled edit or a save with no actual changes passes changed: false.
  Future<void> applyDataChange({required bool changed}) {
    if (!changed) return Future.value();
    _pendingDataChanges++;
    _notify();
    _dataChanges = _dataChanges.then((_) async {
      await _confirmationFinished?.future;
      if (hasRound) {
        _clearRound();
        _restartNotice = '选项或足迹已更新，这一轮已重置，请重新选择。';
      }
      try {
        final options = await _repository.options();
        final categories = await _repository.categories();
        final history = await _repository.history();
        final categoryIds = categories.map((category) => category.id).toSet();
        // A deleted selected category follows its retained options to fallback.
        final lostSelection = !_selectedCategoryIds.every(categoryIds.contains);
        _selectedCategoryIds = _selectedCategoryIds.intersection(categoryIds);
        if (lostSelection) {
          _selectedCategoryIds.add(
            categories
                .firstWhere(
                  (category) =>
                      category.scenario == _scenario && category.isFallback,
                )
                .id,
          );
        }
        _options = options;
        _categories = categories;
        _history = history;
        _dataUnavailable = false;
        _error = null;
      } catch (_) {
        _dataUnavailable = true;
        _error = '更新后的本地数据暂时无法读取，请重新打开应用。';
      } finally {
        _pendingDataChanges--;
        _notify();
      }
    });
    return _dataChanges;
  }

  String? takeRestartNotice() {
    final notice = _restartNotice;
    _restartNotice = null;
    return notice;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
