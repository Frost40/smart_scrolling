/// Complete personal totals; calendar boundaries use the phone's local time.
class ProgressSummary {
  ProgressSummary.fromRows(
    List<Map<String, dynamic>> likes,
    List<Map<String, dynamic>> answers, {
    required DateTime now,
    this.goal,
  }) : liked = likes.length {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final monday = DateTime(now.year, now.month, now.day - today.weekday + 1);
    final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);
    for (final like in likes) {
      final format =
          (like['discover_cards'] as Map?)?['format'] as String? ??
          'unavailable';
      formats.update(format, (n) => n + 1, ifAbsent: () => 1);
      if (like['reviews_paused'] != true &&
          DateTime.parse(like['next_review_at'] as String).isBefore(tomorrow)) {
        due++;
      }
    }
    final dates = <DateTime>{};
    for (final answer in answers) {
      final at = DateTime.parse(answer['answered_at'] as String).toLocal();
      if (!at.isBefore(monday) && at.isBefore(nextMonday) && !at.isAfter(now)) {
        answered++;
        dates.add(DateTime(at.year, at.month, at.day));
      }
    }
    days = dates.length;
  }

  final int liked;
  final int? goal;
  int due = 0, answered = 0, days = 0;
  final formats = <String, int>{};
}
