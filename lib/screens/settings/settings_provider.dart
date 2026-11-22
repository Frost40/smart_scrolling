import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/explore_repository.dart';
import '../../data/repositories/sharing_repository.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/topic.dart';
import '../../domain/topic_groups.dart' as topic_groups;

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._state, this._repo, [this._sharing]) {
    _state.addListener(_notify);
    load();
  }
  final AppStateRepository _state;
  final ExploreRepository _repo;
  final SharingRepository? _sharing;
  int? get weeklyGoal => _state.profile?['weekly_goal_days'] as int?;
  String? get reminder => _state.device?['reminder_time'] as String?;
  String? dataError;
  bool dataBusy = false;

  Future<void> setWeeklyGoal(int? value) =>
      _save(() => _state.setWeeklyGoal(value));
  Future<void> setReminder(String? time) =>
      _dataAction(() => _state.setReminder(time));
  Future<void> exportData(Rect origin) => _dataAction(() async {
    await _sharing!.export(await _state.exportData(), origin);
  });
  Future<void> deleteActivity() => _dataAction(_state.deleteActivity);

  Future<void> _dataAction(Future<void> Function() action) async {
    if (dataBusy) return;
    dataBusy = true;
    dataError = null;
    _notify();
    try {
      await action();
    } catch (e) {
      dataError = e is StateError ? e.message.toString() : 'That did not finish. Check your connection and phone permissions, then retry.';
    }
    dataBusy = false;
    _notify();
  }

  AppSettings get s => _state.s;
  String get level => _state.profile?['preferred_level'] as String? ?? 'any';
  List<Topic> topics = [];
  Map<String, String> choices = {};
  bool loading = true, busy = false, _disposed = false;
  String? error;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      topics = await _repo.topicTree();
      choices = await _repo.topicChoices();
    } catch (_) {
      error = 'Preferences could not load. Check your connection, then retry.';
    }
    loading = false;
    _notify();
  }

  /// Topics you follow. Topics are a follow on/off choice (D46).
  Set<String> get followed => {
    for (final e in choices.entries)
      if (e.value == 'follow') e.key,
  };

  Future<void> toggleTopic(String id) => _save(() async {
    final before = followed,
        after = topic_groups.toggleTopic(topics, before, id);
    for (final t in after.difference(before)) {
      await _repo.followTopic(t);
      choices = {...choices, t: 'follow'};
    }
    for (final t in before.difference(after)) {
      await _repo.forgetTopic(t);
      choices = {...choices}..remove(t);
    }
  });
  Future<void> setLevel(String value) =>
      _save(() => _state.setPreferredLevel(value == 'any' ? null : value));
  Future<void> _save(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
      _state.personalizationChanged();
    } catch (_) {
      error = 'That did not save. Check your connection, then retry.';
    }
    busy = false;
    _notify();
  }

  void setReducedMotion(bool on) => _state.change(() => s.reducedMotion = on);
  void setHighContrast(bool on) => _state.change(() => s.highContrast = on);
  void setTextScale(double scale) => _state.change(() => s.textScale = scale);
  void setOfflineMode(String mode) => _state.change(() => s.offlineMode = mode);
  void setMobileData(bool on) => _state.change(() => s.mobileData = on);
  @override
  void dispose() {
    _disposed = true;
    _state.removeListener(_notify);
    super.dispose();
  }
}
