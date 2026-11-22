import 'package:flutter/foundation.dart';

import '../../data/repositories/explore_repository.dart';
import '../../domain/models/topic.dart';
import '../../domain/topic_groups.dart';

/// First start: interests in a few steps (D46). Continue needs one choice;
/// Skip saves none.
class OnboardingProvider extends ChangeNotifier {
  OnboardingProvider(this._repo, this._finish) {
    load();
  }
  final ExploreRepository _repo;
  final VoidCallback _finish;
  List<Topic> topics = [];
  List<TopicStep> steps = [];
  int step = 0;
  final Set<String> selected = {};
  bool loading = true, saving = false, _disposed = false;
  String? error;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get isLast => step >= steps.length - 1;
  bool get canContinue => selected.isNotEmpty && !saving && !loading;

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      topics = await _repo.topicTree();
      steps = stepsFor(topics);
    } catch (_) {
      error = 'Topics could not load. Check your connection, then retry.';
    }
    loading = false;
    _notify();
  }

  void toggle(String id) {
    final next = toggleTopic(topics, selected, id);
    selected
      ..clear()
      ..addAll(next);
    _notify();
  }

  void next() {
    if (!isLast) step++;
    _notify();
  }

  void back() {
    if (step > 0) step--;
    _notify();
  }

  /// Follows every chosen topic, then opens the app.
  Future<void> finish() async {
    if (!canContinue) return;
    saving = true;
    error = null;
    _notify();
    try {
      for (final id in selected) {
        await _repo.followTopic(id);
      }
      if (!_disposed) _finish();
    } catch (_) {
      error = 'Your topics could not save. Check your connection, then retry.';
    }
    saving = false;
    _notify();
  }

  /// Forgets every choice made so far and opens the app.
  void skip() {
    if (saving) return;
    selected.clear();
    _finish();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
