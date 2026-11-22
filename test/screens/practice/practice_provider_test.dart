import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/practice_card.dart';
import 'package:smart_scrolling/screens/practice/practice_provider.dart';

import '../../data/repositories/fake_practice_repository.dart';

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePracticeRepository repo;
  late ValueNotifier<bool> open;
  final filters = <String>[];
  Future<PracticeProvider> start() async {
    final p = PracticeProvider(
      repo,
      filter: 'mix',
      saveFilter: (f) async => filters.add(f),
      isOpen: () => open.value,
      tabChanges: open,
    );
    addTearDown(p.dispose);
    await settle();
    return p;
  }

  setUp(() {
    repo = FakePracticeRepository();
    open = ValueNotifier(true);
    filters.clear();
  });
  tearDown(() => open.dispose());

  test('pages ten Likes at a time; scrolling does not answer', () async {
    final p = await start();
    expect(p.entries.length, 10);
    expect(p.dueCount, 12);
    await p.loadMore();
    expect(p.entries.length, 12);
    expect(p.hasMore, false);
    expect(repo.answers, isEmpty);
  });
  test('reveal is required; Good records the three-day step once', () async {
    final p = await start();
    final e = p.entries.first;
    await p.answer(e, 'good');
    expect(repo.answers, isEmpty);
    p.reveal(e);
    await p.answer(e, 'good');
    await p.answer(e, 'easy');
    expect(e.saved, true);
    expect(repo.answers.length, 1);
    expect(e.answer!.step.level, 1);
    expect(
      e.answer!.step.nextReviewAt.difference(e.answer!.answeredAt),
      const Duration(days: 3),
    );
    expect(p.entries, contains(e));
    expect(p.dueCount, 11);
  });
  test('Check needs a choice; wrong restarts the ladder', () async {
    final p = await start();
    final e = p.entries[1];
    await p.answer(e);
    expect(repo.answers, isEmpty);
    p.choose(e, 0);
    await p.answer(e);
    expect(e.answer!.result, 'wrong');
    expect(e.answer!.value, 0);
    expect(e.answer!.step.level, 0);
    p.choose(e, 1);
    expect(e.choice, 0);
  });
  test(
    'failed save retains the identical attempt for Retry and blocks refresh',
    () async {
      final p = await start();
      final e = p.entries.first;
      p.reveal(e);
      repo.failSave = true;
      await p.answer(e, 'easy');
      final original = e.answer;
      expect(e.error, isNotNull);
      await p.refresh();
      expect(p.entries, contains(e));
      expect(p.dueCount, 12);
      repo.failSave = false;
      await p.retry(e);
      expect(repo.answers.last, same(original));
      expect(e.saved, true);
      expect(e.error, isNull);
      expect(p.dueCount, 11);
    },
  );
  test('Practice now loads early Likes only when nothing is due', () async {
    final p = await start();
    await p.practiceNow();
    expect(p.early, false);
    repo.early = true;
    await p.refresh();
    expect(p.entries, isEmpty);
    await p.practiceNow();
    expect(p.early, true);
    expect(p.entries.length, 10);
    final e = p.entries.first;
    p.reveal(e);
    await p.answer(e, 'hard');
    expect(p.dueCount, 0);
    expect(e.answer!.step.level, 0);
  });
  test('filter saves and reloads; opening the tab reloads Likes', () async {
    final p = await start();
    await p.setFilter('multiple_choice');
    expect(filters, ['multiple_choice']);
    expect(p.entries.every((e) => e.test.type == 'multiple_choice'), true);
    repo.entries.clear();
    open.value = false;
    open.value = true;
    await settle();
    expect(p.entries, isEmpty);
  });
  test('a removed Like can recover after an unsaved answer without claiming success', () async {
    final p = await start();
    final e = p.entries.first;
    p.reveal(e);
    repo.failSave = true;
    await p.answer(e, 'good');
    expect(p.pending, true);
    repo.entries.remove(e);
    repo.unavailable = true;
    await p.retry(e);
    expect(e.saved, false);
    expect(e.unavailable, true);
    expect(e.error, contains('no longer available'));
    expect(p.pending, false);
    await p.refresh();
    expect(p.entries, isNot(contains(e)));
    expect(p.error, isNull);
  });

  test('load errors can retry', () async {
    repo.failLoad = true;
    final p = await start();
    expect(p.error, isNotNull);
    repo.failLoad = false;
    await p.refresh();
    expect(p.error, isNull);
    expect(p.entries.length, 10);
  });

  test(
    'new answers keep their values on retry and freeze controls after Check',
    () async {
      final p = await start();
      for (final type in ['true_false', 'ordering', 'matching']) {
        final e = PracticeEntry(
          card: repo.entries.first.card,
          level: 2,
          test: PracticeCard(
            id: type,
            type: type,
            prompt: '?',
            isTrue: false,
            correctOrder: const ['A', 'B', 'C'],
            matchLeft: const ['1', '2', '3'],
            matchRight: const ['A', 'B', 'C'],
          ),
        );
        if (type == 'true_false') {
          await p.answer(e);
          expect(e.answer, isNull);
          p.choose(e, 0); // Wrong.
        } else if (type == 'ordering') {
          e.order.setAll(0, [0, 2, 1]); // Partly right.
          p.move(e, -1, 0);
          p.move(e, 0, 3);
          expect(e.order, [0, 2, 1]);
        } else {
          p.pair(e, 0); // A right tap without a left does nothing.
          expect(e.matches, [null, null, null]);
          p.selectLeft(e, 0);
          p.pair(e, 0);
          p.selectLeft(e, 1);
          p.pair(e, 0); // Reusing a right item unpairs the old left.
          expect(e.matches, [null, 0, null]);
          await p.answer(e);
          expect(e.answer, isNull);
          for (final (left, right) in [(0, 0), (1, 2), (2, 1)]) {
            p.selectLeft(e, left);
            p.pair(e, right);
          }
        }
        repo.failSave = true;
        await p.answer(e);
        final original = e.answer!;
        expect(original.result, 'wrong');
        expect(original.step.level, 0);
        expect(original.value, type == 'true_false' ? true : ['A', 'C', 'B']);
        final order = List.of(e.order), pairs = List.of(e.matches);
        p.move(e, 0, 1);
        p.selectLeft(e, 0);
        p.pair(e, 1);
        p.choose(e, 1);
        expect(e.order, order);
        expect(e.matches, pairs);
        repo.failSave = false;
        await p.retry(e);
        expect(repo.answers.last, same(original));
        expect(e.saved, true);
      }
    },
  );

  test(
    'retry after a failed refresh replaces the batch instead of appending',
    () async {
      final p = await start();
      repo.failLoad = true;
      await p.refresh();
      expect(p.entries.length, 10);
      repo.failLoad = false;
      repo.entries.removeAt(0);
      await p.retryLoad();
      expect(p.entries.length, 10);
      expect(p.entries.first.card.id, 'sample-b/card-1');
    },
  );
}
