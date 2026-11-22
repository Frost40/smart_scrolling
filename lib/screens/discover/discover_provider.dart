import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/discover_repository.dart';
import '../../domain/models/discover_card.dart';

/// The Discover feed: cards, Like / For later toggles (D11), seen batching (A3-4)
/// and refresh with everything already loaded left out (D10, A3-5).
class DiscoverProvider extends ChangeNotifier {
  DiscoverProvider(
    this._cards, {
    required this.filter,
    required this.saveFilter,
    required this.openExplore,
  }) {
    refresh();
  }

  static const batch = 20, loadAhead = 5, seenBatch = 5;

  final DiscoverRepository _cards;
  final Future<void> Function(String) saveFilter;
  final VoidCallback openExplore;

  /// `mix` or one format (profiles.discover_filter).
  String filter;
  List<DiscoverCard> cards = [];
  final Set<String> liked = {};

  /// For later: card id → when it was saved.
  final Map<String, DateTime> saved = {};
  bool loading = false, exhausted = false;
  String? error;

  final Set<String> _loaded = {}, _seen = {};
  final List<String> _pendingSeen = [];
  // A Like takes the card out of For later; undoing the Like puts it back as it was.
  final Map<String, DateTime> _savedBeforeLike = {};
  int _generation = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// A new batch that leaves out every card loaded so far. When that leaves
  /// nothing, it starts over, so the feed never runs dry (D46).
  Future<void> refresh() async {
    await flushSeen();
    exhausted = false;
    await _load(replace: true);
    if (cards.isEmpty && error == null && _loaded.isNotEmpty) {
      _loaded.clear();
      await _load(replace: true);
    }
  }

  Future<void> loadMore() async {
    if (loading || exhausted) return;
    await _load(replace: false);
  }

  Future<void> reloadCard(String id) async {
    try {
      final card = await _cards.card(id);
      final i = cards.indexWhere((c) => c.id == id);
      if (i >= 0) cards[i] = card;
      _notify();
    } catch (_) {
      /* Keep the readable card if the connection was lost. */
    }
  }

  Future<void> _load({required bool replace}) async {
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      final next = await _cards.feed(
        limit: batch,
        exclude: _loaded,
        filter: filter,
      );
      if (generation != _generation) return;
      // The feed never sends a liked or saved card, so a mark on a card it
      // sends is stale (changed on another phone, or the feed started over).
      for (final c in next) {
        liked.remove(c.id);
        saved.remove(c.id);
      }
      _loaded.addAll(next.map((c) => c.id));
      cards = replace ? next : [...cards, ...next];
      exhausted = next.length < batch;
    } catch (_) {
      if (generation != _generation) return;
      error = 'Cards could not load. Check your connection, then try again.';
    }
    loading = false;
    _notify();
  }

  Future<void> setFilter(String value) async {
    if (value == filter) return;
    final before = filter;
    filter = value;
    _notify();
    try {
      await saveFilter(value);
    } catch (_) {
      filter = before;
      error = 'Your format choice could not be saved. Check your connection.';
      _notify();
      return;
    }
    _loaded.clear();
    cards = [];
    await refresh();
  }

  /// Called while card [id] shows; [fraction] is how much of it is on screen.
  void visible(String id, double fraction) {
    if (fraction <= 0) return;
    if (cards.indexWhere((c) => c.id == id) >= cards.length - loadAhead) {
      loadMore();
    }
    if (fraction >= 0.5 && _seen.add(id)) {
      _pendingSeen.add(id);
      if (_pendingSeen.length >= seenBatch) flushSeen();
    }
  }

  /// Sends the waiting seen marks; on failure they wait for the next batch.
  Future<void> flushSeen() async {
    if (_pendingSeen.isEmpty) return;
    final ids = List.of(_pendingSeen);
    _pendingSeen.clear();
    try {
      await _cards.markSeen(ids);
    } catch (_) {
      _pendingSeen.addAll(ids);
    }
  }

  /// Swipe right = Like, left = For later. A swipe never undoes.
  void swipe(String id, {required bool right}) {
    if (right && !liked.contains(id)) toggleLike(id);
    if (!right && !saved.containsKey(id)) toggleLater(id);
  }

  Future<void> toggleLike(String id) async {
    _seen.add(id); // the server marks it seen
    final wasLiked = liked.contains(id);
    final savedAt = wasLiked ? _savedBeforeLike[id] : saved[id];
    void apply(bool like) {
      if (like) {
        liked.add(id);
        if (savedAt != null) _savedBeforeLike[id] = savedAt;
        saved.remove(id);
      } else {
        liked.remove(id);
        _savedBeforeLike.remove(id);
        if (savedAt != null) saved[id] = savedAt;
      }
    }

    apply(!wasLiked);
    await _try(
      () => wasLiked ? _cards.undoLike(id, savedAt: savedAt) : _cards.like(id),
      () => apply(wasLiked),
    );
  }

  Future<void> toggleLater(String id) async {
    _seen.add(id);
    final before = saved[id];
    if (before != null) {
      saved.remove(id);
      await _try(() => _cards.unsave(id), () => saved[id] = before);
    } else {
      saved[id] = DateTime.now();
      await _try(() async {
        final at = await _cards.saveForLater(id);
        if (saved.containsKey(id)) saved[id] = at;
      }, () => saved.remove(id));
    }
  }

  /// Shows the change at once; puts it back if the server refuses.
  Future<void> _try(Future<void> Function() call, VoidCallback revert) async {
    error = null;
    _notify();
    try {
      await call();
    } catch (_) {
      revert();
      error = 'That did not save. Check your connection, then try again.';
    }
    _notify();
  }

  /// Adds a to-do for the owner. Returns false when it could not be sent.
  Future<bool> reportProblem(String cardId, String message) async {
    try {
      await _cards.reportProblem(cardId, message);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(flushSeen());
    super.dispose();
  }
}
