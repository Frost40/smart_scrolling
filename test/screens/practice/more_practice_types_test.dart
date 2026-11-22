import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/core/theme/dark_mode.dart';
import 'package:smart_scrolling/core/theme/light_mode.dart';
import 'package:smart_scrolling/domain/models/practice_card.dart';
import 'package:smart_scrolling/screens/practice/practice_provider.dart';
import 'package:smart_scrolling/screens/practice/widgets/practice_card_view.dart';

import '../../data/repositories/fake_practice_repository.dart';

void main() {
  for (final dark in [false, true]) {
    for (final type in ['true_false', 'ordering', 'matching']) {
      testWidgets('$type controls in ${dark ? 'dark' : 'light'} mode', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = dark
            ? const Size(812, 375)
            : const Size(375, 812);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakePracticeRepository(count: 1);
        final e = PracticeEntry(
          card: repo.entries.first.card,
          level: 0,
          test: PracticeCard(
            id: 'test',
            type: type,
            prompt: 'Prompt',
            isTrue: false,
            correctOrder: const ['A', 'B', 'C'],
            matchLeft: const ['One', 'Two', 'Three'],
            matchRight: const ['A', 'B', 'C'],
            explanation: 'Explanation',
          ),
        );
        repo.entries.setAll(0, [e]);
        final tab = ValueNotifier(true);
        final p = PracticeProvider(
          repo,
          filter: type,
          saveFilter: (_) async {},
          isOpen: () => true,
          tabChanges: tab,
        );
        addTearDown(p.dispose);
        addTearDown(tab.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: p,
            child: MaterialApp(
              theme: dark ? darkMode() : lightMode(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.8),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(child: PracticeCardView(entry: e)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        if (type == 'true_false') {
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Check'),
                )
                .onPressed,
            isNull,
          );
          await tap(find.text('False'));
        } else if (type == 'ordering') {
          final before = List.of(e.order);
          final handle = find.byTooltip(
            'Drag ${e.test.correctOrder[e.order.first]}',
          );
          final drag = await tester.startGesture(tester.getCenter(handle));
          await tester.pump(const Duration(milliseconds: 100));
          await drag.moveBy(const Offset(0, 10));
          await tester.pump();
          await drag.moveBy(const Offset(0, 100));
          await tester.pumpAndSettle();
          await drag.up();
          await tester.pumpAndSettle();
          expect(e.order, isNot(before));
          // Buttons use the same move operation as dragging.
          for (var target = 0; target < e.order.length; target++) {
            while (e.order.indexOf(target) > target) {
              await tap(
                find.byTooltip('Move ${e.test.correctOrder[target]} up'),
              );
            }
          }
        } else {
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Check'),
                )
                .onPressed,
            isNull,
          );
          for (var i = 0; i < e.matches.length; i++) {
            await tap(find.byKey(Key('match-left-${e.card.id}-$i')));
            await tap(find.byKey(Key('match-right-${e.card.id}-$i')));
          }
        }
        await tap(find.text('Check'));
        expect(find.text('Correct'), findsOneWidget);
        expect(find.text('Explanation'), findsOneWidget);
        expect(e.saved, true);
        expect(e.answer!.step.level, 1);
        expect(repo.answers.length, 1);
        expect(find.text('Check'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
