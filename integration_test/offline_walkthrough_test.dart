import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/core/widgets/discover_card_view.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/offline_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:smart_scrolling/screens/discover/discover_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_login.dart';

// Uses the debug test login only (A3-8) and the sample box. "Airplane mode"
// is the connection stream switching to none; the outbox does the rest.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Offline: download, airplane mode, scroll, like, later, back online once',
    (tester) async {
      final account = await testLogin();
      final client = Supabase.instance.client;
      final me = account.userId!;
      // This walkthrough uses its own engine; one connection per database file.
      await liveOffline.use(null);
      final net = StreamController<List<ConnectivityResult>>.broadcast();
      final offline = OfflineRepository(client, connectivity: net.stream);
      addTearDown(() async {
        await offline.refill();
        await offline.flush();
        await offline.use(null);
        offline.dispose();
        await net.close();
      });

      Future<void> clean() async {
        for (final table in [
          'seen_cards',
          'likes',
          'saved_for_later',
          'content_requests',
        ]) {
          await client.from(table).delete().eq('user_id', me);
        }
        await client
            .from('profiles')
            .update({'discover_filter': 'mix'})
            .eq('user_id', me);
        await client
            .from('devices')
            .update({'offline_mode': 'light', 'download_on_mobile_data': false})
            .eq('user_id', me);
      }

      Future<void> waitFor(bool Function() done, String what) async {
        for (var i = 0; i < 150; i++) {
          if (done()) return;
          await tester.pump(const Duration(milliseconds: 200));
        }
        fail('Timed out waiting for $what');
      }

      Future<List<String>> serverIds(String table) async => [
        for (final r
            in await client
                .from(table)
                .select('discover_card_id')
                .eq('user_id', me))
          r['discover_card_id'] as String,
      ];

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await clean();
      final discover = DiscoverRepository(client, offline);
      await tester.pumpWidget(
        App(
          account: account,
          offline: offline,
          explore: ExploreRepository(client),
          discover: discover,
          library: LibraryRepository(client, discover, offline),
          practice: PracticeRepository(client, discover, offline),
        ),
      );
      net.add([ConnectivityResult.wifi]);
      final cardViews = find.byType(DiscoverCardView);
      await pumpUntil(tester, cardViews);

      // Download: the stock and its pictures arrive on Wi-Fi.
      await waitFor(
        () =>
            !offline.downloading && offline.unseen > 0 && offline.pending == 0,
        'the download',
      );
      expect(
        offline.usedBytes,
        greaterThan(0),
        reason: 'pictures on the phone',
      );
      final stocked = offline.unseen;

      // Airplane mode.
      net.add([ConnectivityResult.none]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('You are offline'), findsOneWidget);

      final cards = tester
          .element(cardViews.first)
          .read<DiscoverProvider>()
          .cards;
      final first = cards[0].id, second = cards[1].id;
      final feed = find.descendant(
        of: find.byKey(const PageStorageKey('discover-feed')),
        matching: find.byType(Scrollable),
      );
      await tap(find.byKey(Key('like-$first')));
      await tester.scrollUntilVisible(
        find.byKey(Key('card-$second')),
        300,
        scrollable: feed.first,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tap(find.byKey(Key('later-$second')));
      for (var i = 0; i < 6; i++) {
        await tester.drag(feed.first, const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(cardViews, findsWidgets, reason: 'the stock keeps the feed going');
      expect(
        find.textContaining('will be sent when you are back online'),
        findsOneWidget,
      );
      expect(
        await serverIds('likes'),
        isEmpty,
        reason: 'nothing left the phone',
      );
      expect(await serverIds('saved_for_later'), isEmpty);
      final waiting = offline.pending;
      expect(waiting, greaterThanOrEqualTo(3));

      // The Library works offline too, from the phone.
      await tap(find.byKey(const Key('nav-3')));
      await pumpUntil(tester, find.byKey(Key('card-$first')));

      // Back online, on mobile data first as Android reports it: the outbox
      // is sent at once (downloads wait for Wi-Fi), each action exactly once.
      net.add([ConnectivityResult.mobile]);
      await waitFor(() => offline.pending == 0, 'the outbox to empty');
      net.add([ConnectivityResult.wifi]);
      expect(await serverIds('likes'), [first]);
      expect(await serverIds('saved_for_later'), [second]);
      final seen = await serverIds('seen_cards');
      expect(seen, containsAll([first, second]));
      expect(seen.toSet().length, seen.length);
      expect(await offline.flush(), true);
      expect(await serverIds('likes'), [
        first,
      ], reason: 'a second send adds nothing');
      expect(find.textContaining('You are offline'), findsNothing);
      expect(stocked, lessThanOrEqualTo(200), reason: 'Light keeps 200 cards');

      await tester.pumpWidget(const SizedBox());
      await clean();
    },
  );
}
