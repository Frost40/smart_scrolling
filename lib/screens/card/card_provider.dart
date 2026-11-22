import 'package:flutter/foundation.dart';

import '../../data/repositories/discover_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/models/discover_card.dart';
import '../../domain/models/library_card.dart';

/// The exact card opened from See also; unavailable offline cards can be retried.
class CardProvider extends ChangeNotifier {
  CardProvider(this._discover, this._library, this.id) {
    load();
  }
  final DiscoverRepository _discover;
  final LibraryRepository _library;
  final String id;
  DiscoverCard? card;
  LibraryCard? entry;
  String? error, actionError;
  bool saving = false, _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    error = null;
    _notify();
    try {
      card = await _discover.card(id);
      entry = (await _library.liked())
          .where((c) => c.card.id == id)
          .firstOrNull;
    } catch (_) {
      error = 'This card could not load. Go online or try again.';
    }
    _notify();
  }

  Future<String?> saveNote(String text) async {
    if (saving) return 'Your note is still saving.';
    saving = true;
    actionError = null;
    _notify();
    try {
      await _library.saveNote(id, text);
      await load();
      actionError = error;
    } catch (_) {
      actionError = 'Your note did not save. Please try again.';
    }
    saving = false;
    _notify();
    return actionError;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
