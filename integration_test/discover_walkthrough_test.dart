import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/core/theme/app_sizes.dart';
import 'package:smart_scrolling/core/widgets/discover_card_view.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_login.dart';

// Uses the debug test login only (A3-8) and the sample box, never the owner's account.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'Discover: scroll, like, later, unlike, flip, source page, hold-to-refresh, report',
    (tester) async {
      final account = await testLogin();
      final client = Supabase.instance.client;
      final me = account.userId!;

      // Start clean: the test person's own Discover marks only.
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
      }

      await clean();
      await tester.pumpWidget(
        App(
          offline: liveOffline,
          account: account,
          explore: ExploreRepository(client),
          discover: DiscoverRepository(client, liveOffline),
          library: LibraryRepository(
            client,
            DiscoverRepository(client, liveOffline),
            liveOffline,
          ),
          practice: PracticeRepository(
            client,
            DiscoverRepository(client, liveOffline),
            liveOffline,
          ),
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

      Future<int> count(String table, String cardId) async =>
          (await client
                  .from(table)
                  .select()
                  .eq('user_id', me)
                  .eq('discover_card_id', cardId))
              .length;
      Future<void> serverHas(String table, String cardId, int n) async {
        for (var i = 0; i < 50; i++) {
          if (await count(table, cardId) == n) return;
          await tester.pump(const Duration(milliseconds: 200));
        }
        fail('$table never had $n rows for $cardId');
      }

      String cardAt(int i) =>
          tester.widget<DiscoverCardView>(cardViews.at(i)).card.id;
      final feed = find.descendant(
        of: find.byKey(const PageStorageKey('discover-feed')),
        matching: find.byType(Scrollable),
      );

      // On the top card: pull down and hold for a new, different batch.
      final before = cardAt(0);
      final hold = await tester.startGesture(
        tester.getCenter(find.byKey(Key('card-$before'))),
      );
      for (var i = 0; i < 5; i++) {
        await hold.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const Key('refresh-ring')), findsOneWidget);
      await tester.pump(AppDurations.refreshHold);
      await tester.pump(const Duration(milliseconds: 200));
      await hold.up();
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (cardViews.evaluate().isNotEmpty && cardAt(0) != before) break;
      }
      final after = {
        for (var i = 0; i < cardViews.evaluate().length; i++) cardAt(i),
      };
      expect(after, isNotEmpty);
      // Ticket 18 allows older cards to return once fresh cards run out.
      expect(cardAt(0), isNot(before));

      final first = cardAt(0), second = cardAt(1);

      // Like, then tap again to undo it.
      await tap(find.byKey(Key('like-$first')));
      await serverHas('likes', first, 1);
      expect(find.text('Liked'), findsOneWidget);
      await tap(find.byKey(Key('like-$first')));
      await serverHas('likes', first, 0);

      // For later.
      await tap(find.byKey(Key('later-$second')));
      await serverHas('saved_for_later', second, 1);
      await serverHas('seen_cards', second, 1);

      // Flip, report a problem, open the source page.
      tester.state<ScrollableState>(feed.first).position.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 500));
      await tap(find.byKey(Key('card-$first')));
      expect(find.byKey(Key('source-$first')), findsOneWidget);
      await tap(find.byKey(Key('report-$first')));
      await tester.enterText(
        find.byKey(const Key('report-message')),
        'Walkthrough report',
      );
      await tap(find.byKey(const Key('report-send')));
      for (var i = 0; i < 50; i++) {
        final rows = await client
            .from('content_requests')
            .select()
            .eq('user_id', me)
            .eq('kind', 'problem')
            .eq('discover_card_id', first);
        if (rows.isNotEmpty) {
          expect(rows.single['message'], 'Walkthrough report');
          break;
        }
        await tester.pump(const Duration(milliseconds: 200));
      }
      final sourceTitle = tester
          .widget<DiscoverCardView>(cardViews.first)
          .card
          .sourceTitle;
      await tap(find.byKey(Key('source-$first')));
      await pumpUntil(tester, find.text(sourceTitle));
      await pumpUntil(tester, find.text('A few of its cards'));
      expect(find.byType(DiscoverCardView), findsWidgets);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));

      // Swipe right = Like.
      final third = cardAt(2);
      await tester.ensureVisible(find.byKey(Key('card-$third')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.timedDrag(
        find.byKey(Key('card-$third')),
        const Offset(200, 0),
        const Duration(milliseconds: 600),
      );
      await serverHas('likes', third, 1);

      // Scroll: cards half on screen become seen, in batches.
      for (var i = 0; i < 8; i++) {
        await tester.drag(feed.first, const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 500));
      }
      for (var i = 0; i < 50; i++) {
        final seen = await client.from('seen_cards').select().eq('user_id', me);
        if (seen.length >= 5) break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(
        (await client.from('seen_cards').select().eq('user_id', me)).length,
        greaterThanOrEqualTo(5),
      );
      // The new batch is all there is: the end of the feed says so.
      expect(find.text('You’ve seen everything here'), findsOneWidget);

      await clean();
      // Every published sample format is reachable through the real selector.
      for (final format in [
        'Concept',
        'Quote',
        'News',
        'Research',
        'Myth',
        'Image',
        'Video',
        'Audio',
      ]) {
        tester.state<ScrollableState>(feed.first).position.jumpTo(0);
        await tester.pump(const Duration(milliseconds: 500));
        await tap(find.byType(DropdownButtonFormField<String>));
        await tap(find.text(format).last);
        await pumpUntil(
          tester,
          find.byWidgetPredicate(
            (w) =>
                w is DiscoverCardView && w.card.format == format.toLowerCase(),
          ),
        );
      }
      await clean();
    },
  );
}
