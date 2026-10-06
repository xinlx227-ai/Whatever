import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/meal_repository.dart';
import '../domain/meal.dart';

class MealController extends ChangeNotifier {
  MealController({
    required MealRepository repository,
    DateTime Function()? clock,
    Random? random,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random(),
       _period = MealPeriod.at((clock ?? DateTime.now)());

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

  MealPeriod get period => _period;
  List<FoodOption> get options => _options;
  List<FoodOption> get candidates => List.unmodifiable(
    _options.where((option) => option.periods.contains(_period)),
  );
  FoodOption? get result => _result;
  int? get selectedIndex => _selectedIndex;
  bool get isDrawing => _isDrawing;
  bool get isSaving => _isSaving;
  bool get hasRound => _chosen != null;
  String? get error => _error;
  List<HistoryEntry> get history => _history;

  Future<void> initialize() async {
    try {
      _options = await _repository.options();
      _history = await _repository.history();
      _error = null;
    } catch (_) {
      _error = '本地数据暂时无法读取，请重新打开应用。';
      _notify();
      rethrow;
    }
    _notify();
  }

  bool startDraw() {
    if (_isSaving || hasRound) return false;
    final pool = candidates;
    if (pool.isEmpty) {
      _error = '这个时段暂无可选餐食，请换个时段。';
      _notify();
      return false;
    }
    _selectedIndex = _random.nextInt(pool.length);
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
    if (_isSaving || _isDrawing || _result == null) return false;
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
      _notify();
    }
  }

  bool changePeriod(MealPeriod period) {
    if (_isSaving) return false;
    if (_period == period) return true;
    _clearRound();
    _period = period;
    _error = null;
    _notify();
    return true;
  }

  bool abandon() {
    if (_isSaving) return false;
    _clearRound();
    _error = null;
    _notify();
    return true;
  }

  void _clearRound() {
    _chosen = null;
    _result = null;
    _selectedIndex = null;
    _operation = null;
    _isDrawing = false;
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
