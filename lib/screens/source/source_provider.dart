import 'package:flutter/foundation.dart';

import '../../data/repositories/discover_repository.dart';
import '../../data/repositories/explore_repository.dart';
import '../../domain/models/source.dart';

/// One source page: its facts and its published cards.
class SourceProvider extends ChangeNotifier {
  SourceProvider(this._cards, this.id, this._explore, this._changed) {
    load();
  }

  final DiscoverRepository _cards;
  final String id;
  final ExploreRepository _explore;
  final VoidCallback _changed;
  String? choice, actionMessage;
  bool busy = false;

  Future<void> choose(String? value) => _act(() async {
    if (value == 'follow') {
      await _explore.followSource(id);
    } else if (value == 'hide') {
      await _explore.hideSource(id);
    } else {
      await _explore.forgetSource(id);
    }
    choice = value;
    _changed();
    return value == 'hide'
        ? 'Source hidden.'
        : value == 'follow'
        ? 'Added to your feed.'
        : 'Source preference removed.';
  });
  Future<void> ask(String message) => _act(() async {
    await _explore.askForMoreCards(id, message);
    return "Your request is on the owner's to-do list.";
  });
  Future<void> _act(Future<String> Function() action) async {
    if (busy) return;
    busy = true;
    actionMessage = null;
    _notify();
    try {
      actionMessage = await action();
    } catch (_) {
      actionMessage =
          'That did not save. Check your connection, then try again.';
    }
    busy = false;
    _notify();
  }

  Source? source;
  String? error;
  bool _disposed = false;

  Future<void> load() async {
    error = null;
    _notify();
    try {
      source = await _cards.source(id);
      choice = await _explore.sourceChoice(id);
    } catch (_) {
      error =
          'This source could not load. Check your connection, then try again.';
    }
    _notify();
  }

  Future<bool> reportProblem(String cardId, String message) async {
    try {
      await _cards.reportProblem(cardId, message);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
