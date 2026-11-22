import 'package:flutter/foundation.dart';

import '../../data/repositories/practice_repository.dart';
import '../../domain/models/progress_summary.dart';

class ProgressProvider extends ChangeNotifier {
  ProgressProvider(this._repo) {
    load();
  }
  final PracticeRepository _repo;
  ProgressSummary? summary;
  bool loading = false, _disposed = false;
  String? error;

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      summary = await _repo.progress();
    } catch (_) {
      error = 'Connect to the internet and sync your activity, then try again.';
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
