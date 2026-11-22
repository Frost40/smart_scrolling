import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/screens/discover/discover_provider.dart';

import '../../data/repositories/fake_discover_repository.dart';

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeDiscoverRepository repo;
  late List<String> savedFilters;

  Future<DiscoverProvider> start() async {
    final p = DiscoverProvider(
      repo,
      filter: 'mix',
      saveFilter: (f) async => savedFilters.add(f),
      openExplore: () {},
    );
    await settle();
    return p;
  }

  setUp(() {
    repo = FakeDiscoverRepository();
    savedFilters = [];
  });

  test('loads the first batch of 20', () async {
    final p = await start();
    expect(p.cards, hasLength(20));
    expect(p.exhausted, false);
  });

  test('refresh starts over when every card is already loaded (D46)', () async {
    repo.cards.removeRange(3, repo.cards.length);
    final p = await start();
    final first = [for (final c in p.cards) c.id];
    expect(first, hasLength(3));
    await p.refresh();
    expect([for (final c in p.cards) c.id], first);
    expect(repo.feedExcludes.last, isEmpty);
  });

  test('a card the feed sends again is no longer marked liked', () async {
    repo.cards.removeRange(3, repo.cards.length);
    final p = await start();
    final id = p.cards.first.id;
    await p.toggleLike(id);
    // Unliked elsewhere (another phone): the server forgets the Like.
    repo
      ..liked.remove(id)
      ..seen.remove(id);
    await p.refresh();
    expect(p.cards.map((c) => c.id), contains(id));
    expect(p.liked, isNot(contains(id)));
  });

  test('Like toggles: tap again undoes it', () async {
    final p = await start();
    final id = p.cards.first.id;
    await p.toggleLike(id);
    expect(p.liked, contains(id));
    expect(repo.liked, contains(id));
    await p.toggleLike(id);
    expect(p.liked, isNot(contains(id)));
    expect(repo.liked, isEmpty);
  });

  test('For later toggles; Like takes it out and undoing the Like puts it back as it was', () async {
    final p = await start();
    final id = p.cards.first.id;
    await p.toggleLater(id);
    final at = repo.saved[id];
    expect(p.saved[id], at);
    await p.toggleLike(id);
    expect(p.saved, isEmpty);
    expect(repo.saved, isEmpty);
    await p.toggleLike(id);
    expect(p.saved[id], at);
    expect(repo.saved[id], at);
    await p.toggleLater(id);
    expect(p.saved, isEmpty);
    expect(repo.saved, isEmpty);
  });

  test('swipes only turn things on', () async {
    final p = await start();
    final id = p.cards.first.id;
    p.swipe(id, right: true);
    await settle();
    p.swipe(id, right: true);
    await settle();
    expect(p.liked, contains(id));
    p.swipe(id, right: false);
    await settle();
    expect(p.saved.keys, contains(id));
  });

  test('a refused action is put back', () async {
    final p = await start();
    final id = p.cards.first.id;
    repo.fail = true;
    await p.toggleLike(id);
    expect(p.liked, isEmpty);
    expect(p.error, isNotNull);
  });

  test(
    'seen marks go in batches of 5; half on screen counts, less does not',
    () async {
      final p = await start();
      final ids = p.cards.map((c) => c.id).toList();
      p.visible(ids[0], 0.3);
      for (final id in ids.sublist(1, 5)) {
        p.visible(id, 0.6);
      }
      p.visible(ids[1], 1);
      await settle();
      expect(repo.seenBatches, isEmpty);
      await p.toggleLike(ids[5]); // the server marks a liked card seen itself
      p.visible(ids[5], 1);
      p.visible(ids[6], 0.5);
      await settle();
      expect(repo.seenBatches, [
        [ids[1], ids[2], ids[3], ids[4], ids[6]],
      ]);
    },
  );

  test('refresh leaves out every loaded and seen card', () async {
    final p = await start();
    final first = p.cards.map((c) => c.id).toSet();
    p.visible(p.cards.first.id, 1);
    await p.refresh();
    expect(repo.feedExcludes.last, first);
    expect(repo.seenBatches.single, [first.first]);
    expect(p.cards.map((c) => c.id).toSet().intersection(first), isEmpty);
    expect(p.cards, hasLength(10));
    expect(p.exhausted, true);
  });

  test('more cards load 5 cards from the end', () async {
    final p = await start();
    p.visible(p.cards[14].id, 0.1);
    await settle();
    expect(p.cards, hasLength(20));
    p.visible(p.cards[15].id, 0.1);
    await settle();
    expect(p.cards, hasLength(30));
  });

  test('a new format is saved, then the feed reloads from scratch', () async {
    final p = await start();
    await p.setFilter('myth');
    expect(savedFilters, ['myth']);
    expect(p.filter, 'myth');
    expect(repo.feedExcludes.last, isEmpty);
  });

  test('report sends the message', () async {
    final p = await start();
    expect(await p.reportProblem('sample-a/card-0', 'Typo'), true);
    expect(repo.reports, [('sample-a/card-0', 'Typo')]);
    repo.fail = true;
    expect(await p.reportProblem('sample-a/card-0', ''), false);
  });
}
