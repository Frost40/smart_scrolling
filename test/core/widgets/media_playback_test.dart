import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/light_mode.dart';
import 'package:smart_scrolling/core/widgets/card_media.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Only the native decoder is replaced; the real controller and card run.
class Decoder extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  int created = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++created;
    positions[id] = Duration.zero;
    streams[id] = StreamController<VideoEvent>(onCancel: () async {});
    streams[id]!.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 20),
        size: const Size(320, 180),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    unawaited(streams[playerId]!.close());
  }

  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId]!;
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

void main() {
  late VideoPlayerPlatform original;
  late Decoder decoder;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    decoder = Decoder();
    VideoPlayerPlatform.instance = decoder;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(() {
    VideoPlayerPlatform.instance = original;
  });

  testWidgets(
    'retained controller reloads latest resume and recovers after a decoder error',
    (tester) async {
      var resume = 2, loads = 0;
      final writes = <int>[];
      const card = DiscoverCard(
        id: 's/v',
        sourceId: 's',
        format: 'video',
        title: 'Video',
        front: 'Sample',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: lightMode(highContrast: false),
          home: Scaffold(
            body: CardMedia(
              card: card,
              load: () async {
                loads++;
                return (
                  url: 'file:///sample.mp4',
                  captions: 'WEBVTT\n\n00:00.000 --> 00:20.000\nHello\n',
                  resume: resume,
                  save: (int seconds) async {
                    resume = seconds;
                    writes.add(seconds);
                  },
                );
              },
            ),
          ),
        ),
      );
      Future<void> play() async {
        await tester.tap(find.byTooltip('Play video'));
        await tester.pumpAndSettle();
      }

      VideoPlayerController controller() =>
          tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;
      await play();
      expect(controller().value.isPlaying, true);
      expect(controller().value.position.inSeconds, 2);
      expect(find.text('Hello'), findsOneWidget);
      mediaPlaybackChanges.value++;
      await tester.pumpAndSettle();
      resume = 7; // The same card played further in another retained tab.
      await play();
      expect(decoder.created, 1, reason: 'Play after Pause keeps the player');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(loads, 2);
      expect(controller().value.position.inSeconds, 7);
      decoder.streams[decoder.created]!.addError(
        PlatformException(code: 'VideoError', message: 'Decoder failed'),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(resume, 7, reason: 'an erroneous zero must not erase resume');
      expect(writes, isNot(contains(0)));
      await play();
      expect(loads, 3);
      expect(decoder.created, 2, reason: 'after an error the player reloads');
      expect(controller().value.isPlaying, true);
      expect(controller().value.position.inSeconds, 7);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(controller().value.isPlaying, false);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
