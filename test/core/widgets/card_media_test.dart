import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/light_mode.dart';
import 'package:smart_scrolling/core/widgets/discover_card_view.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';

void main() {
  testWidgets('media waits for Play and exposes a transcript on the back', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var loads = 0;
    const card = DiscoverCard(
      id: 's/v',
      sourceId: 's',
      format: 'video',
      title: 'Sample video',
      front: 'Watch the colors',
      transcript: 'Teal then amber.',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: lightMode(highContrast: false),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiscoverCardView(
              card: card,
              loadMedia: () async {
                loads++;
                throw StateError('Offline');
              },
            ),
          ),
        ),
      ),
    );
    expect(loads, 0);
    expect(find.byTooltip('Play video'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Seek video')), findsWidgets);
    await tester.tap(find.byTooltip('Play video'));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.textContaining('Could not play'), findsOneWidget);
    await tester.tap(find.text('Watch the colors'));
    await tester.pumpAndSettle();
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Teal then amber.'), findsOneWidget);
    semantics.dispose();
  });
}
