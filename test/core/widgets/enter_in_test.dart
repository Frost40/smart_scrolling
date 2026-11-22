import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/light_mode.dart';
import 'package:smart_scrolling/core/widgets/discover_card_view.dart';
import 'package:smart_scrolling/core/widgets/enter_in.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    required bool still,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: lightMode(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );

  const card = DiscoverCard(
    id: 's/a',
    sourceId: 's',
    format: 'concept',
    title: 'Title',
    front: 'Front',
    back: 'Back',
    sourceTitle: 'S',
    sourceKind: 'book',
  );

  testWidgets('with reduce motion, entrances and the flip happen at once', (
    tester,
  ) async {
    await mount(tester, const EnterIn(child: Text('Hello')), still: true);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);

    await mount(tester, const DiscoverCardView(card: card), still: true);
    await tester.tap(find.text('Front'));
    await tester.pump();
    // One frame later the front is gone: no turning in between.
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Front'), findsNothing);
  });

  testWidgets('without reduce motion, the same things animate', (tester) async {
    await mount(tester, const EnterIn(child: Text('Hello')), still: false);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();

    await mount(tester, const DiscoverCardView(card: card), still: false);
    await tester.tap(find.text('Front'));
    await tester.pump();
    // Mid-turn both sides are still there.
    expect(find.text('Front'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Front'), findsNothing);
  });
}
