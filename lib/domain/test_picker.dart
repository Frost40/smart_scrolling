import 'models/practice_card.dart';

/// D32, the same rule as the database's `pick_test`, so the phone picks the
/// same test offline: a test never answered first, otherwise the one whose
/// latest answer is oldest; ties go by id. [lastAnswered] holds the person's
/// latest answer time for each test id, through any linked card.
/// The shared cases in `supabase/tests/pick_test_cases.sql` keep both alike.
PracticeCard? pickTest(
  Iterable<PracticeCard> tests,
  Map<String, DateTime> lastAnswered, {
  String filter = 'mix',
}) {
  final matching = tests.where((t) => testMatches(t.type, filter)).toList()
    ..sort((a, b) {
      final x = lastAnswered[a.id], y = lastAnswered[b.id];
      final byTime = x == null
          ? (y == null ? 0 : -1)
          : (y == null ? 1 : x.compareTo(y));
      // Ids are lowercase letters, digits, hyphens and one slash; for these
      // the database's text order is the same as Dart's.
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  return matching.isEmpty ? null : matching.first;
}
