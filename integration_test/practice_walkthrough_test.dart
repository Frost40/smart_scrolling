import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_login.dart';

// Prepares only the signed-in test user's sample-card review.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'Practice: due Like, flashcard, early multiple choice, saved filter',
    (tester) async {
      final account = await testLogin();
      final client = Supabase.instance.client;
      final me = account.userId!;
      const card = 'sample-curious-learner/retrieval-practice';
      final discover = DiscoverRepository(client, liveOffline);
      final repo = PracticeRepository(client, discover, liveOffline);
      Future<Map<String, dynamic>> like() => client
          .from('likes')
          .select()
          .eq('user_id', me)
          .eq('discover_card_id', card)
          .single();
      // Repeated Like preserves the host's due timetable.
      await discover.like(card);
      await liveOffline.flush();
      await client
          .from('practice_answers')
          .delete()
          .eq('user_id', me)
          .eq('discover_card_id', card);
      await client
          .from('likes')
          .update({
            'review_level': 0,
            'last_reviewed_at': null,
            'next_review_at': DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 1))
                .toIso8601String(),
            'reviews_paused': false,
          })
          .eq('user_id', me)
          .eq('discover_card_id', card);
      await discover.like(card);
      await liveOffline.flush();
      final initial = await like();
      expect(initial['review_level'], 0);
      expect(
        DateTime.parse(initial['next_review_at'] as String)
            .isAfter(DateTime.now()),
        false,
        reason: 'The sample Like is due before opening Practice.',
      );
      await client
          .from('profiles')
          .update({'practice_filter': 'flashcard'})
          .eq('user_id', me);

      // The repository must leave paused Likes out of both feed and counts.
      await client
          .from('likes')
          .update({'reviews_paused': true})
          .eq('user_id', me)
          .eq('discover_card_id', card);
      expect(
        (await repo.due(filter: 'flashcard')).entries
            .where((e) => e.card.id == card),
        isEmpty,
      );
      await client
          .from('likes')
          .update({'reviews_paused': false})
          .eq('user_id', me)
          .eq('discover_card_id', card);

      await tester.pumpWidget(
        App(
          offline: liveOffline,
          account: account,
          explore: ExploreRepository(client),
          discover: discover,
          library: LibraryRepository(client, discover, liveOffline),
          practice: repo,
        ),
      );
      await pumpUntil(tester, find.byKey(const Key('nav-1')));
      await tester.tap(find.byKey(const Key('nav-1')));
      await pumpUntil(tester, find.text('Reveal'));

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tap(find.text('Testing: Testing yourself'));
      await pumpUntil(tester, find.text('Close'));
      await tap(find.text('Close'));
      expect((await like())['last_reviewed_at'], isNull);
      await tap(find.text('Reveal'));
      expect((await like())['last_reviewed_at'], isNull);
      await tap(find.text('Good'));
      await pumpUntil(tester, find.text('Answer saved'));
      final after = await like();
      expect(after['review_level'], 1);
      expect(
        DateTime.parse(after['next_review_at'] as String)
            .difference(DateTime.parse(after['last_reviewed_at'] as String)),
        const Duration(days: 3),
      );

      // Change the persisted filter; an early test must advance the same Like.
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump(const Duration(milliseconds: 300));
      await tap(find.byType(DropdownButtonFormField<String>));
      await tap(find.text('Multiple choice').last);
      await pumpUntil(tester, find.text('Practice now'));
      await tap(find.text('Practice now'));
      await pumpUntil(tester, find.text('Check'));
      await tap(find.byKey(const Key('choice-$card-2')));
      await tap(find.text('Check'));
      await pumpUntil(tester, find.text('Answer saved'));
      expect(find.text('Correct'), findsOneWidget);
      expect(
        find.text(
          'Recalling from memory is a test, and tests strengthen memories.',
        ),
        findsOneWidget,
      );
      final early = await like();
      expect(early['review_level'], 2);
      expect(
        DateTime.parse(early['next_review_at'] as String)
            .difference(DateTime.parse(early['last_reviewed_at'] as String)),
        const Duration(days: 7),
      );
      final profile = await client
          .from('profiles')
          .select('practice_filter')
          .eq('user_id', me)
          .single();
      expect(profile['practice_filter'], 'multiple_choice');
      expect(
        (await client
                .from('practice_answers')
                .select('id')
                .eq('user_id', me)
                .eq('discover_card_id', card))
            .length,
        2,
      );

      // A Like removed elsewhere is a permanent failure, not an endless network retry.
      final next = (await repo.practiceNow(filter: 'flashcard')).entries
          .singleWhere((e) => e.card.id == card);
      final stale = repo.newAnswer(next, 'good', 'good');
      await client
          .from('likes')
          .delete()
          .eq('user_id', me)
          .eq('discover_card_id', card);
      await expectLater(
        repo.recordAnswer(stale),
        throwsA(isA<PracticeUnavailable>()),
      );

      // Sample-only cleanup, never owner data.
      await tester.pumpWidget(const SizedBox());
      for (final table in [
        'practice_answers',
        'likes',
        'seen_cards',
        'content_requests',
      ]) {
        await client
            .from(table)
            .delete()
            .eq('user_id', me)
            .eq('discover_card_id', card);
      }
      await client
          .from('profiles')
          .update({'practice_filter': 'mix'})
          .eq('user_id', me);
    },
  );
}
