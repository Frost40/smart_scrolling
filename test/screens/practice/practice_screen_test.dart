import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/core/theme/dark_mode.dart';
import 'package:smart_scrolling/core/theme/light_mode.dart';
import 'package:smart_scrolling/core/theme/app_sizes.dart';
import 'package:smart_scrolling/screens/practice/practice_provider.dart';
import 'package:smart_scrolling/screens/practice/practice_screen.dart';

import '../../data/repositories/fake_practice_repository.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'flashcard, retry, concept, and choice work in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final repo = FakePracticeRepository(count: 2);
        final open = ValueNotifier(true);
        final p = PracticeProvider(
          repo,
          filter: 'mix',
          saveFilter: (_) async {},
          isOpen: () => true,
          tabChanges: open,
        );
        addTearDown(p.dispose);
        addTearDown(open.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: p,
            child: MaterialApp(
              theme: dark ? darkMode() : lightMode(),
              home: const Scaffold(body: PracticeScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await tap(find.text('Testing: Card 0'));
        expect(find.text('Front 0'), findsOneWidget);
        await tap(find.text('Close'));
        await tap(find.text('Reveal'));
        expect(find.text('Answer 0'), findsOneWidget);
        expect(repo.answers, isEmpty);
        repo.failSave = true;
        await tap(find.text('Good'));
        expect(find.text('Retry answer'), findsOneWidget);
        repo.failSave = false;
        await tap(find.text('Retry answer'));
        expect(find.text('Answer saved'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Check'), 200);
        await tap(find.byKey(const Key('choice-sample-b/card-1-1')));
        await tap(find.text('Check'));
        expect(find.text('Correct'), findsOneWidget);
        expect(find.text('Explanation 1'), findsOneWidget);
        expect(find.text('For later'), findsNothing);
        expect(find.text('Skip'), findsNothing);
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.text('Answer 0'), findsOneWidget);
        expect(p.entries.first.saved, true);
        // Hold-to-refresh removes the completed tests, rather than submitting anything.
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Question 0')),
        );
        await gesture.moveBy(const Offset(0, 50));
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump();
        await tester.pump(AppDurations.refreshHold);
        await tester.pump(AppDurations.refreshHold);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(p.entries, isEmpty);
        expect(find.text('Practice now'), findsOneWidget);
        expect(
          repo.answers.length,
          3,
          reason: 'One retry and two distinct answers',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
