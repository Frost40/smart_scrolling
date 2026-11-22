import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/screens/library/library_provider.dart';

import '../../data/repositories/fake_library_repository.dart';

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeLibraryRepository repo;
  late ValueNotifier<int> tab;

  Future<LibraryProvider> start() async {
    final p = LibraryProvider(
      repo,
      isOpen: () => tab.value == 3,
      tabChanges: tab,
    );
    await settle();
    return p;
  }

  List<String> ids(LibraryProvider p) => [for (final c in p.visible) c.card.id];

  setUp(() {
    repo = FakeLibraryRepository();
    tab = ValueNotifier(3);
  });

  test('loads both feeds, newest first', () async {
    final p = await start();
    expect(p.loaded, true);
    expect(ids(p), [
      'sample-a/card-0',
      'sample-b/card-2',
      'sample-a/card-4',
      'sample-b/card-6',
    ]);
    p.showLater(true);
    expect(ids(p).first, 'sample-a/card-1');
    expect(p.visible, hasLength(4));
  });

  test('search finds title, front text and source title, any case', () async {
    final p = await start();
    p.search('card 4');
    expect(ids(p), ['sample-a/card-4']);
    p.search('FRONT TEXT 2');
    expect(ids(p), ['sample-b/card-2']);
    p.search('sample b');
    expect(ids(p), ['sample-b/card-2', 'sample-b/card-6']);
    p.search('nothing like this');
    expect(p.visible, isEmpty);
    expect(p.tabCards, isNotEmpty);
  });

  test(
    'filters by format, topic and source, and combine with search',
    () async {
      final p = await start();
      expect(p.formats, ['concept', 'quote']);
      expect(p.topics, {'x': 'Topic X', 'y': 'Topic Y'});
      expect(p.sources, {'sample-a': 'Sample A', 'sample-b': 'Sample B'});
      p.filterFormat('quote');
      expect(ids(p), ['sample-b/card-2', 'sample-b/card-6']);
      p.filterTopic('x');
      expect(ids(p), ['sample-b/card-6']);
      p.filterSource('sample-a');
      expect(p.visible, isEmpty);
      p.filterSource('all');
      p.search('card 6');
      expect(ids(p), ['sample-b/card-6']);
    },
  );

  test('each tab offers only its own filter values', () async {
    final p = await start();
    p.filterTopic('x');
    p.showLater(true);
    expect(p.topics, {'x': 'Topic X', 'y': 'Topic Y'});
    expect(ids(p), ['sample-b/card-3']);
  });

  test('a filter whose cards are gone counts as All', () async {
    final p = await start();
    p.filterTopic('x');
    expect(p.visible, hasLength(2));
    await p.removeLiked(p.visible.first);
    await p.removeLiked(p.visible.first);
    expect(p.topic, 'all');
    expect(p.visible, hasLength(2));
  });

  test('Remove from Liked, then Undo restores it in place', () async {
    final p = await start();
    final first = p.visible.first;
    expect(await p.removeLiked(first), true);
    expect(repo.unliked, [first.card.id]);
    expect(p.liked, isNot(contains(first)));
    await p.undo();
    expect(repo.restoredLikes, [first.card.id]);
    expect(ids(p).first, first.card.id);
    expect(p.liked, hasLength(4));
    await p.undo(); // nothing left to undo
    expect(repo.restoredLikes, hasLength(1));
  });

  test('Remove from For later, then Undo restores it in place', () async {
    final p = await start();
    p.showLater(true);
    final second = p.visible[1];
    expect(await p.removeLater(second), true);
    expect(repo.unsaved, [second.card.id]);
    expect(p.later, hasLength(3));
    await p.undo();
    expect(repo.restoredSaves, [second.card.id]);
    expect(ids(p)[1], second.card.id);
  });

  test('only the latest Remove can be undone', () async {
    final p = await start();
    final a = p.visible[0], b = p.visible[1];
    await p.removeLiked(a);
    await p.removeLiked(b);
    await p.undo();
    expect(repo.restoredLikes, [b.card.id]);
    expect(p.liked, contains(b));
    expect(p.liked, isNot(contains(a)));
  });

  test('a refused Remove or Undo puts the list back and says why', () async {
    final p = await start();
    final first = p.visible.first;
    repo.fail = true;
    expect(await p.removeLiked(first), false);
    expect(p.liked, contains(first));
    expect(p.actionError, isNotNull);
    repo.fail = false;
    await p.removeLiked(first);
    expect(p.actionError, isNull);
    repo.fail = true;
    await p.undo();
    expect(p.liked, isNot(contains(first)));
    expect(p.actionError, isNotNull);
  });

  test('Pause and Resume reviews change the status and save', () async {
    final p = await start();
    final first = p.visible.first;
    expect(first.reviewStatus(DateTime.utc(2026, 11, 1)), 'Next test: 3 Nov');
    expect(await p.setPaused(first, true), true);
    expect(repo.pauses, [(first.card.id, true)]);
    final paused = p.visible.first;
    expect(paused.reviewStatus(DateTime.utc(2026, 11, 1)), 'Reviews paused');
    await p.setPaused(paused, false);
    expect(repo.pauses.last, (first.card.id, false));
    repo.fail = true;
    expect(await p.setPaused(p.visible.first, true), false);
    expect(p.visible.first.reviewsPaused, false);
  });

  test('a card with no published test says it is waiting for tests', () async {
    final p = await start();
    final waiting = p.visible.firstWhere((c) => c.card.id.endsWith('card-2'));
    expect(
      waiting.reviewStatus(DateTime.utc(2026, 11, 1)),
      'Waiting for tests',
    );
  });

  test('reloads each time the tab opens, and when refreshed', () async {
    final p = await start();
    repo.likedCards.removeAt(0);
    tab.value = 0;
    await settle();
    expect(p.liked, hasLength(4));
    tab.value = 3;
    await settle();
    expect(p.liked, hasLength(3));
    repo.likedCards.removeAt(0);
    await p.refresh();
    expect(p.liked, hasLength(2));
  });

  test('a load that fails says so and keeps what is shown', () async {
    final p = await start();
    repo.fail = true;
    await p.refresh();
    expect(p.loadError, isNotNull);
    expect(p.liked, hasLength(4));
    repo.fail = false;
    await p.refresh();
    expect(p.loadError, isNull);
  });
}
