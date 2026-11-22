import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/review_schedule.dart';

void main() {
  final at = DateTime.utc(2026, 10, 30, 12, 34, 56);
  const levels = {
    'correct': [1, 2, 3, 4, 4],
    'wrong': [0, 0, 0, 0, 0],
    'again': [0, 0, 0, 0, 0],
    'hard': [0, 1, 2, 3, 4],
    'good': [1, 2, 3, 4, 4],
    'easy': [2, 3, 4, 4, 4],
  };
  const days = [1, 3, 7, 14, 30];
  for (final result in levels.keys) {
    for (var level = 0; level < 5; level++) {
      test('$result at level $level', () {
        final step = nextReview(level: level, result: result, answeredAt: at);
        final expected = levels[result]![level];
        expect(step.level, expected);
        expect(step.nextReviewAt, at.add(Duration(days: days[expected])));
      });
    }
  }
  test('rejects unknown levels and results', () {
    for (final level in [-1, 5]) {
      expect(
        () => nextReview(level: level, result: 'good', answeredAt: at),
        throwsArgumentError,
      );
    }
    expect(
      () => nextReview(level: 0, result: 'skip', answeredAt: at),
      throwsArgumentError,
    );
  });
}
