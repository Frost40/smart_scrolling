import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/domain/models/progress_summary.dart';
import 'package:smart_scrolling/screens/progress/progress_provider.dart';
import 'package:smart_scrolling/screens/progress/progress_screen.dart';

import '../../data/repositories/fake_practice_repository.dart';

class ProgressPractice extends FakePracticeRepository {
  bool fail = false;
  @override
  Future<ProgressSummary> progress() async {
    if (fail) throw StateError('offline');
    return ProgressSummary.fromRows(
      [],
      [],
      now: DateTime(2026, 10, 31),
      goal: 3,
    );
  }
}

void main() {
  testWidgets(
    'Progress fits both themes at large text and retries offline reads',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final repo = ProgressPractice();
      final p = ProgressProvider(repo);
      addTearDown(p.dispose);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: p,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: const ProgressScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('progress-liked')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      repo.fail = true;
      await p.load();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('progress-liked')), findsNothing);
      expect(find.textContaining('Connect to the internet'), findsOneWidget);
      repo.fail = false;
      await tester.ensureVisible(find.text('Refresh progress'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh progress'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('progress-liked')), findsOneWidget);
    },
  );
}
