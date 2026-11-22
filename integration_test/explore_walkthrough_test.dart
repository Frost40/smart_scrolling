import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_scrolling/data/services/local_store.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_login.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'onboarding, search, follow, request, hide, settings and unhide',
    (tester) async {
      final account = await testLogin();
      expect(account.email, 'agent@smartscrolling.test');
      final client = Supabase.instance.client;
      final me = account.userId!;
      final discover = DiscoverRepository(client, liveOffline);
      final explore = ExploreRepository(client);
      final topicsBefore = await client
          .from('user_topics')
          .select()
          .eq('user_id', me);
      final sourcesBefore = await client
          .from('user_sources')
          .select()
          .eq('user_id', me);
      final profileBefore = await client
          .from('profiles')
          .select()
          .eq('user_id', me)
          .single();
      const sourceId = 'sample-night-library';
      const title = 'City library opens a night reading room (sample)';
      final cards = await client
          .from('discover_cards')
          .select('id')
          .eq('source_id', sourceId);
      final ids = [for (final c in cards) c['id'] as String];
      final seenBefore = await client
          .from('seen_cards')
          .select()
          .eq('user_id', me)
          .inFilter('discover_card_id', ids);
      Future<void> tap(Finder f) async {
        await tester.ensureVisible(f);
        await tester.pump();
        await tester.tap(f);
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> waitFor(Finder f) async {
        for (var i = 0; i < 150 && f.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(f, findsWidgets);
      }

      try {
        for (final table in ['user_topics', 'user_sources']) {
          await client.from(table).delete().eq('user_id', me);
        }
        await client
            .from('seen_cards')
            .delete()
            .eq('user_id', me)
            .inFilter('discover_card_id', ids);
        await client
            .from('profiles')
            .update({'discover_filter': 'mix', 'preferred_level': null})
            .eq('user_id', me);
        // A first start finished on an earlier run is remembered on the phone.
        await LocalStore().clearState(me);
        await tester.pumpWidget(
          App(
            offline: liveOffline,
            account: account,
            discover: discover,
            explore: explore,
            library: LibraryRepository(client, discover, liveOffline),
            practice: PracticeRepository(client, discover, liveOffline),
          ),
        );
        await waitFor(find.text('Step 1 of 3'));
        // Psychology is in step 2 of 3 (lib/domain/topic_groups.dart).
        await tap(find.byKey(const Key('onboarding-next')));
        await tap(find.byKey(const Key('topic-psychology')));
        await tap(find.byKey(const Key('onboarding-next')));
        await tap(find.byKey(const Key('onboarding-continue')));
        await waitFor(find.byTooltip('Settings'));
        expect(await explore.topicChoices(), {'psychology': 'follow'});
        final topicSources = (await explore.sourcesByTopic('psychology'))
            .map((s) => s.id)
            .toSet();
        expect(
          (await discover.feed()).every(
            (c) => topicSources.contains(c.sourceId),
          ),
          true,
        );
        await tap(find.byKey(const Key('nav-2')));
        await waitFor(find.byKey(const Key('explore-search')));
        await tester.enterText(
          find.byKey(const Key('explore-search')),
          'd. reporter',
        );
        await waitFor(find.text(title));
        await tap(find.text(title));
        await waitFor(find.text('Add to my feed'));
        await tap(find.text('Add to my feed'));
        await waitFor(find.text('Added to your feed.'));
        expect(
          (await discover.feed()).any((c) => c.sourceId == sourceId),
          true,
        );
        await tap(find.text('Ask for more cards'));
        await tester.enterText(
          find.byKey(const Key('report-message')),
          'Ticket 07 sample walkthrough',
        );
        await tap(find.byKey(const Key('report-send')));
        await waitFor(find.textContaining('Your request is on'));
        final requests = await client
            .from('content_requests')
            .select('id')
            .eq('user_id', me)
            .eq('source_id', sourceId)
            .eq('kind', 'more_cards')
            .eq('message', 'Ticket 07 sample walkthrough');
        expect(requests, isNotEmpty);
        await tap(find.text('Hide'));
        await waitFor(find.text('Source hidden.'));
        expect(
          (await discover.feed()).any((c) => c.sourceId == sourceId),
          false,
        );
        // Hidden sources are unhidden on their own page (D46).
        await tap(find.text('Unhide'));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(await explore.sourceChoice(sourceId), isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final table in ['user_topics', 'user_sources']) {
          await client.from(table).delete().eq('user_id', me);
        }
        if (topicsBefore.isNotEmpty) {
          await client.from('user_topics').insert(topicsBefore);
        }
        if (sourcesBefore.isNotEmpty) {
          await client.from('user_sources').insert(sourcesBefore);
        }
        await client
            .from('profiles')
            .update({
              'discover_filter': profileBefore['discover_filter'],
              'preferred_level': profileBefore['preferred_level'],
            })
            .eq('user_id', me);
        await client
            .from('content_requests')
            .delete()
            .eq('user_id', me)
            .eq('source_id', sourceId)
            .eq('kind', 'more_cards')
            .eq('message', 'Ticket 07 sample walkthrough');
        await client
            .from('seen_cards')
            .delete()
            .eq('user_id', me)
            .inFilter('discover_card_id', ids);
        if (seenBefore.isNotEmpty) {
          await client.from('seen_cards').insert(seenBefore);
        }
      }
    },
  );
}
