import 'discover_card.dart';
import '../review_schedule.dart';

const practiceFilters = [
  'mix',
  'flashcard',
  'multiple_choice',
  'true_false',
  'ordering',
  'matching',
];

/// Whether a test of [type] belongs in the Practice [filter]. Mix holds the
/// types with controls, like `pick_test`'s Mix.
bool testMatches(String type, String filter) =>
    filter == 'mix' ? practiceFilters.skip(1).contains(type) : type == filter;

class PracticeCard {
  const PracticeCard({
    required this.id,
    required this.type,
    required this.prompt,
    this.version = 1,
    this.answer,
    this.choices = const [],
    this.correctChoice,
    this.isTrue,
    this.correctOrder = const [],
    this.matchLeft = const [],
    this.matchRight = const [],
    this.explanation,
  });

  factory PracticeCard.fromRow(Map<String, dynamic> row) => PracticeCard(
    id: row['id'] as String,
    type: row['type'] as String,
    prompt: row['prompt'] as String,
    version: row['version'] as int,
    answer: row['answer'] as String?,
    choices: List<String>.from(row['choices'] as List? ?? const []),
    correctChoice: row['correct_choice'] as int?,
    isTrue: row['is_true'] as bool?,
    correctOrder: List<String>.from(row['correct_order'] as List? ?? const []),
    matchLeft: List<String>.from(row['match_left'] as List? ?? const []),
    matchRight: List<String>.from(row['match_right'] as List? ?? const []),
    explanation: row['explanation'] as String?,
  );

  final String id, type, prompt;
  final int version;
  final String? answer, explanation;
  final List<String> choices;
  final int? correctChoice;
  final bool? isTrue;
  final List<String> correctOrder, matchLeft, matchRight;
}

/// One Like's test and the answer state retained when it scrolls out of view.
class PracticeEntry {
  PracticeEntry({required this.card, required this.test, required this.level})
    : order = List.generate(
        test.type == 'ordering'
            ? test.correctOrder.length
            : test.matchRight.length,
        (i) => i,
      )..shuffle(),
      matches = List.filled(test.matchLeft.length, null) {
    // Avoid opening a new test with the solution already displayed.
    if (order.length > 1 &&
        order.asMap().entries.every((e) => e.key == e.value)) {
      order.add(order.removeAt(0));
    }
  }

  DiscoverCard card;
  final PracticeCard test;
  final int level;
  int? choice;
  final List<int> order;
  final List<int?> matches;
  int? selectedLeft;
  bool revealed = false, saving = false, saved = false, unavailable = false;
  PracticeAnswer? answer;
  String? error;
}

/// An immutable attempt: retries keep its id, timestamp and timetable.
class PracticeAnswer {
  const PracticeAnswer({
    required this.id,
    required this.entry,
    required this.result,
    required this.value,
    required this.answeredAt,
    required this.step,
  });

  final String id, result;
  final PracticeEntry entry;
  final Object? value;
  final DateTime answeredAt;
  final ReviewStep step;
}

class PracticeBatch {
  const PracticeBatch(
    this.entries, {
    required this.due,
    required this.waiting,
    required this.hasMore,
  });

  final List<PracticeEntry> entries;
  final int due, waiting;
  final bool hasMore;
}
