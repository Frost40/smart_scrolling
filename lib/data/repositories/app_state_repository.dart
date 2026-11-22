import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../domain/models/app_settings.dart';
import '../services/local_store.dart';
import '../services/reminder_service.dart';
import 'account_repository.dart';
import 'offline_repository.dart';

/// The whole app state: who is signed in, their profile and phone settings,
/// and navigation settings. Screens reach it through their providers.
class AppStateRepository extends ChangeNotifier with WidgetsBindingObserver {
  AppStateRepository(
    this._store,
    this._account, [
    this._offline,
    this._reminders,
  ]) {
    WidgetsBinding.instance.addObserver(this);
    _authEvents = _account.authChanges.listen((userId) {
      if (userId != _owner) load();
    }, onError: (Object _) {});
  }

  final LocalStore _store;
  final AccountRepository _account;
  final OfflineRepository? _offline;
  final ReminderService? _reminders;
  StreamSubscription<String?>? _authEvents;
  AppSettings s = AppSettings();
  String? installation, _owner;

  /// The signed-in person's rows; null while signed out or loading.
  Map<String, dynamic>? profile, device;
  bool loading = true, _disposed = false;
  bool needsOnboarding = false;
  int feedRevision = 0;

  /// Taps on the tab bar, also on the open tab, so a tab can go back to how it opens.
  int tabTaps = 0;

  /// Continue or Skip: remembered, so Skip is not asked again (D46).
  void finishOnboarding() {
    needsOnboarding = false;
    s.onboarded = true;
    persist();
    personalizationChanged();
  }

  void personalizationChanged() {
    feedRevision++;
    _notify();
  }

  String? loadError, saveError;
  Future<void> saving = Future.value();

  /// Called when this phone's saved theme arrives (`system`, `light` or `dark`).
  void Function(String)? onThemeLoaded;

