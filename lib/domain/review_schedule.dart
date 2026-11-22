class ReviewStep {
  const ReviewStep(this.level, this.nextReviewAt);

  final int level;
  final DateTime nextReviewAt;
}

/// D33: the one timetable rule, shared by online and future offline answers.
ReviewStep nextReview({
  required int level,
  required String result,
  required DateTime answeredAt,
}) {
  if (level < 0 || level > 4) throw ArgumentError.value(level, 'level');
  final next = switch (result) {
    'correct' || 'good' => (level + 1).clamp(0, 4),
    'easy' => (level + 2).clamp(0, 4),
    'hard' => level,
    'wrong' || 'again' => 0,
    _ => throw ArgumentError.value(result, 'result'),
  };
  return ReviewStep(
    next,
    answeredAt.toUtc().add(Duration(days: const [1, 3, 7, 14, 30][next])),
  );
}
