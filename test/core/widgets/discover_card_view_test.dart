import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/light_mode.dart';
import 'package:smart_scrolling/core/widgets/discover_card_view.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';

void main() {
  var sourcePages = 0, reports = 0;

  Future<void> mount(WidgetTester tester, DiscoverCard card) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightMode(highContrast: false),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiscoverCardView(
              card: card,
              onSourcePage: () => sourcePages++,
              onReport: () => reports++,
            ),
          ),
        ),
      ),
    );
  }

  DiscoverCard card(String format, {String? speaker, String? back}) =>
      DiscoverCard(
        id: 'sample-a/$format',
        sourceId: 'sample-a',
        format: format,
        title: 'Title $format',
        front: 'Front $format',
        back: back,
        speaker: speaker,
        location: 'Chapter 1',
        level: 'intro',
        mediaAlt: 'A drawn curve',
        sourceTitle: 'Sample A',
        sourceKind: 'news',
        newspaper: 'The Sample Times',
        publishedOn: '2026-10-29',
      );

  testWidgets('quote: the speaker on the front', (tester) async {
    await mount(tester, card('quote', speaker: 'Ada Sample'));
    expect(find.text('“Front quote”'), findsOneWidget);
    expect(find.text('— Ada Sample'), findsOneWidget);
    expect(find.text('“'), findsNothing, reason: 'no stray quote mark');
  });

  testWidgets('news: the newspaper and the date', (tester) async {
    await mount(tester, card('news'));
    expect(find.text('News · The Sample Times · 2026-10-29'), findsOneWidget);
  });

  testWidgets('image without a link still says what it shows', (tester) async {
    await mount(tester, card('image'));
    expect(find.text('A drawn curve'), findsOneWidget);
  });

  testWidgets('unknown formats show title and front', (tester) async {
    await mount(tester, card('hologram'));
    expect(find.text('Title hologram'), findsOneWidget);
    expect(find.text('Front hologram'), findsOneWidget);
  });

  testWidgets(
    'myth: the myth on the front, the fact on the back with the essentials',
    (tester) async {
      await mount(tester, card('myth', back: 'The fact'));
      expect(find.text('Myth'), findsOneWidget);
      expect(find.text('Front myth'), findsOneWidget);
      expect(find.text('The fact'), findsNothing);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.text('Fact'), findsOneWidget);
      expect(find.text('The fact'), findsOneWidget);
      expect(find.text('Chapter 1'), findsOneWidget);
      expect(find.text('Sample A · news'), findsOneWidget);
      expect(find.text('Level: intro'), findsOneWidget);
      await tester.tap(find.text('Source page'));
      await tester.tap(find.text('Report a problem'));
      expect((sourcePages, reports), (1, 1));
      await tester.tap(find.text('The fact'));
      await tester.pumpAndSettle();
      expect(find.text('Front myth'), findsOneWidget);
    },
  );
}
