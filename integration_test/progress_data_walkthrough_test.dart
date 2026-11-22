import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/config/app_config.dart';
import 'package:smart_scrolling/data/repositories/app_state_repository.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:smart_scrolling/data/services/local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_login.dart';

// Host dismisses the two Android share sheets with Back when their markers print.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'progress, daily reminder, native sharing, export and confirmed delete',
    (tester) async {
      final account = await testLogin();
      expect(account.email, AppConfig.testLoginEmail);
      final client = Supabase.instance.client;
      final me = account.userId!;
      final discover = DiscoverRepository(client, liveOffline);
      final practice = PracticeRepository(client, discover, liveOffline);
      const card = 'sample-curious-learner/retrieval-practice';
      await liveOffline.flush();
      await client.rpc('like_card', params: {'p_card_id': card});
      await client
          .from('likes')
          .update({
            'next_review_at': DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
          })
          .eq('user_id', me)
          .eq('discover_card_id', card);
      await client.from('practice_answers').insert({
        'id': uuid(),
        'user_id': me,
        'practice_card_id': 'sample-curious-learner/recall-flash',
        'practice_card_version': 1,
        'discover_card_id': card,
        'result': 'good',
        'answered_at': DateTime.now().toUtc().toIso8601String(),
      });
      await tester.pumpWidget(
        App(
          account: account,
          discover: discover,
          library: LibraryRepository(client, discover, liveOffline),
          practice: practice,
          explore: ExploreRepository(client),
          offline: liveOffline,
        ),
      );
      await pumpUntil(tester, find.byKey(const Key('nav-1')));
      final context = tester.element(find.byKey(const Key('nav-1')));
      final state = context.read<AppStateRepository>();
      final router = context.read<GoRouter>();
      Future<void> tap(Finder target) async {
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            350,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await state.setWeeklyGoal(3);
      await tap(find.byKey(const Key('nav-1')));
      await tap(find.text('Progress'));
      await pumpUntil(tester, find.byKey(const Key('progress-liked')));
      final exported = await account.exportData();
      final likes = List<Map<String, dynamic>>.from(exported['likes'] as List);
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
      final answers = (exported['practice_answers'] as List)
          .where(
            (a) => !DateTime.parse(a['answered_at'] as String).isBefore(monday),
          )
          .toList();
      expect(
        tester.widget<Text>(find.byKey(const Key('progress-liked'))).data,
        '${likes.length}',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('progress-due'))).data,
        '${likes.where((l) => l['reviews_paused'] != true && DateTime.parse(l['next_review_at'] as String).isBefore(tomorrow)).length}',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('progress-answered'))).data,
        '${answers.length}',
      );
      expect(find.text('Weekly goal: 3 days'), findsOneWidget);
      router.pop();
      unawaited(router.push('/card?id=${Uri.encodeComponent(card)}'));
      await pumpUntil(tester, find.byKey(const Key('card-$card')));
      await tap(find.byKey(const Key('card-$card')));
      await tap(find.text('Share card'));
      debugPrint('TICKET13_CARD_SHARE_OPEN');
      // Native UI is outside Flutter; the host verifies it and dismisses it.
      await Future<void>.delayed(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 1));
      router.pop();
      unawaited(router.push('/settings'));
      await pumpUntil(tester, find.text('Daily reminder'));

      // The host grants POST_NOTIFICATIONS to the test app before this step.
      final next = DateTime.now().add(const Duration(minutes: 1));
      await state.setReminder(
        '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}',
      );
      final notifications = FlutterLocalNotificationsPlugin();
      expect(await notifications.pendingNotificationRequests(), hasLength(1));
      debugPrint('TICKET13_REMINDER_SCHEDULED');
      // Android batches inexact reminders; its delivery window can exceed 100s.
      for (var i = 0; i < 180; i++) {
        if ((await notifications.getActiveNotifications()).any(
          (n) => n.id == 13,
        )) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        await tester.pump();
      }
      expect(
        (await notifications.getActiveNotifications()).any((n) => n.id == 13),
        true,
      );
      debugPrint('TICKET13_REMINDER_FIRED');

      await tap(find.text('Export my data'));
      debugPrint('TICKET13_EXPORT_SHARE_OPEN');
      await Future<void>.delayed(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 1));
      final temp = await getTemporaryDirectory();
      final files = await temp
          .list(recursive: true)
          .where(
            (f) => f is File && f.path.endsWith('smartscrolling-data.json'),
          )
          .toList();
      expect(files, isNotEmpty);
      final data = jsonDecode(
        await File(files.last.path).readAsString(),
      ) as Map<String, dynamic>;
      expect(data.keys.toSet(), {
        'profiles',
        'devices',
        'user_topics',
        'user_sources',
        'likes',
        'saved_for_later',
        'seen_cards',
        'practice_answers',
        'collections',
        'collection_cards',
        'content_requests',
      });
      for (final rows in data.values) {
        for (final row in rows as List) {
          expect(row['user_id'], me);
        }
      }
      await tap(find.text('Delete all my activity'));
      await tap(find.text('Keep my activity'));
      expect((await account.exportData())['likes'], isNotEmpty);
      await tap(find.text('Delete all my activity'));
      await tap(find.text('Continue to final confirmation'));
      await tap(find.text('Keep my activity'));
      expect((await account.exportData())['likes'], isNotEmpty);
      await tap(find.text('Delete all my activity'));
      await tap(find.text('Continue to final confirmation'));
      await tap(find.text('Delete permanently'));
      await pumpUntil(tester, find.text('Skip'));
      expect(account.email, AppConfig.testLoginEmail);
      final after = await account.exportData();
      for (final entry in after.entries) {
        if (!['profiles', 'devices'].contains(entry.key)) {
          expect(entry.value, isEmpty, reason: entry.key);
        }
      }
      expect(await liveOffline.db!.pendingCount(), 0);
      expect(await liveOffline.db!.resume(card), isNull);
      expect(await notifications.pendingNotificationRequests(), isEmpty);
      debugPrint('TICKET13_COMPLETE');
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
