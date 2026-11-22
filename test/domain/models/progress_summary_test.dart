import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/progress_summary.dart';

void main() {
  test('local week, overdue and paused Likes, formats and distinct days', () {
    final now = DateTime(2026, 10, 31, 12);
    Map<String, dynamic> like(
      String format,
      DateTime due, [
      bool paused = false,
    ]) => {
      'reviews_paused': paused,
      'next_review_at': due.toUtc().toIso8601String(),
      'discover_cards': {'format': format},
    };
    final summary = ProgressSummary.fromRows(
      [
        like('quote', DateTime(2026, 10, 29)),
        like('quote', DateTime(2026, 10, 31, 23, 59)),
        like('audio', DateTime(2026, 10, 31), true),
        like('concept', DateTime(2026, 11, 1)),
      ],
      [
        for (final at in [
          DateTime(2026, 10, 25, 23, 59),
          DateTime(2026, 10, 26),
          DateTime(2026, 10, 26, 15),
          DateTime(2026, 10, 30),
          DateTime(2026, 11, 2),
        ])
          {'answered_at': at.toUtc().toIso8601String()},
      ],
      now: now,
      goal: 3,
    );
    expect(summary.liked, 4);
    expect(summary.due, 2);
    expect(summary.answered, 3);
    expect(summary.days, 2);
    expect(summary.goal, 3);
    expect(summary.formats, {'quote': 2, 'audio': 1, 'concept': 1});
  });
  test('empty activity and no weekly goal are valid', () {
    final summary = ProgressSummary.fromRows(
      [],
      [],
      now: DateTime(2026, 11, 2),
    );
    expect(summary.liked, 0);
    expect(summary.days, 0);
    expect(summary.goal, isNull);
  });
}