  bool get signedIn => device != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final owner = _owner = _account.userId;
    loading = true;
    loadError = saveError = null;
    profile = device = null;
    _theme = null;
    s = AppSettings();
    needsOnboarding = false;
    _notify();
    try {
      installation ??= await _store.installationId();
      if (owner != null) {
        s = _snapshot(await _store.loadState(owner));
        await _offline?.use(owner);
        try {
          final rows = await _account.load(installation!);
          final follows = await _account.hasFollows();
          if (owner != _owner) return;
          profile = rows.profile;
          _applyDevice(rows.device);
          needsOnboarding = !follows && !s.onboarded;
          await _store.saveRows(
            owner,
            jsonEncode({'profile': profile, 'device': device}),
          );
        } catch (_) {
          // Offline: open with the rows saved last time, if any.
          final saved = await _store.loadRows(owner);
          if (saved == null || owner != _owner) rethrow;
          final rows = jsonDecode(saved) as Map<String, dynamic>;
          profile = rows['profile'] as Map<String, dynamic>;
          _applyDevice(rows['device'] as Map<String, dynamic>);
          // Choosing topics needs a connection; it waits for the next online start.
          needsOnboarding = false;
        }
      } else {
        await _offline?.use(null);
      }
    } catch (_) {
      if (owner != _owner) return;
      loadError = 'Your settings could not load. Check your connection, then try again.';
    }
    try {
      await _reminders?.restore(device?['reminder_time'] as String?);
    } catch (_) {
      saveError =
          'The reminder could not be restored. Check notification settings.';
    }
    loading = false;
    _notify();
  }

  // Old snapshots contribute only navigation; learning data lives in Supabase.
  AppSettings _snapshot(String? saved) {
    if (saved == null || saved.isEmpty) return AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  void _applyDevice(Map<String, dynamic> row) {
    device = row;
    s
      ..reducedMotion = row['reduce_motion'] == true
      ..highContrast = row['high_contrast'] == true
      ..textScale = (row['text_scale'] as num).toDouble()
      ..offlineMode = row['offline_mode'] as String? ?? 'standard'
      ..mobileData = row['download_on_mobile_data'] == true;
    _offline?.configure(s.offlineMode, s.mobileData);
    onThemeLoaded?.call(row['theme_mode'] as String);
  }

  void change(VoidCallback action) {
    action();
    _offline?.configure(s.offlineMode, s.mobileData);
    _notify();
    persist();
  }

  /// Saves the theme choice to this phone's row.
  void setThemeMode(String mode) {
    if (device == null || device!['theme_mode'] == mode) return;
    _theme = mode;
    persist();
  }

  String? _theme;

  /// What this phone's row should hold now.
  Map<String, dynamic> get _deviceValues => {
    'reduce_motion': s.reducedMotion,
    'high_contrast': s.highContrast,
    'text_scale': s.textScale,
    'offline_mode': s.offlineMode,
    'download_on_mobile_data': s.mobileData,
    'theme_mode': _theme ?? device!['theme_mode'],
  };

  /// Saves the snapshot on the phone and changed settings online, one save at a time.
  void persist() {
    final owner = _owner;
    if (loading || device == null || owner == null) return;
    final value = jsonEncode(s.toJson());
    saving = saving.then((_) async {
      try {
        await _store.saveState(owner, value);
        await _saveDevice(owner);
        saveError = null;
      } on AccountConflict {
        await _reloadDevice(owner);
      } catch (_) {
        if (owner != _owner) return;
        saveError = 'Settings could not be saved online. Check your connection, then retry.';
      }
      _notify();
    });
  }

  Future<void> _saveDevice(String owner) async {
    final current = device;
    if (current == null || owner != _owner) return;
    final changes = {
      for (final e in _deviceValues.entries)
        if (current[e.key] != e.value) e.key: e.value,
    };
    if (changes.isEmpty) return;
    final saved = await _account.saveDevice(
      installation!,
      changes,
      current['revision'] as int,
    );
    if (owner == _owner) device = saved;
  }

  /// Saved elsewhere first: the saved row wins and is shown again (A3-14).
  Future<void> _reloadDevice(String owner) async {
    try {
      final rows = await _account.load(installation!);
      if (owner != _owner) return;
      _theme = null;
      _applyDevice(rows.device);
    } catch (_) {
      saveError = 'Settings changed elsewhere and could not reload. Check your connection, then retry.';
    }
  }

  /// `mix` or one Discover format (profiles.discover_filter).
  String get discoverFilter => profile?['discover_filter'] as String? ?? 'mix';

  /// Saves the Discover format. A save that lost to another phone reloads the
  /// profile and tries once more (A3-14). Throws when it cannot save.
  Future<void> setDiscoverFilter(String filter) =>
      _setFilter('discover_filter', filter);

  String get practiceFilter => profile?['practice_filter'] as String? ?? 'mix';

  Future<void> setPracticeFilter(String filter) =>
      _setFilter('practice_filter', filter);

  Future<void> setPreferredLevel(String? level) =>
      _setFilter('preferred_level', level);

  Future<void> setWeeklyGoal(int? days) {
    if (days != null && (days < 1 || days > 7)) throw ArgumentError.value(days);
    return _setFilter('weekly_goal_days', days);
  }

  Future<void> setReminder(String? time) {
    final task = saving.then((_) => _setReminder(time));
    saving = task.catchError((Object _) {});
    return task;
  }

  Future<void> _setReminder(String? time) async {
    if (device == null) throw StateError('Sign in first');
    final old = device!['reminder_time'] as String?;
    if (time != null &&
        old == null &&
        !await (_reminders?.requestPermission() ?? Future.value(false))) {
      throw StateError(
        'Notifications are not allowed. Enable them in your phone settings, then try again.',
      );
    }
    try {
      await _reminders?.restore(time);
      device = await _account.saveDevice(installation!, {
        'reminder_time': time,
      }, device!['revision'] as int);
      await _store.saveRows(
        _owner!,
        jsonEncode({'profile': profile, 'device': device}),
      );
    } catch (e) {
      if (e is AccountConflict) await _reloadDevice(_owner!);
      await _reminders?.restore(device!['reminder_time'] as String?);
      rethrow;
    }
    _notify();
  }

  Future<Map<String, dynamic>> exportData() async {
    await saving;
    if (saveError != null ||
        (_offline != null && !await _offline.canReadServer())) {
      throw StateError('Connect and sync before exporting');
    }
    return _account.exportData();
  }

  Future<void> deleteActivity() async {
    final owner = _owner;
    await saving;
    Future<void> remove() {
      if (owner == null || owner != _owner || _account.userId != owner) {
        throw StateError('Account changed');
      }
      return _account.deleteData();
    }

    if (_offline == null) {
      await remove();
    } else {
      await _offline.deleteActivity(remove);
    }
    if (owner != _owner) return;
    await _reminders?.restore(null);
    await _store.clearState(_owner!);
    personalizationChanged();
    await load();
  }

  Future<void> _setFilter(String column, Object? filter) async {
    final owner = _owner;
    if (profile == null || owner == null) return;
    for (var attempt = 0; ; attempt++) {
      try {
        final saved = await _account.saveProfile({
          column: filter,
        }, profile!['revision'] as int);
        if (owner == _owner) profile = saved;
        return;
      } on AccountConflict {
        if (attempt > 0) rethrow;
        final rows = await _account.load(installation!);
        if (owner != _owner) return;
        profile = rows.profile;
      }
    }
  }

  Future<void> signOut() async {
    await _reminders?.restore(null);
    await _account.signOut();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      persist();
    } else {
      saving = saving.then((_) => _restoreReminder());
    }
  }

  Future<void> _restoreReminder() async {
    try {
      if (!signedIn) return;
      final owner = _owner;
      final rows = await _account.load(installation!);
      if (owner != _owner || device == null) return;
      // A reset from another phone must cancel this phone's saved reminder too.
      device = {...device!, 'reminder_time': rows.device['reminder_time']};
      await _store.saveRows(
        _owner!,
        jsonEncode({'profile': profile, 'device': device}),
      );
      await _reminders?.restore(device!['reminder_time'] as String?);
      _notify();
    } catch (_) {
      saveError = 'The reminder could not refresh. Check your connection and notification settings.';
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authEvents?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
