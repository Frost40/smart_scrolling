import 'package:flutter/foundation.dart';

import '../../data/repositories/account_repository.dart';

/// Who you are: your email and Sign out.
class AccountProvider extends ChangeNotifier {
  AccountProvider(this._account);

  final AccountRepository _account;
  bool busy = false, _disposed = false;
  String? error;

  String get email => _account.email ?? '';

  Future<void> signOut() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _account.signOut();
    } catch (_) {
      error = 'Sign out failed. Check your connection, then try again.';
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
