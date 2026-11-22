import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/domain/models/library_card.dart';
import 'package:smart_scrolling/screens/library/library_provider.dart';
import 'package:smart_scrolling/screens/library/widgets/collections_section.dart';

import 'card_collections_test.dart';

void main() {
  late PlacesLibrary repo;
  late ValueNotifier<int> taps;
  late LibraryProvider p;

  Future<void> start(int folders) async {
    repo = PlacesLibrary();
    taps = ValueNotifier(0);
    p = LibraryProvider(
      repo,
      isOpen: () => true,
      tabChanges: taps,
      tabTaps: () => taps.value,
    );
    await p.refresh();
    for (var i = 0; i < folders; i++) {
      await p.createCollection('Folder $i');
    }
  }

  test(
    'up to 2 collections show at first, 3 or more fold; a tab tap resets',
    () async {
      await start(2);
      expect(p.collectionsShown, isTrue);
      await p.createCollection('Third');
      expect(p.collectionsShown, isTrue, reason: 'no jump while you edit');
      taps.value++;
      expect(p.collectionsShown, isFalse, reason: 'reopened: 3 fold');
      p.showCollections(true);
      taps.value++;
      expect(p.collectionsShown, isFalse, reason: 'back to the default');
    },
  );

  testWidgets('tap the open collection to leave it; drop a card to add it', (
    tester,
  ) async {
    await tester.runAsync(() => start(1));
    final folder = p.collections.keys.single;
    final card = p.liked.first;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: p,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const CollectionsSection(),
                LongPressDraggable<LibraryCard>(
                  data: card,
                  feedback: const SizedBox.square(dimension: 10),
                  child: const Text('drag me'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(Key('collection-$folder')));
    expect(p.collectionId, folder);
    await tester.pump();
    await tester.tap(find.byKey(Key('collection-$folder')));
    expect(p.collectionId, isNull);

    final drag = await tester.startGesture(
      tester.getCenter(find.text('drag me')),
    );
    await tester.pump(kLongPressTimeout);
    await drag.moveTo(tester.getCenter(find.byKey(Key('collection-$folder'))));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(repo.memberships.last, (card.card.id, folder, true));
    expect(find.text('Added to Folder 0'), findsOneWidget);
  });
}
