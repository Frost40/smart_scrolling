import 'package:flutter/foundation.dart';

import '../../data/repositories/library_repository.dart';
import '../../domain/models/library_card.dart';

/// Library feeds, collection filters, notes and Remove with Undo (A3-12).
class LibraryProvider extends ChangeNotifier {
  LibraryProvider(
    this._repo, {
    required bool Function() isOpen,
    required Listenable tabChanges,
    int Function()? tabTaps,
  }) : _isOpen = isOpen,
       _tabChanges = tabChanges,
       _tabTaps = tabTaps {
    _wasOpen = isOpen();
    _taps = tabTaps?.call() ?? 0;
    tabChanges.addListener(_tabChanged);
    refresh();
  }

  static const all = 'all';
  final LibraryRepository _repo;
  final bool Function() _isOpen;
  final Listenable _tabChanges;
  final int Function()? _tabTaps;
  List<LibraryCard> liked = [], later = [];
  Map<String, String> collections = {};
  String? collectionId;
  bool laterTab = false, loaded = false, loading = false, busy = false;
  String query = '';
  String _format = all, _topic = all, _source = all;
  String? loadError, actionError;
  ({bool fromLiked, LibraryCard card, Future<void> Function() restore})? _undo;
  bool _wasOpen = false, _disposed = false;
  int _generation = 0, _taps = 0;

  /// Collections unfold by default only while there are at most 2 (v2);
  /// null goes back to that default.
  bool get collectionsShown => _shown ?? collections.length <= 2;
  bool? _shown;
  void showCollections(bool? on) => _set(() => _shown = on);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _set(VoidCallback change) {
    change();
    _notify();
  }

  void _tabChanged() {
    final open = _isOpen(), taps = _tabTaps?.call() ?? 0;
    if (open && !_wasOpen) refresh();
    // Opening Library from the tab bar folds the collections back to default.
    if (open && taps != _taps) showCollections(null);
    _wasOpen = open;
    _taps = taps;
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    loading = true;
    loadError = null;
    _notify();
    try {
      final (a, b, folders) = await (
        _repo.liked(),
        _repo.later(),
        _repo.collections(),
      ).wait;
      if (generation != _generation) return;
      liked = List.of(a);
      later = List.of(b);
      collections = folders;
      if (!collections.containsKey(collectionId)) collectionId = null;
      loaded = true;
    } catch (_) {
      if (generation != _generation) return;
      loadError = 'Your Library could not load. Check your connection.';
    }
    loading = false;
    _notify();
  }

  List<LibraryCard> get tabCards => laterTab
      ? later
      : [
          for (final c in liked)
            if (collectionId == null || c.collectionIds.contains(collectionId))
              c,
        ];
  List<LibraryCard> get visible => [
    for (final c in tabCards)
      if (c.matches(query) &&
          (format == all || c.card.format == format) &&
          (topic == all || c.topics.containsKey(topic)) &&
          (source == all || c.card.sourceId == source))
        c,
  ];
  List<String> get formats =>
      {for (final c in tabCards) c.card.format}.toList()..sort();
  Map<String, String> get topics => {for (final c in tabCards) ...c.topics};
  Map<String, String> get sources => {
    for (final c in tabCards) c.card.sourceId: c.card.sourceTitle,
  };
  String get format => formats.contains(_format) ? _format : all;
  String get topic => topics.containsKey(_topic) ? _topic : all;
  String get source => sources.containsKey(_source) ? _source : all;
  void showLater(bool value) => _set(() {
    laterTab = value;
    collectionId = null;
  });
  void openCollection(String? id) => _set(() {
    collectionId = id;
    laterTab = false;
  });
  void search(String text) => _set(() => query = text);
  void filterFormat(String value) => _set(() => _format = value);
  void filterTopic(String value) => _set(() => _topic = value);
  void filterSource(String value) => _set(() => _source = value);

  Future<bool> _edit(Future<void> Function() action) async {
    if (busy) return false;
    // A new 3rd collection must not fold the list you are using.
    _shown ??= collectionsShown;
    busy = true;
    actionError = null;
    _notify();
    try {
      await action();
      await refresh();
      return loadError == null;
    } on ArgumentError {
      actionError = 'Use a unique collection name of 1–60 characters.';
      return false;
    } catch (_) {
      actionError = 'That did not save. Check your connection, then try again.';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> createCollection(String name) =>
      _edit(() => _repo.createCollection(name));
  Future<bool> renameCollection(String id, String name) =>
      _edit(() => _repo.renameCollection(id, name));
  Future<bool> deleteCollection(String id) =>
      _edit(() => _repo.deleteCollection(id));
  Future<bool> saveNote(LibraryCard c, String note) =>
      _edit(() => _repo.saveNote(c.card.id, note));
  Future<bool> setMembership(LibraryCard c, String id, bool included) =>
      _edit(() => _repo.setMembership(c.card.id, id, included));

  Future<bool> removeLiked(LibraryCard c) async {
    late RemovedLike gone;
    final done = await _remove(
      liked,
      c,
      () async => gone = await _repo.unlike(c.card.id),
    );
    if (done) {
      _undo = (
        fromLiked: true,
        card: c,
        restore: () => _repo.restoreLike(gone),
      );
    }
    return done;
  }

  Future<bool> removeLater(LibraryCard c) async {
    final done = await _remove(later, c, () => _repo.unsave(c.card.id));
    if (done) {
      _undo = (fromLiked: false, card: c, restore: () => _repo.restoreSaved(c));
    }
    return done;
  }

  Future<bool> _remove(
    List<LibraryCard> list,
    LibraryCard c,
    Future<void> Function() call,
  ) async {
    list.remove(c);
    actionError = null;
    _notify();
    try {
      await call();
      return true;
    } catch (_) {
      _insert(list, c);
      actionError = 'That did not save. Check your connection, then try again.';
      _notify();
      return false;
    }
  }

  Future<void> undo() async {
    final u = _undo;
    if (u == null) return;
    _undo = null;
    final list = u.fromLiked ? liked : later;
    _insert(list, u.card);
    actionError = null;
    _notify();
    try {
      await u.restore();
    } catch (_) {
      list.remove(u.card);
      actionError = 'Undo did not save. Check your connection.';
      _notify();
    }
  }

  void _insert(List<LibraryCard> list, LibraryCard c) {
    list
      ..add(c)
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  Future<bool> setPaused(LibraryCard c, bool paused) async {
    final i = liked.indexOf(c);
    if (i < 0) return false;
    final changed = c.withPaused(paused);
    liked[i] = changed;
    actionError = null;
    _notify();
    try {
      await _repo.setReviewsPaused(c.card.id, paused);
      return true;
    } catch (_) {
      final now = liked.indexOf(changed);
      if (now >= 0) liked[now] = c;
      actionError = 'That did not save. Check your connection, then try again.';
      _notify();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _tabChanges.removeListener(_tabChanged);
    super.dispose();
  }
}
