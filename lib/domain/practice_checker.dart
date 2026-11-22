import 'models/practice_card.dart';

/// D15: only a fully correct answer is right; partial credit is wrong.
bool checkPracticeAnswer(PracticeCard card, Object? answer) {
  if (card.type == 'true_false') {
    return answer is bool && answer == card.isTrue;
  }
  if (card.type == 'multiple_choice') {
    return answer is int &&
        answer >= 0 &&
        answer < card.choices.length &&
        answer == card.correctChoice;
  }
  final expected = switch (card.type) {
    'ordering' => card.correctOrder,
    'matching' => card.matchRight,
    _ => const <String>[],
  };
  return expected.isNotEmpty &&
      answer is List &&
      answer.length == expected.length &&
      expected.asMap().entries.every((e) => answer[e.key] == e.value);
}
