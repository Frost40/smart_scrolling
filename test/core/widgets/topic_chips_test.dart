import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/widgets/topic_chips.dart';
import 'package:smart_scrolling/domain/models/topic.dart';

const topics = [
  Topic('physics', 'Physics'),
  Topic('optics', 'Optics and light', 'physics'),
  Topic('everyday-physics', 'Everyday physics', 'physics'),
  Topic('history', 'History'),
];

Widget chips(Set<String> chosen, void Function(String) onToggle) => MaterialApp(
  home: Scaffold(
    body: TopicChips(topics: topics, chosen: chosen, onToggle: onToggle),
  ),
);

bool selected(WidgetTester tester, String id) =>
    tester.widget<FilterChip>(find.byKey(Key('topic-$id'))).selected;

void main() {
  testWidgets('each name shows once; All and sub-topic taps report ids', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(chips({}, taps.add));
    for (final t in topics) {
      expect(find.text(t.name), findsOneWidget);
    }
    // The area's name is its card title; its "All" chip means the whole area.
    expect(find.bySemanticsLabel('All of Physics'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.tap(find.text('Optics and light'));
    await tester.tap(find.text('History'));
    expect(taps, ['physics', 'optics', 'history']);
  });

  testWidgets('a chosen area marks its sub-topics as chosen too', (
    tester,
  ) async {
    await tester.pumpWidget(chips({'physics'}, (_) {}));
    expect(selected(tester, 'physics'), isTrue);
    expect(selected(tester, 'optics'), isTrue);
    expect(selected(tester, 'history'), isFalse);
    // A ✓ replaces the + when chosen, so color is not the only sign and the
    // chip keeps its size.
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    final before = tester.getSize(find.byKey(const Key('topic-history')));
    await tester.pumpWidget(chips({'physics', 'history'}, (_) {}));
    expect(tester.getSize(find.byKey(const Key('topic-history'))), before);
  });

  testWidgets('a sub-topic of a chosen area can still be tapped', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(chips({'physics'}, taps.add));
    await tester.tap(find.text('Optics and light'));
    expect(taps, ['optics']);
  });
}
