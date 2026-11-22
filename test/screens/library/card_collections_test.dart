import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/domain/models/library_card.dart';
import 'package:smart_scrolling/screens/library/library_provider.dart';
import 'package:smart_scrolling/screens/library/widgets/card_collections.dart';

import '../../data/repositories/fake_library_repository.dart';

/// Keeps each card's collections, like the real database does.
class PlacesLibrary extends FakeLibraryRepository {
  @override
  Future<void> setMembership(String cardId, String id, bool included) async {
    await super.setMembership(cardId, id, included);
    final i = likedCards.indexWhere((c) => c.card.id == cardId);
    final c = likedCards[i];
    likedCards[i] = LibraryCard(
      card: c.card,
      at: c.at,
      collectionIds: included
          ? {...c.collectionIds, id}
          : ({...c.collectionIds}..remove(id)),
    );
  }
}

void main() {
  testWidgets('Add to collection ticks a card in and out of a collection', (
    tester,
  ) async {
    final repo = PlacesLibrary();
    final p = LibraryProvider(
      repo,
      isOpen: () => true,
      tabChanges: ValueNotifier(3),
    );
    await p.refresh();
    await p.createCollection('Physics bits');
    final folder = p.collections.keys.single;
    final id = p.liked.first.card.id;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: p,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer<LibraryProvider>(
              builder: (_, p, _) => AddToCollection(entry: p.liked.first),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Collect'), findsOneWidget);
    await tester.tap(find.byKey(Key('card-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('membership-$folder')));
    await tester.pumpAndSettle();
    expect(repo.memberships.last, (id, folder, true));
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(Key('membership-$folder')))
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(Key('membership-$folder')));
    await tester.pumpAndSettle();
    expect(repo.memberships.last, (id, folder, false));
    await tester.tap(find.byKey(const Key('collection-sheet-done')));
    await tester.pumpAndSettle();
    expect(find.text('Collect'), findsOneWidget);
  });
}
