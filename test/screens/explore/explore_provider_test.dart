import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/screens/explore/explore_provider.dart';
import 'package:smart_scrolling/domain/models/source.dart';
import 'package:smart_scrolling/domain/models/topic.dart';

import '../../data/repositories/fake_explore_repository.dart';

class DelayedExplore extends FakeExploreRepository {
  final pending = <String, Completer<List<Source>>>{};
  @override
  Future<List<Source>> searchSources(String text) =>
      (pending[text] = Completer<List<Source>>()).future;
}

class WithSoloArea extends FakeExploreRepository {
  @override
  Future<List<Topic>> topicTree() async => [
    ...await super.topicTree(),
    const Topic('history', 'History'),
  ];
}

void main() {
  test('an area without sub-topics is chosen at once', () async {
    final p = ExploreProvider(WithSoloArea());
    await p.load();
    p.tapTopic('learning');
    expect(p.open, 'learning');
    expect(p.chosen, isEmpty);
    p.tapTopic('memory');
    p.tapTopic('history');
    expect(p.open, 'learning');
    expect(p.chosen, {'memory', 'history'});
    p.tapTopic('history');
    expect(p.chosen, {'memory'});
    p.dispose();
  });

  test(
    'stale search cannot overwrite current results; errors can retry',
    () async {
      final repo = DelayedExplore();
      final p = ExploreProvider(repo);
      await Future<void>.delayed(Duration.zero);
      repo.pending['']!.complete([]);
      await Future<void>.delayed(Duration.zero);
      p.search('old');
      await Future<void>.delayed(Duration.zero);
      p.search('new');
      await Future<void>.delayed(Duration.zero);
      repo.pending['new']!.complete([
        const Source(id: 'new', kind: 'book', title: 'New'),
      ]);
      await Future<void>.delayed(Duration.zero);
      repo.pending['old']!.complete([]);
      await Future<void>.delayed(Duration.zero);
      expect(p.results.single.id, 'new');
      p.search('offline');
      await Future<void>.delayed(Duration.zero);
      repo.pending['offline']!.completeError(Exception('offline'));
      await Future<void>.delayed(Duration.zero);
      expect(p.error, isNotNull);
      final retry = p.load();
      await Future<void>.delayed(Duration.zero);
      repo.pending['offline']!.complete([]);
      await retry;
      expect(p.error, isNull);
      p.dispose();
    },
  );
}
