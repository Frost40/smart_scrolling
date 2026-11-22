import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/offline_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:smart_scrolling/domain/models/practice_card.dart';
import 'package:smart_scrolling/screens/practice/practice_provider.dart';
import 'package:smart_scrolling/screens/practice/practice_screen.dart';
import 'package:smart_scrolling/screens/practice/widgets/practice_card_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_login.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('All new Practice types online, offline, then sync once', (
    tester,
  ) async {
    final account = await testLogin();
    expect(account.email, 'agent@smartscrolling.test');
    final client = Supabase.instance.client;
    final me = account.userId!;
    const cards = {
      'true_false': 'sample-curious-learner/retrieval-practice',
      'ordering': 'sample-curious-learner/interleaving',
      'matching': 'sample-curious-learner/curiosity-gap',
    };
    expect(
      (await client
          .from('sources')
          .select('is_sample')
          .eq('id', 'sample-curious-learner')
          .single())['is_sample'],
      true,
    );
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
    final discover = DiscoverRepository(client, offline);
    final practice = PracticeRepository(client, discover, offline);

    Future<void> clean() async {
      for (final id in cards.values) {
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
              .eq('discover_card_id', id);
        }
      }
      await client
          .from('profiles')
          .update({'practice_filter': 'mix'})
          .eq('user_id', me);
    }

    Future<void> prepare() async {
      for (final id in cards.values) {
        await client.rpc('like_card', params: {'p_card_id': id});
        await client
            .from('likes')
            .update({
              'next_review_at': DateTime.now()
                  .toUtc()
                  .subtract(const Duration(minutes: 1))
                  .toIso8601String(),
              'review_level': 0,
              'last_reviewed_at': null,
              'reviews_paused': false,
            })
            .eq('user_id', me)
            .eq('discover_card_id', id);
      }
    }

    Future<void> waitFor(bool Function() done, String what) async {
      for (var i = 0; i < 150; i++) {
        if (done()) return;
        await tester.pump(const Duration(milliseconds: 200));
      }
      fail('Timed out waiting for $what');
    }

    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 300));
    }

    await clean();
    await prepare();
    await tester.pumpWidget(
      App(
        account: account,
        offline: offline,
        discover: discover,
        practice: practice,
        explore: ExploreRepository(client),
        library: LibraryRepository(client, discover, offline),
      ),
    );
    net.add([ConnectivityResult.wifi]);
    await pumpUntil(tester, find.byKey(const Key('nav-1')));
    await tap(find.byKey(const Key('nav-1')));
    final p = tester
        .element(find.byType(PracticeScreen))
        .read<PracticeProvider>();
    await waitFor(() => p.loaded && !p.loading, 'Practice');
    final attempts = <PracticeAnswer>[];
    for (final disconnected in [false, true]) {
      if (disconnected) {
        await prepare();
        await offline.refill();
        net.add([ConnectivityResult.none]);
        await waitFor(() => !offline.online, 'offline mode');
      }
      for (final (type, card) in cards.entries.map((e) => (e.key, e.value))) {
        // Exercise the actual persisted filter menu for every type.
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump(const Duration(milliseconds: 300));
        await tap(find.byType(DropdownButtonFormField<String>));
        final label = type == 'true_false'
            ? 'True false'
            : '${type[0].toUpperCase()}${type.substring(1)}';
        await tap(find.text(label).last);
        await waitFor(() => p.filter == type && !p.loading, '$type filter');
        final e = p.entries.singleWhere((e) => e.card.id == card);
        final view = find.byWidgetPredicate(
          (w) => w is PracticeCardView && identical(w.entry, e),
        );
        if (type == 'true_false') {
          await tap(
            find.descendant(
              of: view,
              matching: find.text(e.test.isTrue! ? 'True' : 'False'),
            ),
          );
        } else if (type == 'ordering') {
          final first = e.test.correctOrder[e.order.first];
          final second = e.test.correctOrder[e.order[1]];
          final handle = find.byTooltip('Drag $first');
          await tester.ensureVisible(find.byTooltip('Drag $second'));
          await tester.pump(const Duration(milliseconds: 300));
          final before = List.of(e.order);
          final distance =
              tester.getCenter(find.byTooltip('Drag $second')).dy -
              tester.getCenter(handle).dy;
          final drag = await tester.startGesture(tester.getCenter(handle));
          await tester.pump(const Duration(milliseconds: 100));
          await drag.moveBy(const Offset(0, 10));
          await tester.pump();
          await drag.moveBy(Offset(0, distance * 2 - 10));
          await tester.pump(const Duration(milliseconds: 700));
          await drag.up();
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            e.order,
            isNot(before),
            reason: 'The drag handle must reorder on Android.',
          );
          for (var target = 0; target < e.order.length; target++) {
            while (e.order.indexOf(target) > target) {
              await tap(
                find.byTooltip('Move ${e.test.correctOrder[target]} up'),
              );
            }
          }
          // Down is also a working alternative to dragging.
          await tap(find.byTooltip('Move ${e.test.correctOrder.first} down'));
          await tap(find.byTooltip('Move ${e.test.correctOrder.first} up'));
        } else {
          for (var i = 0; i < e.matches.length; i++) {
            await tap(find.byKey(Key('match-left-$card-$i')));
            await tap(find.byKey(Key('match-right-$card-$i')));
          }
        }
        await tap(find.descendant(of: view, matching: find.text('Check')));
        await waitFor(() => e.saved, '$type answer');
        expect(e.answer!.result, 'correct');
        expect(e.answer!.step.level, 1);
        attempts.add(e.answer!);
        expect(
          find.descendant(of: view, matching: find.text('Correct')),
          findsOneWidget,
        );
      }
      if (!disconnected) {
        expect(await offline.flush(), true);
        final profile = await client
            .from('profiles')
            .select('practice_filter')
            .eq('user_id', me)
            .single();
        expect(profile['practice_filter'], 'matching');
      }
    }
    expect(offline.pending, greaterThanOrEqualTo(3));
    final beforeSync = await client
        .from('practice_answers')
        .select('id')
        .eq('user_id', me)
        .inFilter('discover_card_id', cards.values.toList());
    expect(beforeSync, hasLength(3));
    net.add([ConnectivityResult.mobile]);
    await waitFor(() => offline.pending == 0, 'answers to sync');
    final rows = await client
        .from('practice_answers')
        .select()
        .eq('user_id', me)
        .inFilter('discover_card_id', cards.values.toList());
    expect(rows, hasLength(6));
    for (final attempt in attempts) {
      final row = rows.singleWhere((r) => r['id'] == attempt.id);
      expect(row['result'], 'correct');
      expect(row['answer'], attempt.value);
      expect(row['practice_card_version'], attempt.entry.test.version);
    }
    for (final attempt in attempts.skip(3)) {
      final row = await client
          .from('likes')
          .select()
          .eq('user_id', me)
          .eq('discover_card_id', attempt.entry.card.id)
          .single();
      expect(row['review_level'], attempt.step.level);
      expect(DateTime.parse(row['next_review_at']), attempt.step.nextReviewAt);
    }
    expect(await offline.flush(), true);
    expect(
      await client
          .from('practice_answers')
          .select('id')
          .eq('user_id', me)
          .inFilter('discover_card_id', cards.values.toList()),
      hasLength(6),
    );
    await tester.pumpWidget(const SizedBox());
    await clean();
  });
}
