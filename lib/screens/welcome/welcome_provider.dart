import 'package:flutter/foundation.dart';

import '../../data/repositories/account_repository.dart';

/// Sign-in: Google for everyone, Test login for agents in debug builds (A3-8).
class WelcomeProvider extends ChangeNotifier {
  WelcomeProvider(this._account, {this.testLogin});

  final AccountRepository _account;

  /// Email and password of the test login; null hides the button.
  final (String, String)? testLogin;
  bool busy = false, _disposed = false;
  String? error;

  Future<void> signInWithGoogle() =>
      _run(_account.signInWithGoogle, 'Google sign-in could not start.');

  Future<void> signInForTest() => _run(
    () => _account.signInWithPassword(testLogin!.$1, testLogin!.$2),
    'Test login failed.',
  );

  Future<void> _run(Future<void> Function() action, String failure) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (_) {
      error = '$failure Check your connection, then try again.';
    }
    busy = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
