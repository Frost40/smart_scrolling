import 'package:flutter/material.dart';

/// Follow phone / Light / Dark. [load] and [save] come from a repository that
/// app.dart passes in (core may not import data).
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(Future<ThemeMode> Function() load, this._save) {
    load()
        .then((saved) {
          if (_changed || _disposed) return;
          mode = saved;
          notifyListeners();
        })
        .catchError((Object _) {});
  }

  final Future<void> Function(ThemeMode) _save;
  ThemeMode mode = ThemeMode.system;
  bool _changed = false, _disposed = false;

  void setMode(ThemeMode value) {
    _changed = true;
    mode = value;
    notifyListeners();
    _save(value).catchError((Object _) {});
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
