import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/data/local/offline_database.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = OfflineDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('v3 Library videos are counted when upgrading', () async {
    await db.close();
    db = OfflineDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('create table cards (format text, row text)');
          raw.execute('create table library (row text)');
          raw.execute(
            'create table files (path text primary key, file text, bytes integer)',
          );
          raw.execute('insert into library values (?)', [
            jsonEncode({
              'discover_cards': {'format': 'video', 'media_path': 'old.mp4'},
            }),
          ]);
          raw.execute("insert into files values ('old.mp4', 'old', 21)");
          raw.execute("insert into files values ('orphan.wav', 'orphan', 5)");
          raw.execute('pragma user_version = 3');
        },
      ),
    );
    expect(
      await db.mediaBytes(),
      26,
      reason: 'orphaned old media still consumes space',
    );
    expect(await db.trimMedia(100), ['old']);
  });

  test(
    'media includes whole files, posters and captions, pictures first',
    () async {
      await db.addStock([
        {
          'id': 's/video',
          'format': 'video',
          'media_path': 'video.mp4',
          'poster_path': 'poster.png',
          'captions_path': 'captions.vtt',
        },
      ]);
      expect(await db.missingMedia(), ['poster.png', 'captions.vtt']);
      expect(await db.missingMedia(isMedia: true), ['video.mp4']);
      await db.addFile('poster.png', 'poster', 10);
      expect(
        (await db.makeRoom(90, 100)).fits,
        true,
        reason: 'referenced posters must survive eviction',
      );
    },
  );

  test('audio and video share 20 percent, including a smaller mode', () async {
    await db.addStock([
      {'id': 's/kept', 'format': 'video', 'media_path': 'kept.mp4'},
    ]);
    await db.addFile('kept.mp4', 'kept', 19, isMedia: true);
    expect(
      (await db.makeRoom(2, 100, isMedia: true)).fits,
      false,
      reason:
          'referenced media stays, but new media cannot exceed the shared cap',
    );
    await db.clearDownloads();
    await db.addFile('v.mp4', 'v', 19, isMedia: true);
    expect(
      (await db.makeRoom(2, 100, isMedia: true)).fits,
      true,
      reason: 'unreferenced old media can leave',
    );
    expect(await db.mediaBytes(), 0);
    await db.addFile('v.mp4', 'v', 19, isMedia: true);
    final removed = await db.trimMedia(50);
    expect(removed, ['v']);
    expect(await db.mediaBytes(), lessThanOrEqualTo(10));
    expect((await db.makeRoom(21, 100, isMedia: true)).fits, false);
  });

  test('resume persists independently of the download stock', () async {
    await db.setResume('s/video', 12);
    await db.clearDownloads();
    expect(await db.resume('s/video'), 12);
    await db.setResume('s/video', 3);
    expect(await db.resume('s/video'), 3, reason: 'seeking backwards wins');
    expect(() => db.setResume('s/video', -1), throwsArgumentError);
  });
}
