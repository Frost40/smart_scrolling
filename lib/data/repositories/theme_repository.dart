import 'package:flutter/material.dart';

import '../services/local_store.dart';

/// Keeps the Follow phone / Light / Dark choice on the phone.
class ThemeRepository {
  ThemeRepository(this._store);

  final LocalStore _store;

  Future<ThemeMode> load() async {
    final saved = await _store.themeMode();
    return ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
  }

  Future<void> save(ThemeMode mode) => _store.saveThemeMode(mode.name);
}
