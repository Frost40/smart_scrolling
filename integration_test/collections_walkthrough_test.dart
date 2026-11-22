import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/core/widgets/discover_card_view.dart';
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
    'collections, private notes, bidirectional See also and offline Undo',
    (tester) async {
      final account = await testLogin();
      final client = Supabase.instance.client;
      final me = account.userId!;
      final discover = DiscoverRepository(client, liveOffline);
      final library = LibraryRepository(client, discover, liveOffline);
      const a = 'sample-curious-learner/curiosity-gap';
      const b = 'sample-curious-learner/teach-to-learn';
      const name = 'Ticket 11 samples';

      Future<void> clean() async {
        await client.from('collections').delete().eq('user_id', me).inFilter(
          'name',
          [name, 'Renamed samples'],
        );
        await client.from('likes').delete().eq('user_id', me).inFilter(
          'discover_card_id',
          [a, b],
        );
      }

      Future<void> until(Future<bool> Function() check, String what) async {
        for (var i = 0; i < 100; i++) {
          if (await check()) return;
          await tester.pump(const Duration(milliseconds: 200));
        }
        fail('Never happened: $what');
      }

      Future<void> tap(Finder target) async {
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            300,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> top() async {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> saveText(String text) async {
        await pumpUntil(tester, find.byType(AlertDialog));
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          ),
          text,
        );
        await tap(find.text('Save'));
        await until(
          () async => find.byType(AlertDialog).evaluate().isEmpty,
          'saved dialog',
        );
      }

      Future<Map<String, dynamic>> like(String id) => client
          .from('likes')
          .select()
          .eq('user_id', me)
          .eq('discover_card_id', id)
          .single();

      await liveOffline.flush();
      await clean();
      for (final id in [a, b]) {
        await client.rpc('like_card', params: {'p_card_id': id});
      }
      await tester.pumpWidget(
        App(
          offline: liveOffline,
          account: account,
          explore: ExploreRepository(client),
          discover: discover,
          library: library,
          practice: PracticeRepository(client, discover, liveOffline),
        ),
      );
      await pumpUntil(tester, find.byKey(const Key('nav-3')));
      await tap(find.byKey(const Key('nav-3')));
      await pumpUntil(tester, find.byKey(const Key('new-collection')));

      await tap(find.byKey(const Key('new-collection')));
      await saveText(name);
      final folders = await library.collections();
      final folder = folders.entries.singleWhere((c) => c.value == name).key;
      for (final id in [a, b]) {
        await top();
        await tap(find.byKey(Key('card-menu-$id')));
        await tap(find.byKey(Key('membership-$folder')));
        await tap(find.byKey(const Key('collection-sheet-done')));
      }
      // The note is edited on the back of card a.
      Future<void> editNote() async {
        if (find.text('Edit note').hitTestable().evaluate().isEmpty) {
          await tap(find.byKey(const Key('card-$a')));
        }
        await tap(find.text('Edit note').last);
      }

      await top();
      await tap(find.byKey(Key('collection-$folder')));
      expect(
        (await library.liked()).where((c) => c.collectionIds.contains(folder)),
        hasLength(2),
      );

      await editNote();
      await saveText('My private sample note');
      await pumpUntil(tester, find.text('My private sample note'));
      await tap(find.byKey(const Key('related-$b')));
      await pumpUntil(tester, find.text('Card'));
      await pumpUntil(tester, find.byKey(const Key('card-$b')).hitTestable());
      expect(
        tester
            .widget<DiscoverCardView>(find.byType(DiscoverCardView).last)
            .card
            .id,
        b,
      );
      await tap(find.byKey(const Key('card-$b')));
      await tap(find.byKey(const Key('related-$a')));
      await pumpUntil(tester, find.byKey(const Key('card-$a')));
      expect(
        tester
            .widget<DiscoverCardView>(find.byType(DiscoverCardView).last)
            .card
            .id,
        a,
      );
      await tap(find.text('Edit note').last);
      await saveText('Edited through See also');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await pumpUntil(tester, find.text('Edited through See also'));

      await liveOffline.refill();
      final expectedLike = {...await like(a), 'note': 'Written offline'};
      final expectedPlaces = await client
          .from('collection_cards')
          .select()
          .eq('collection_id', folder)
          .order('discover_card_id');
      liveOffline.online = false;
      await editNote();
      await saveText('Written offline');
      await tap(find.byKey(const Key('remove-$a')));
      await tap(find.text('Undo'));
      final restored = (await library.liked()).singleWhere(
        (c) => c.card.id == a,
      );
      expect(restored.note, 'Written offline');
      expect(restored.collectionIds, contains(folder));
      expect(await liveOffline.db!.pendingCount(), greaterThanOrEqualTo(3));
      liveOffline.online = true;
      await until(liveOffline.flush, 'offline actions sent');
      expect(await like(a), expectedLike);
      expect(
        await client
            .from('collection_cards')
            .select()
            .eq('collection_id', folder)
            .order('discover_card_id'),
        expectedPlaces,
      );

      await top();
      await tap(find.byKey(Key('collection-menu-$folder')));
      await tap(find.text('Rename'));
      await saveText('Renamed samples');
      await tap(find.byKey(Key('collection-menu-$folder')));
      await tap(find.text('Delete collection'));
      await until(
        () async => !(await library.collections()).containsKey(folder),
        'collection deleted',
      );
      expect(
        (await library.liked()).where((c) => [a, b].contains(c.card.id)),
        hasLength(2),
      );

      // Source page also exposes the related titles without flipping a card.
      await top();
      await tap(find.byKey(const Key('card-$a')));
      await tap(find.byKey(const Key('source-$a')));
      await pumpUntil(tester, find.text('See also'));
      expect(find.byKey(const Key('related-$b')), findsWidgets);
      await tap(find.byKey(const Key('card-$a')));
      await tap(find.text('Edit note').first);
      await saveText('Edited through Source');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await pumpUntil(tester, find.text('Edited through Source'));
      await liveOffline.flush();
      await clean();
    },
  );
}
