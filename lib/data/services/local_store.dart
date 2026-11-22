import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// The phone's own storage: the installation id, the theme and each person's snapshot.
class LocalStore {
  Future<void> clearState(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['state:$userId', 'rows:$userId']) {
      if (!await prefs.remove(key)) {
        throw StateError('Could not clear saved settings');
      }
    }
  }

  Future<String> installationId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('installation_id');
    if (saved != null) return saved;
    final id = uuid();
    if (!await prefs.setString('installation_id', id)) {
      throw StateError('Could not save the installation id');
    }
    return id;
  }

  Future<String?> themeMode() async =>
      (await SharedPreferences.getInstance()).getString('theme_mode');

  Future<void> saveThemeMode(String name) async {
    await (await SharedPreferences.getInstance()).setString('theme_mode', name);
  }

  /// One snapshot per person, so a second account on this phone starts clean.
  Future<String?> loadState(String userId) async =>
      (await SharedPreferences.getInstance()).getString('state:$userId');

  Future<void> saveState(String userId, String json) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      'state:$userId',
      json,
    )) {
      throw StateError('Could not save the app state');
    }
  }

  /// The last profile and phone rows each person loaded, so the app opens offline.
  Future<String?> loadRows(String userId) async =>
      (await SharedPreferences.getInstance()).getString('rows:$userId');

  Future<void> saveRows(String userId, String json) async {
    await (await SharedPreferences.getInstance()).setString(
      'rows:$userId',
      json,
    );
  }
}

/// A random UUID v4.
String uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
