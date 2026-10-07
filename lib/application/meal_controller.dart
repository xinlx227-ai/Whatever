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
  List<FoodOption> _options = const [];
  List<HistoryEntry> _history = const [];
  FoodOption? _chosen;
  FoodOption? _result;
  int? _selectedIndex;
  ConfirmationOperation? _operation;
  bool _isDrawing = false;
  bool _isSaving = false;
  bool _disposed = false;
  String? _error;
  MealPreferences _preferences = const MealPreferences();
  final Set<String> _sessionExclusions = {};
  List<FoodOption>? _roundCandidates;
  bool _isUpdatingPreferences = false;
  int _pendingDataChanges = 0;
  Future<void> _dataChanges = Future.value();
  Future<void> _libraryChanges = Future.value();
  int _pendingLibraryChanges = 0;
  Completer<void>? _confirmationFinished;
  String? _restartNotice;
  bool _dataUnavailable = false;

  MealPeriod get period => _period;
  MealPeriod get currentLocalPeriod => MealPeriod.at(_clock().toLocal());
  List<FoodOption> get options => _options;
  List<FoodOption> get candidates => _roundCandidates ?? _eligibleCandidates();
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
    final now = _clock().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final yesterdayIds = _preferences.excludeYesterday
        ? _history
              .where((entry) {
                final time = entry.confirmedAt.toLocal();
                return !time.isBefore(yesterday) && time.isBefore(today);
              })
              .map((entry) => entry.option.id)
              .toSet()
        : const <String>{};
    return List.unmodifiable(
      _options.where(
        (option) =>
            option.scenario == 'eat' &&
            option.isActive &&
            !option.isDeleted &&
            option.periods.contains(_period) &&
            !_sessionExclusions.contains(option.id) &&
            !yesterdayIds.contains(option.id),
      ),
    );
  }

  FoodOption? get result => _result;
  int? get selectedIndex => _selectedIndex;
  bool get isDrawing => _isDrawing;
  bool get isSaving => _isSaving;
  bool get hasRound => _chosen != null;
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
    String category = '未分类',
    String scenario = 'eat',
    String? imagePath,
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
        confirmRestore: confirmRestore,
        confirmSameFood: confirmSameFood,
      ),
    );
  }

  Future<OptionMutationResult> setOptionActive(String id, bool active) =>
      _mutateLibrary(() => _repository.setOptionActive(id, active));

  Future<OptionMutationResult> deleteOption(String id) =>
      _mutateLibrary(() => _repository.deleteOption(id));

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
    if (isBusy || hasRound) return false;
    if (_dataUnavailable) return false;
    final pool = candidates;
    if (pool.isEmpty) {
      _error = '这个时段暂无可选餐食，请换个时段。';
      _notify();
      return false;
    }
    _selectedIndex = _random.nextInt(pool.length);
    _roundCandidates = pool;
    _chosen = pool[_selectedIndex!];
    _result = null;
    _isDrawing = true;
    _error = null;
    _notify();
    return true;
  }

  void finishDraw() {
    if (!_isDrawing) return;
    _isDrawing = false;
    _result = _chosen;
    _notify();
  }

  Future<bool> confirm() async {
    if (isBusy || _isDrawing || _result == null) return false;
    _operation ??= ConfirmationOperation(
      operationId: List.generate(
        16,
        (_) => _operationRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      confirmedAt: _clock(),
      period: _period,
      option: _result!,
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

  bool abandon() {
    if (isBusy) return false;
    _clearRound();
    _error = null;
    _notify();
    return true;
  }

  void _clearRound() {
    _roundCandidates = null;
    _chosen = null;
    _result = null;
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
        _options = await _repository.options();
        _history = await _repository.history();
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
