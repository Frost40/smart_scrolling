import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/screens/explore/explore_provider.dart';
import 'package:smart_scrolling/screens/explore/widgets/topic_filter.dart';

import '../../../data/repositories/fake_explore_repository.dart';

void main() {
  testWidgets('an area opens on the first tap, is chosen on the second', (
    tester,
  ) async {
    final p = ExploreProvider(FakeExploreRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider.value(
            value: p,
            child: const TopicFilter(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tap(String id) async {
      await tester.tap(find.byKey(Key('explore-topic-$id')));
      await tester.pumpAndSettle();
    }

    bool on(String id) => tester
        .widget<ChoiceChip>(
          find.descendant(
            of: find.byKey(Key('explore-topic-$id')),
            matching: find.byType(ChoiceChip),
          ),
        )
        .selected;

    expect(find.byType(SubTopicStrip), findsNothing);
    await tap('learning');
    expect(find.byType(SubTopicStrip), findsOneWidget);
    expect(p.chosen, isEmpty);
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);

    // Second tap: the whole area, which marks its sub-topics as in Settings.
    await tap('learning');
    expect(p.chosen, {'learning'});
    expect(on('memory'), isTrue);
    expect(on('focus'), isTrue);

    // Dropping one sub-topic of a chosen area keeps the others.
    await tap('memory');
    expect(p.chosen, {'focus'});
    expect(on('learning'), isTrue, reason: 'area marked while a sub is chosen');
    await tap('focus');
    expect(p.chosen, isEmpty);
    expect(find.byType(SubTopicStrip), findsOneWidget, reason: 'stays open');

    await tap('learning');
    await tap('learning');
    expect(p.chosen, isEmpty);
    expect(find.byType(SubTopicStrip), findsNothing);
  });
}
