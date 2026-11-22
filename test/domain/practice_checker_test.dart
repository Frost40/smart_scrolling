import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/practice_card.dart';
import 'package:smart_scrolling/domain/practice_checker.dart';

void main() {
  test('true/false accepts only the complete correct boolean', () {
    for (final correct in [true, false]) {
      final card = PracticeCard(
        id: 'tf',
        type: 'true_false',
        prompt: 'Statement',
        isTrue: correct,
      );
      expect(checkPracticeAnswer(card, correct), true);
      for (final wrong in [!correct, null, 0, 'true']) {
        expect(checkPracticeAnswer(card, wrong), false);
      }
    }
  });

  for (final type in ['ordering', 'matching']) {
    test('$type needs every item in the correct position', () {
      final card = PracticeCard(
        id: type,
        type: type,
        prompt: 'Prompt',
        correctOrder: const ['A', 'B', 'C'],
        matchLeft: const ['One', 'Two', 'Three'],
        matchRight: const ['A', 'B', 'C'],
      );
      expect(checkPracticeAnswer(card, ['A', 'B', 'C']), true);
      for (final wrong in [
        ['C', 'A', 'B'], // Entirely wrong.
        ['A', 'C', 'B'], // Partly right still counts as wrong.
        ['A', 'B'], ['A', 'B', null], ['A', 'B', 'C', 'D'], null,
      ]) {
        expect(checkPracticeAnswer(card, wrong), false);
      }
    });
  }

  test('multiple choice stays strict and unsupported types fail closed', () {
    const card = PracticeCard(
      id: 'mc',
      type: 'multiple_choice',
      prompt: '?',
      choices: ['A', 'B'],
      correctChoice: 1,
    );
    expect(checkPracticeAnswer(card, 1), true);
    expect(checkPracticeAnswer(card, 0), false);
    expect(checkPracticeAnswer(card, null), false);
    expect(checkPracticeAnswer(card, true), false);
    expect(
      checkPracticeAnswer(
        const PracticeCard(id: 'x', type: 'unknown', prompt: '?'),
        1,
      ),
      false,
    );
  });

  test('all five types participate in Mix and their own filters', () {
    for (final type in [
      'flashcard',
      'multiple_choice',
      'true_false',
      'ordering',
      'matching',
    ]) {
      expect(practiceFilters, contains(type));
      expect(testMatches(type, 'mix'), true);
      expect(testMatches(type, type), true);
      expect(testMatches(type, 'other'), false);
    }
    expect(testMatches('unknown', 'mix'), false);
  });
}
