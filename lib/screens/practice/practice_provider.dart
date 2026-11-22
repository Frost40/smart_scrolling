import 'package:flutter/foundation.dart';

import '../../data/repositories/practice_repository.dart';
import '../../domain/models/practice_card.dart';
import '../../domain/practice_checker.dart';

class PracticeProvider extends ChangeNotifier {
  PracticeProvider(
    this._repo, {
    required String filter,
    required this.saveFilter,
    required bool Function() isOpen,
    required Listenable tabChanges,
  }) : filter = practiceFilters.contains(filter) ? filter : 'mix',
       _isOpen = isOpen,
       _tabChanges = tabChanges {
    _wasOpen = isOpen();
    tabChanges.addListener(_tabChanged);
    refresh();
  }

  final PracticeRepository _repo;
  final Future<void> Function(String) saveFilter;
  final bool Function() _isOpen;
  final Listenable _tabChanges;
  List<PracticeEntry> entries = [];
  String filter;
  int dueCount = 0, waitingCount = 0;
  bool loading = false, loaded = false, hasMore = false, early = false;
  String? error;
  bool _disposed = false, _wasOpen = false, _filterSaving = false;
  bool _retryReset = true;
  int _generation = 0;

  bool get pending =>
      entries.any((e) => e.answer != null && !e.saved && !e.unavailable);

  Future<void> reloadCard(PracticeEntry entry) async {
    try {
      entry.card = await _repo.card(entry.card.id);
      _notify();
    } catch (_) {
      /* Keep the attempt if the connection was lost. */
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _tabChanged() {
    final open = _isOpen();
    if (open && !_wasOpen && !pending) refresh();
    _wasOpen = open;
  }

  Future<void> refresh() async {
    if (pending) {
      error = 'Retry the unsaved answer before refreshing.';
      _notify();
      return;
    }
    early = false;
    await _load(reset: true);
  }

  Future<void> loadMore() async {
    if (loading || pending || !hasMore || error != null) return;
    await _load(reset: false);
  }

  Future<void> retryLoad() async {
    error = null;
    await _load(reset: _retryReset);
  }

  Future<void> practiceNow() async {
    if (!loaded || loading || dueCount != 0 || pending) return;
    early = true;
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    _retryReset = reset;
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      final exclude = reset ? <String>[] : entries.map((e) => e.card.id);
      final batch = await (early
          ? _repo.practiceNow(filter: filter, exclude: exclude)
          : _repo.due(filter: filter, exclude: exclude));
      if (_disposed || generation != _generation) return;
      entries = [if (!reset) ...entries, ...batch.entries];
      dueCount = batch.due;
      waitingCount = batch.waiting;
      hasMore = batch.hasMore;
      loaded = true;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = 'Practice could not load. Check your connection, then try again.';
    }
    loading = false;
    _notify();
  }

  Future<void> setFilter(String value) async {
    if (!practiceFilters.contains(value) || value == filter || _filterSaving) {
      return;
    }
    if (pending) {
      error = 'Retry the unsaved answer before changing the filter.';
      _notify();
      return;
    }
    _filterSaving = true;
    try {
      await saveFilter(value);
      if (_disposed) return;
      filter = value;
      await refresh();
    } catch (_) {
      error = 'The filter could not save. Check your connection.';
      _notify();
    } finally {
      _filterSaving = false;
    }
  }

  void reveal(PracticeEntry e) {
    if (e.answer != null) return;
    e.revealed = true;
    _notify();
  }

  void choose(PracticeEntry e, int choice) {
    final count = e.test.type == 'true_false' ? 2 : e.test.choices.length;
    if (e.answer != null || choice < 0 || choice >= count) {
      return;
    }
    e.choice = choice;
    _notify();
  }

  void move(PracticeEntry e, int from, int to) {
    if (e.answer != null ||
        e.test.type != 'ordering' ||
        from < 0 ||
        from >= e.order.length ||
        to < 0 ||
        to >= e.order.length) {
      return;
    }
    e.order.insert(to, e.order.removeAt(from));
    _notify();
  }

  void selectLeft(PracticeEntry e, int left) {
    if (e.answer != null || left < 0 || left >= e.matches.length) return;
    e.selectedLeft = left;
    _notify();
  }

  void pair(PracticeEntry e, int right) {
    if (e.answer != null ||
        e.selectedLeft == null ||
        right < 0 ||
        right >= e.test.matchRight.length) {
      return;
    }
    final previous = e.matches.indexOf(right);
    if (previous != -1) e.matches[previous] = null;
    e.matches[e.selectedLeft!] = right;
    e.selectedLeft = null;
    _notify();
  }

  Future<void> answer(PracticeEntry e, [String? rating]) async {
    if (e.answer != null || loading || _filterSaving) return;
    String result;
    Object? value;
    if (e.test.type == 'flashcard') {
      if (!e.revealed ||
          !const ['again', 'hard', 'good', 'easy'].contains(rating)) {
        return;
      }
      result = rating!;
      value = rating;
    } else {
      switch (e.test.type) {
        case 'multiple_choice':
        case 'true_false':
          if (e.choice == null) return;
          value = e.test.type == 'true_false' ? e.choice == 0 : e.choice;
        case 'ordering':
          value = List<String>.unmodifiable(
            e.order.map((i) => e.test.correctOrder[i]),
          );
        case 'matching':
          if (e.matches.contains(null)) return;
          value = List<String>.unmodifiable(
            e.matches.map((i) => e.test.matchRight[i!]),
          );
        default:
          return;
      }
      result = checkPracticeAnswer(e.test, value) ? 'correct' : 'wrong';
    }
    e.answer = _repo.newAnswer(e, result, value);
    await retry(e);
  }

  Future<void> retry(PracticeEntry e) async {
    if (e.answer == null || e.saving || e.saved || e.unavailable) return;
    e.saving = true;
    e.error = null;
    _notify();
    try {
      await _repo.recordAnswer(e.answer!);
      e.saved = true;
      if (!early) dueCount = (dueCount - 1).clamp(0, dueCount);
      error = null;
    } on PracticeUnavailable {
      e.unavailable = true;
      e.error = 'This card or test is no longer available. Refresh Practice to continue.';
      error = null;
    } catch (_) {
      e.error = 'Answer not saved. Check your connection and retry.';
    }
    e.saving = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _tabChanges.removeListener(_tabChanged);
    super.dispose();
  }
}
