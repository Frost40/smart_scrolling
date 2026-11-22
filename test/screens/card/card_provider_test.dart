import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/screens/card/card_provider.dart';

import '../../data/repositories/fake_discover_repository.dart';
import '../../data/repositories/fake_library_repository.dart';

void main() {
  test('exact card loads; a failed note keeps an error, and unavailable cards retry', () async {
    final discover = FakeDiscoverRepository();
    final library = FakeLibraryRepository();
    final p = CardProvider(discover, library, 'sample-a/card-0');
    await p.load();
    expect(p.card?.id, 'sample-a/card-0');
    expect(p.entry, isNotNull);
    expect(await p.saveNote('Mine'), isNull);
    expect(library.notes[p.id], 'Mine');
    library.fail = true;
    expect(await p.saveNote('Still here'), isNotNull);
    expect(p.saving, false);
    discover.fail = true;
    await p.load();
    expect(p.error, isNotNull);
    library.fail = discover.fail = false;
    await p.load();
    expect(p.error, isNull);
    p.dispose();
  });
}
