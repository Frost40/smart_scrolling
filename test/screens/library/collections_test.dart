import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/library_card.dart';
import 'package:smart_scrolling/screens/library/library_provider.dart';

import '../../data/repositories/fake_library_repository.dart';

void main() {
  test('collection feed filters liked cards; note and membership errors are visible', () async {
    final repo = FakeLibraryRepository();
    final tab = ValueNotifier(3);
    final p = LibraryProvider(repo, isOpen: () => true, tabChanges: tab);
    await p.refresh();
    expect(await p.createCollection('Samples'), true);
    expect(p.collections.values, ['Samples']);
    final id = p.collections.keys.single;
    final original = p.liked.first;
    repo.likedCards[0] = LibraryCard(
      card: original.card,
      at: original.at,
      note: 'private',
      collectionIds: {id},
    );
    await p.refresh();
    p.openCollection(id);
    expect(p.visible.single.card.id, original.card.id);
    expect(await p.saveNote(p.visible.single, 'new'), true);
    expect(repo.notes[original.card.id], 'new');
    expect(await p.setMembership(p.visible.single, id, false), true);
    expect(repo.memberships.single, (original.card.id, id, false));
    repo.fail = true;
    expect(await p.renameCollection(id, 'Other'), false);
    expect(p.actionError, isNotNull);
    expect(p.collections[id], 'Samples');
    repo.fail = false;
    expect(await p.deleteCollection(id), true);
    expect(p.collectionId, isNull);
    expect(p.visible.length, p.liked.length);
    p.dispose();
    tab.dispose();
  });
}
