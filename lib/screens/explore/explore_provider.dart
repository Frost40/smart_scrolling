import 'package:flutter/foundation.dart';

import '../../data/repositories/explore_repository.dart';
import '../../domain/models/source.dart';
import '../../domain/models/topic.dart';
import '../../domain/topic_groups.dart';

class ExploreProvider extends ChangeNotifier {
  ExploreProvider(this._repo) {
    load();
  }
  final ExploreRepository _repo;
  List<Topic> topics = [];
  List<Source> results = [];
  String query = '';
  String? error;

  /// Chosen topics, with the same rules as Settings (`toggleTopic`).
  Set<String> chosen = {};

  /// The main area whose sub-topics show under the topic row.
  String? open;
  bool loading = false, _disposed = false;
  int _generation = 0;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      final tree = await _repo.topicTree();
      final found = chosen.isEmpty
          ? await _repo.searchSources(query)
          : _unique([
              for (final list in await Future.wait(
                chosen.map(_repo.sourcesByTopic),
              ))
                ...list,
            ]);
      if (generation != _generation) return;
      topics = tree;
      results = found;
    } catch (_) {
      if (generation != _generation) return;
      error = 'Sources could not load. Check your connection, then try again.';
    }
    loading = false;
    _notify();
  }

  void search(String text) {
    query = text;
    chosen = {};
    open = null;
    load();
  }

  /// An area with sub-topics opens them on the first tap; after that taps
  /// choose and drop like in Settings (`toggleTopic`), and the area closes
  /// once nothing in it is chosen. Any other topic is chosen or dropped at
  /// once.
  void tapTopic(String id) {
    final hasSubs = topics.any((t) => t.parentId == id);
    if (hasSubs && open != id) {
      open = id;
      return _notify();
    }
    chosen = toggleTopic(topics, chosen, id);
    final inOpen = chosen.any(
      (c) => c == open || topics.any((t) => t.id == c && t.parentId == open),
    );
    if (!inOpen && topics.any((t) => t.id == id && t.parentId == null)) {
      open = null;
    }
    query = '';
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// [sources] without repeats, first one kept.
List<Source> _unique(List<Source> sources) {
  final seen = <String>{};
  return [
    for (final s in sources)
      if (seen.add(s.id)) s,
  ];
}
