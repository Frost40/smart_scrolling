import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';
import 'package:smart_scrolling/domain/models/practice_card.dart';

void main() {
  test('server and cached rows keep every new answer field', () {
    final card = PracticeCard.fromRow({
      'id': 'sample/test',
      'type': 'matching',
      'prompt': '?',
      'version': 3,
      'is_true': false,
      'correct_order': ['A', 'B'],
      'match_left': ['One', 'Two'],
      'match_right': ['A', 'B'],
    });
    expect(card.version, 3);
    expect(card.isTrue, false);
    expect(card.correctOrder, ['A', 'B']);
    expect(card.matchLeft, ['One', 'Two']);
    expect(card.matchRight, ['A', 'B']);
  });

  test(
    'shuffling keeps duplicate labels distinct and does not mutate content',
    () {
      const card = DiscoverCard(
        id: 'sample/card',
        sourceId: 'sample',
        format: 'concept',
        title: 'Title',
        front: 'Front',
      );
      for (final type in ['ordering', 'matching']) {
        final test = PracticeCard(
          id: 'sample/test',
          type: type,
          prompt: '?',
          correctOrder: const ['Repeat', 'Repeat', 'Finish'],
          matchLeft: const ['One', 'Two', 'Three'],
          matchRight: const ['Repeat', 'Repeat', 'Finish'],
        );
        final entry = PracticeEntry(card: card, test: test, level: 0);
        expect(entry.order.toSet(), {0, 1, 2});
        expect(entry.order, isNot([0, 1, 2]));
        expect(test.correctOrder, ['Repeat', 'Repeat', 'Finish']);
        expect(test.matchRight, ['Repeat', 'Repeat', 'Finish']);
        expect(entry.matches, [null, null, null]);
      }
    },
  );
}
