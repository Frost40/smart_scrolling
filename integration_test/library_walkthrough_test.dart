import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/core/widgets/discover_card_view.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:smart_scrolling/screens/library/library_provider.dart';
import 'package:smart_scrolling/screens/library/widgets/filter_menu.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_login.dart';

// Uses the debug test login only (A3-8) and the sample box, never the owner's account.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'Library: liked and saved cards show up, Remove then Undo restores everything, pause reviews, search',
    (tester) async {
      final account = await testLogin();
      final client = Supabase.instance.client;
      final discover = DiscoverRepository(client, liveOffline);
      final me = account.userId!;

      Future<void> clean() async {
        for (final table in [
          'seen_cards',
          'collections', // takes its card list with it
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
      }

      await clean();
      await tester.pumpWidget(
        App(
          offline: liveOffline,
          account: account,
          explore: ExploreRepository(client),
          discover: discover,
          library: LibraryRepository(client, discover, liveOffline),
          practice: PracticeRepository(client, discover, liveOffline),
        ),
      );
      final cardViews = find.byType(DiscoverCardView);
      await pumpUntil(tester, cardViews);

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> until(Future<bool> Function() check, String what) async {
        for (var i = 0; i < 50; i++) {
          if (await check()) return;
          await tester.pump(const Duration(milliseconds: 200));
        }
        fail('Never happened: $what');
      }

      Future<Map<String, dynamic>?> row(String table, String id) => client
          .from(table)
          .select()
          .eq('user_id', me)
          .eq('discover_card_id', id)
          .maybeSingle();

      // The header (tabs, search) is the first item of the feed; scroll back to it.
      Future<void> toTop() async {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump(const Duration(milliseconds: 500));
      }

      String cardAt(int i) =>
          tester.widget<DiscoverCardView>(cardViews.at(i)).card.id;

      // Discover: like the top card and save the next one for later.
      final first = cardAt(0), savedFirst = cardAt(1);
      await tap(find.byKey(Key('like-$first')));
      await until(() async => await row('likes', first) != null, 'first like');
      await tap(find.byKey(Key('later-$savedFirst')));
      await until(
        () async => await row('saved_for_later', savedFirst) != null,
        'first save',
      );

      // Library opens with that like.
      await tap(find.byKey(const Key('nav-3')));
      await pumpUntil(tester, find.byKey(Key('remove-$first')));
      expect(find.byKey(Key('status-$first')), findsOneWidget);

      // Back in Discover, two more likes and one more save, made directly.
      await tap(find.byKey(const Key('nav-0')));
      final more = await discover.feed(limit: 4);
      expect(more.length, greaterThanOrEqualTo(3));
      final second = more[0].id, third = more[1].id, savedSecond = more[2].id;
      await discover.like(second);
      await discover.like(third);
      await discover.saveForLater(savedSecond);
      await liveOffline.flush();

      // The tab reloads when it opens: the newest like leads the feed.
      await tap(find.byKey(const Key('nav-3')));
      await pumpUntil(tester, find.byKey(Key('remove-$third')));
      await tester.scrollUntilVisible(
        find.byKey(Key('remove-$second')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(Key('remove-$second')), findsOneWidget);
      await toTop();

      // Give the newest like a note, a timetable and a collection to restore.
      await client
          .from('likes')
          .update({
            'note': 'my note',
            'review_level': 2,
            'next_review_at': '2030-01-15T09:00:00+00:00',
          })
          .eq('user_id', me)
          .eq('discover_card_id', third);
      final collection = await client
          .from('collections')
          .insert({'name': 'Walkthrough'})
          .select()
          .single();
      await client.from('collection_cards').insert({
        'collection_id': collection['id'],
        'discover_card_id': third,
      });
      final before = (await row('likes', third))!;
      final placed = await client
          .from('collection_cards')
          .select()
          .eq('discover_card_id', third);
      await tap(find.byKey(const Key('library-tab-later')));
      await tap(find.byKey(const Key('library-tab-liked')));

      // Remove from Liked: the like and its collection place are gone.
      await tap(find.byKey(Key('remove-$third')));
      await pumpUntil(tester, find.text('Removed from Liked'));
      expect(find.byKey(Key('remove-$third')), findsNothing);
      expect(await row('likes', third), isNull);
      expect(
        await client
            .from('collection_cards')
            .select()
            .eq('discover_card_id', third),
        isEmpty,
      );

      // Undo brings back the same timetable, note and collection place.
      await tap(find.text('Undo'));
      await until(() async => await row('likes', third) != null, 'undo');
      await pumpUntil(tester, find.byKey(Key('remove-$third')));
      expect(await row('likes', third), before);
      expect(
        await client
            .from('collection_cards')
            .select()
            .eq('discover_card_id', third),
        placed,
      );

      // Pause and resume reviews.
      await tap(find.byKey(Key('pause-$third')));
      await until(
        () async => (await row('likes', third))!['reviews_paused'] == true,
        'pause',
      );
      expect(find.text('Reviews paused'), findsOneWidget);
      await tap(find.byKey(Key('pause-$third')));
      await until(
        () async => (await row('likes', third))!['reviews_paused'] == false,
        'resume',
      );
      expect(find.text('Reviews paused'), findsNothing);

      // Search narrows the feed to the matching card.
      final title = tester
          .widget<DiscoverCardView>(
            find.ancestor(
              of: find.byKey(Key('card-$third')),
              matching: find.byType(DiscoverCardView),
            ),
          )
          .card
          .title;
      await toTop();
      await tester.enterText(find.byKey(const Key('library-search')), title);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(Key('remove-$third')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('library-search')),
        'zzzz-nothing',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Nothing matches. Try other words or filters.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('library-search')), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 500));

      // Exercise all three filter controls against the saved sample cards.
      final library = tester
          .element(find.byKey(const Key('library-search')))
          .read<LibraryProvider>();
      for (final label in ['Format', 'Topic', 'Source']) {
        await toTop();
        final menu = find.byWidgetPredicate(
          (w) => w is FilterMenu && w.label == label,
        );
        final option = tester.widget<FilterMenu>(menu).options.entries.first;
        final expected = library.liked
            .where(
              (c) => switch (label) {
                'Format' => c.card.format == option.key,
                'Topic' => c.topics.containsKey(option.key),
                _ => c.card.sourceId == option.key,
              },
            )
            .map((c) => c.card.id)
            .toList();
        await tap(menu);
        await tap(find.text(option.value).last);
        expect(library.visible.map((c) => c.card.id), expected);
        await pumpUntil(tester, find.byKey(Key('card-${expected.first}')));
        await tap(menu);
        await tap(find.text('All').last);
        expect(library.visible, hasLength(library.liked.length));
      }

      // For later: both saved cards, Remove then Undo.
      await toTop();
      await tap(find.byKey(const Key('library-tab-later')));
      await pumpUntil(tester, find.byKey(Key('remove-$savedSecond')));
      await tester.scrollUntilVisible(
        find.byKey(Key('remove-$savedFirst')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(Key('remove-$savedFirst')), findsOneWidget);
      await toTop();
      expect(find.byKey(Key('pause-$savedSecond')), findsNothing);
      final saved = (await row('saved_for_later', savedSecond))!;
      await tap(find.byKey(Key('remove-$savedSecond')));
      await pumpUntil(tester, find.text('Removed from For later'));
      expect(await row('saved_for_later', savedSecond), isNull);
      await tap(find.text('Undo'));
      await until(
        () async => await row('saved_for_later', savedSecond) != null,
        'undo of For later',
      );
      expect(await row('saved_for_later', savedSecond), saved);

      await clean();
    },
  );
}
