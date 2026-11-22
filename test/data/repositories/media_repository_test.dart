import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/data/local/offline_database.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/offline_repository.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MediaPhone implements OfflineRepository {
  MediaPhone(this.db, this.links);
  @override
  OfflineDatabase? db;
  @override
  bool online = false;
  final Map<String, String> links;
  @override
  Future<bool> canReadServer() async => false;
  @override
  Future<void> count() async {}
  @override
  Future<bool> flush() async => false;
  @override
  Future<void> queue(String action, Map<String, dynamic> payload) =>
      db!.enqueue(action, payload);
  @override
  Future<Map<String, String>> localMedia(Iterable<String> paths) async => {
    for (final e in links.entries)
      if (paths.contains(e.key)) e.key: e.value,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'local playback resumes; For later also queues position after Save',
    () async {
      final dir = await Directory.systemTemp.createTemp('media-repo');
      final captions = File('${dir.path}/captions.vtt');
      await captions.writeAsString(
        'WEBVTT\n\n00:00.000 --> 00:08.000\n[A tone]\n',
      );
      final db = OfflineDatabase(NativeDatabase.memory());
      final client = SupabaseClient(
        'http://localhost:54321',
        'public-test-key',
      );
      final phone = MediaPhone(db, {
        'v.mp4': 'file:///sample.mp4',
        'c.vtt': captions.uri.toString(),
      });
      final repo = DiscoverRepository(client, phone);
      const card = DiscoverCard(
        id: 's/v',
        sourceId: 's',
        format: 'video',
        title: 'Video',
        front: 'Sample',
        mediaPath: 'v.mp4',
        captionsPath: 'c.vtt',
      );
      try {
        await db.addStock([
          {
            'id': card.id,
            'source_id': 's',
            'format': 'video',
            'title': 'Video',
            'front': 'Sample',
            'media_path': 'v.mp4',
          },
        ]);
        final data = await repo.loadMedia(card);
        expect(data.url, 'file:///sample.mp4');
        expect(data.captions, contains('[A tone]'));
        expect(data.resume, 0);
        await data.save(3);
        expect(
          await db.pendingCount(),
          0,
          reason: 'unsaved resume stays on phone',
        );
        expect((await repo.loadMedia(card)).resume, 3);
        await repo.saveForLater(card.id);
        expect(
          (await db.libraryRow('later', card.id))!['resume_at_seconds'],
          3,
        );
        await (await repo.loadMedia(card)).save(5);
        expect(
          (await db.libraryRow('later', card.id))!['resume_at_seconds'],
          5,
        );
        final actions = <String>[];
        final seconds = <int>[];
        await db.drain((e) async {
          actions.add(e.action);
          if (e.action == 'resume') seconds.add(e.payload['seconds'] as int);
        }, refused: (_) => false);
        expect(actions, ['save', 'resume', 'resume']);
        expect(seconds, [3, 5]);
        final oldPlayer = await repo.loadMedia(card);
        phone.db = null;
        await oldPlayer.save(9);
        expect(
          await db.resume(card.id),
          5,
          reason: 'a player cannot write after its account closes',
        );
      } finally {
        await db.close();
        await client.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
