import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/offline_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:smart_scrolling/domain/models/practice_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_login.dart';

// Uses the debug test login only (A3-8) and the sample box. "Airplane mode"
// is the connection stream switching to none; the outbox does the rest.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'Offline Practice: download the window, answer 3 in airplane mode, sync',
    (tester) async {
      final account = await testLogin();
      final client = Supabase.instance.client;
      final me = account.userId!;
      // Sample cards with a flashcard each.
      const cards = [
        'sample-curious-learner/retrieval-practice',
        'sample-everyday-light/light-speed',
        'sample-night-library/night-room-opens',
      ];
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
          'practice_answers',
          'seen_cards',
          'likes',
          'saved_for_later',
          'content_requests',
        ]) {
          await client.from(table).delete().eq('user_id', me);
        }
        await client
            .from('profiles')
            .update({'practice_filter': 'mix'})
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

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<List<Map<String, dynamic>>> serverLikes() async =>
          List<Map<String, dynamic>>.from(
            await client
                .from('likes')
                .select(
                  'discover_card_id, review_level, next_review_at, '
                  'last_reviewed_at',
                )
                .eq('user_id', me)
                .order('discover_card_id'),
          );

      await clean();
      // Three Likes, due a minute apart so their order is fixed.
      final now = DateTime.now().toUtc();
      for (var i = 0; i < cards.length; i++) {
        await client.rpc('like_card', params: {'p_card_id': cards[i]});
        await client
            .from('likes')
            .update({
              'next_review_at': now
                  .subtract(Duration(minutes: 3 - i))
                  .toIso8601String(),
            })
            .eq('user_id', me)
            .eq('discover_card_id', cards[i]);
      }
      await client
          .from('profiles')
          .update({'practice_filter': 'flashcard'})
          .eq('user_id', me);

      final discover = DiscoverRepository(client, offline);
      final practice = PracticeRepository(client, discover, offline);
      await tester.pumpWidget(
        App(
          account: account,
          offline: offline,
          explore: ExploreRepository(client),
          discover: discover,
          library: LibraryRepository(client, discover, offline),
          practice: practice,
        ),
      );
      net.add([ConnectivityResult.wifi]);
      await pumpUntil(tester, find.byKey(const Key('nav-1')));

      // Download: the Practice window arrives on Wi-Fi.
      await waitFor(
        () => !offline.downloading && offline.practice == cards.length,
        'the Practice window',
      );

      // Airplane mode.
      net.add([ConnectivityResult.none]);
      await tester.pump(const Duration(milliseconds: 300));
      await tap(find.byKey(const Key('nav-1')));
      await pumpUntil(tester, find.text('Reveal'));
      expect(find.text('3 due · 0 waiting for tests'), findsOneWidget);

      // The phone picks the same test as the database would.
      final phone = await practice.due(filter: 'flashcard');
      expect(phone.entries.map((e) => e.card.id), cards);
      for (final e in phone.entries) {
        final row = await client.rpc(
          'pick_test',
          params: {'p_discover_card_id': e.card.id, 'p_filter': 'flashcard'},
        );
        expect(e.test.id, (row as Map)['id']);
        expect(PracticeCard.fromRow(Map.from(row)).prompt, e.test.prompt);
      }

      for (var i = 0; i < cards.length; i++) {
        await tap(find.text('Reveal').first);
        // After an answer the card shows "Good" as plain text; tap the button.
        await tap(find.widgetWithText(OutlinedButton, 'Good').first);
      }

      // The timetable moved on the phone right away.
      final phoneLikes = <String, Map<String, dynamic>>{};
      for (final id in cards) {
        for (var i = 0; i < 50; i++) {
          phoneLikes[id] = (await offline.db!.libraryRow('liked', id))!;
          if (phoneLikes[id]!['review_level'] == 1) break;
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(phoneLikes[id]!['review_level'], 1, reason: id);
      }
      expect(offline.pending, greaterThanOrEqualTo(3));
      expect(
        await client.from('practice_answers').select('id').eq('user_id', me),
        isEmpty,
        reason: 'nothing left the phone',
      );
      expect((await practice.due(filter: 'flashcard')).entries, isEmpty);

      // Back online: each answer arrives once and Supabase matches the phone.
      net.add([ConnectivityResult.mobile]);
      await waitFor(() => offline.pending == 0, 'the outbox to empty');
      final answers = await client
          .from('practice_answers')
          .select('id, discover_card_id, result')
          .eq('user_id', me);
      expect(answers, hasLength(3));
      expect(answers.map((a) => a['result']).toSet(), {'good'});
      for (final like in await serverLikes()) {
        final mine = phoneLikes[like['discover_card_id']]!;
        expect(like['review_level'], mine['review_level']);
        for (final column in ['next_review_at', 'last_reviewed_at']) {
          expect(
            DateTime.parse(like[column] as String),
            DateTime.parse(mine[column] as String),
            reason: column,
          );
        }
      }
      expect(await offline.flush(), true);
      expect(
        await client.from('practice_answers').select('id').eq('user_id', me),
        hasLength(3),
        reason: 'a second send adds nothing',
      );

      await tester.pumpWidget(const SizedBox());
      await clean();
    },
  );
}
