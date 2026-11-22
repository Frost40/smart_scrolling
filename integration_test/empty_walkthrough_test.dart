import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_login.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Empty app after sample cleanup preserves real sources', (
    tester,
  ) async {
    final account = await testLogin();
    final client = Supabase.instance.client;
    expect(
      await client.from('sources').select('id').eq('is_sample', true),
      isEmpty,
    );
    expect(await client.from('discover_cards').select('id'), isEmpty);
    final discover = DiscoverRepository(client, liveOffline);
    await tester.pumpWidget(
      App(
        account: account,
        offline: liveOffline,
        discover: discover,
        library: LibraryRepository(client, discover, liveOffline),
        practice: PracticeRepository(client, discover, liveOffline),
        explore: ExploreRepository(client),
      ),
    );
    await pumpUntil(tester, find.text('You’ve seen everything here'));
    await tester.tap(find.byKey(const Key('nav-1')));
    await pumpUntil(tester, find.text('All caught up'));
    await tester.tap(find.byKey(const Key('nav-3')));
    await pumpUntil(
      tester,
      find.text('Nothing liked yet. Tap Like on a Discover card.'),
    );
    await tester.tap(find.byKey(const Key('library-tab-later')));
    await pumpUntil(
      tester,
      find.text(
        'Nothing saved for later yet. Tap For later on a Discover card.',
      ),
    );
    await tester.tap(find.byKey(const Key('nav-2')));
    await pumpUntil(tester, find.byKey(const Key('explore-search')));
    final real = await client
        .from('sources')
        .select('id,title')
        .eq('is_sample', false);
    expect(real.map((r) => r['id']).toSet(), {
      'happiness-advantage',
      'incepholorgb',
    });
    for (final source in real) {
      await tester.enterText(
        find.byKey(const Key('explore-search')),
        source['title'] as String,
      );
      await pumpUntil(tester, find.text(source['title'] as String));
    }
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('VERIFY_EMPTY'));
}
