import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/core/widgets/card_media.dart';
import 'package:smart_scrolling/core/widgets/discover_card_view.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/offline_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'test_login.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Media: play, pause, leave, resume, captions and downloaded playback',
    (tester) async {
      final account = await testLogin();
      final client = Supabase.instance.client;
      final me = account.userId!;
      const videoId = 'sample-media/sample-video';
      const audioId = 'sample-media/sample-tone';
      await liveOffline.use(null);
      final net = StreamController<List<ConnectivityResult>>.broadcast();
      final offline = OfflineRepository(client, connectivity: net.stream);
      final discover = DiscoverRepository(client, offline);
      for (final table in ['seen_cards', 'saved_for_later', 'likes']) {
        await client.from(table).delete().eq('user_id', me).inFilter(
          'discover_card_id',
          [videoId, audioId],
        );
      }
      // Follows left by other runs could hide the media cards; put them back after.
      final followsBefore = {
        for (final table in ['user_topics', 'user_sources'])
          table: await client.from(table).select().eq('user_id', me),
      };
      for (final table in followsBefore.keys) {
        await client.from(table).delete().eq('user_id', me);
      }
      await client
          .from('profiles')
          .update({'discover_filter': 'video'})
          .eq('user_id', me);
      await client
          .from('devices')
          .update({'offline_mode': 'light'})
          .eq('user_id', me);

      Future<void> waitFor(bool Function() done, String what) async {
        for (var i = 0; i < 150; i++) {
          if (done()) return;
          await tester.pump(const Duration(milliseconds: 200));
        }
        fail('Timed out waiting for $what');
      }

      Future<void> tap(Finder finder) async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(finder.first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      GoRouter router() =>
          tester.element(find.byType(DiscoverCardView).first).read<GoRouter>();
      VideoPlayerController player() =>
          tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller;

      try {
        await tester.pumpWidget(
          App(
            account: account,
            discover: discover,
            offline: offline,
            explore: ExploreRepository(client),
            library: LibraryRepository(client, discover, offline),
            practice: PracticeRepository(client, discover, offline),
          ),
        );
        net.add([ConnectivityResult.wifi]);
        await pumpUntil(tester, find.byType(DiscoverCardView));
        final source = await discover.source('sample-media');
        await discover.saveForLater(videoId);
        await discover.saveForLater(audioId);
        await offline.flush();
        await offline.refill();
        await waitFor(
          () => !offline.downloading && offline.pending == 0,
          'media download',
        );
        final video = source.cards.firstWhere((c) => c.id == videoId);
        final audio = source.cards.firstWhere((c) => c.id == audioId);
        final files = await offline.localMedia([
          video.mediaPath!,
          audio.mediaPath!,
          video.captionsPath!,
          audio.captionsPath!,
          video.posterPath!,
          audio.posterPath!,
        ]);
        expect(
          files.length,
          6,
          reason: 'whole media files plus both posters and captions',
        );
        expect(
          await offline.db!.mediaBytes(),
          lessThanOrEqualTo(offline.mode.capBytes ~/ 5),
        );

        unawaited(router().push('/card?id=${Uri.encodeComponent(videoId)}'));
        await tester.pump(const Duration(milliseconds: 500));
        await pumpUntil(tester, find.byTooltip('Play video'));
        expect(
          find.byType(VideoPlayer),
          findsNothing,
          reason: 'poster before Play; no autoplay',
        );
        await tap(find.byTooltip('Play video'));
        await waitFor(
          () =>
              find.byType(VideoPlayer).evaluate().isNotEmpty &&
              player().value.isPlaying,
          'video playback',
        );
        await waitFor(
          () => player().value.position.inSeconds >= 2,
          'two seconds of video',
        );
        expect(find.text('[Silent sample video]'), findsOneWidget);
        await tap(find.byTooltip('Pause video'));
        final paused = player().value.position.inSeconds;
        expect(paused, greaterThanOrEqualTo(2));
        await tester.pump(const Duration(milliseconds: 500));
        await offline.flush();
        final saved = await client
            .from('saved_for_later')
            .select('resume_at_seconds')
            .eq('user_id', me)
            .eq('discover_card_id', videoId)
            .single();
        expect(saved['resume_at_seconds'], greaterThanOrEqualTo(2));

        unawaited(router().push('/card?id=${Uri.encodeComponent(audioId)}'));
        await tester.pump(const Duration(milliseconds: 500));
        await pumpUntil(tester, find.byTooltip('Play audio'));
        await tap(find.byTooltip('Play audio'));
        await waitFor(
          () => find.byTooltip('Pause audio').evaluate().isNotEmpty,
          'audio playback',
        );
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('[A steady tone]'), findsOneWidget);
        mediaPlaybackChanges.value++;
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byTooltip('Play audio'),
          findsOneWidget,
          reason: 'navigation pauses audio',
        );
        expect(await offline.db!.resume(audioId), greaterThanOrEqualTo(1));

        net.add([ConnectivityResult.none]);
        await tester.pump(const Duration(milliseconds: 300));
        router().pop();
        await tester.pump(const Duration(milliseconds: 500));
        await pumpUntil(tester, find.byTooltip('Play video'));
        await tap(find.byTooltip('Play video'));
        await waitFor(
          () =>
              find.byType(VideoPlayer).evaluate().isNotEmpty &&
              player().value.isPlaying,
          'offline playback',
        );
        expect(
          player().dataSource,
          startsWith('file:'),
          reason: 'native decoder reads the completed download',
        );
        expect(player().value.position.inSeconds, greaterThanOrEqualTo(paused));
        final resumed = player().value.position;
        await waitFor(
          () =>
              player().value.position >
              resumed + const Duration(milliseconds: 500),
          'offline progress',
        );
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          player().value.isPlaying,
          false,
          reason: 'backgrounding stops sound',
        );
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tap(find.text(video.front));
        await pumpUntil(tester, find.text('Transcript'));
        expect(find.text(video.transcript!), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        net.add([ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 300));
        await offline.flush();
        await offline.use(null);
        offline.dispose();
        await net.close();
        await client
            .from('profiles')
            .update({'discover_filter': 'mix'})
            .eq('user_id', me);
        for (final MapEntry(key: table, value: rows) in followsBefore.entries) {
          if (rows.isNotEmpty) await client.from(table).insert(rows);
        }
      }
    },
  );
}
