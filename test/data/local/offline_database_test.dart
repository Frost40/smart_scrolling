import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/data/local/offline_database.dart';

Map<String, dynamic> card(
  int i, {
  String format = 'concept',
  bool picture = true,
}) => {
  'id': 'sample/card-$i',
  'format': format,
  'media_path': picture ? 'cards/sample/card-$i/image.webp' : null,
  'title': 'Card $i',
};

class Refused implements Exception {}

void main() {
  late OfflineDatabase db;
  setUp(() => db = OfflineDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'delete activity clears cached lists, answers, resume and queued writes',
    () async {
      await db.addStock([card(1)]);
      await db.putCollection({'id': 'folder', 'name': 'Sample'});
      await db.setResume('sample/card-1', 23);
      await db.enqueue('like', {'card_id': 'sample/card-1'});
      final revision = await db.outboxRevision();
      await db.clearActivity();
      expect(await db.pendingCount(), 1);
      expect(
        await db.keepSnapshot(
          revision,
          () => db.putCollection({'id': 'stale'}),
        ),
        false,
      );
      final sent = <String>[];
      expect(
        await db.drain((e) async {
          sent.add(e.action);
          throw Exception('response lost after committing');
        }, refused: (_) => false),
        false,
      );
      expect(sent, ['delete_data']);
      expect(await db.pendingCount(), 1);
      await db.drain((e) async => sent.add(e.action), refused: (_) => false);
      expect(sent, ['delete_data', 'delete_data']);
      expect(await db.collections(), isEmpty);
      expect(await db.resume('sample/card-1'), isNull);
      expect(await db.unseenIds(), isEmpty);
      expect(await db.library('liked'), isEmpty);
      expect(await db.lastAnswers(), isEmpty);
    },
  );

  test('a stale server snapshot cannot overwrite an edit even after the outbox drains', () async {
    await db.putCollection({'id': 'folder', 'name': 'Before'});
    final revision = await db.outboxRevision();
    await db.transaction(() async {
      await db.putCollection({'id': 'folder', 'name': 'Edited while fetching'});
      await db.enqueue('collection_rename', {
        'id': 'folder',
        'name': 'Edited while fetching',
      });
    });
    await db.drain((_) async {}, refused: (_) => false);
    expect(await db.pendingCount(), 0);
    expect(
      await db.keepSnapshot(
        revision,
        () => db.replaceCollections([
          {'id': 'folder', 'name': 'Stale snapshot'},
        ]),
      ),
      false,
    );
    expect((await db.collections()).single['name'], 'Edited while fetching');
    expect(
      await db.keepSnapshot(
        await db.outboxRevision(),
        () => db.replaceCollections([
          {'id': 'folder', 'name': 'Fresh snapshot'},
        ]),
      ),
      true,
    );
    expect((await db.collections()).single['name'], 'Fresh snapshot');
  });

  group('outbox', () {
    test('sends in the order the actions were taken, each once', () async {
      for (final a in ['like', 'undo_like', 'save', 'seen']) {
        await db.enqueue(a, {'card_id': 'c'});
      }
      final sent = <String>[];
      final empty = await db.drain(
        (e) async => sent.add(e.action),
        refused: (_) => false,
      );
      expect(empty, true);
      expect(sent, ['like', 'undo_like', 'save', 'seen']);
      expect(await db.pendingCount(), 0);
      await db.drain((e) async => sent.add(e.action), refused: (_) => false);
      expect(sent, hasLength(4), reason: 'nothing is sent twice');
    });

    test('no connection: stops, keeps everything, and resends from the same action', () async {
      await db.enqueue('like', {'card_id': 'a'});
      await db.enqueue('save', {'card_id': 'b'});
      var online = false;
      final sent = <String>[];
      Future<void> send(OutboxEntry e) async {
        if (!online) throw Exception('no connection');
        sent.add('${e.action} ${e.payload['card_id']}');
      }

      expect(await db.drain(send, refused: (e) => e is Refused), false);
      expect(await db.drain(send, refused: (e) => e is Refused), false);
      expect(await db.pendingCount(), 2);
      online = true;
      expect(await db.drain(send, refused: (e) => e is Refused), true);
      expect(sent, ['like a', 'save b']);
    });

    test(
      'an action the server refuses is retried, then dropped after 5 tries',
      () async {
        await db.enqueue('like', {'card_id': 'gone'});
        await db.enqueue('save', {'card_id': 'b'});
        final sent = <String>[];
        Future<void> send(OutboxEntry e) async {
          if (e.payload['card_id'] == 'gone') throw Refused();
          sent.add(e.action);
        }

        for (var i = 0; i < 4; i++) {
          expect(await db.drain(send, refused: (e) => e is Refused), false);
          expect(sent, isEmpty, reason: 'later actions wait, so order holds');
        }
        expect(await db.drain(send, refused: (e) => e is Refused), true);
        expect(sent, ['save']);
      },
    );
  });

  group('space cap', () {
    test(
      'seen cards leave first, oldest first; unseen and Library pictures stay',
      () async {
        await db.addStock([card(1), card(2), card(3)]);
        await db.putInLibrary('liked', {
          'liked_at': '2026-10-31T10:00:00Z',
          'discover_cards': card(9),
        }, 'liked_at');
        for (final i in [1, 2, 3, 9]) {
          await db.addFile('cards/sample/card-$i/image.webp', 'f$i', 100);
        }
        await db.markSeen(['sample/card-2', 'sample/card-1']);

        // 400 used, cap 450: 250 more needs both seen cards to leave.
        final room = await db.makeRoom(250, 450);
        expect(room.fits, true);
        expect(room.gone, ['f1', 'f2']);
        expect(await db.usedBytes(), 200);
        expect(await db.cardRow('sample/card-1'), isNull);

        // Only an unseen card and a Library card are left: nothing more leaves.
        final full = await db.makeRoom(300, 450);
        expect(full.fits, false);
        expect(full.gone, isEmpty);
        expect(await db.usedBytes(), 200);
      },
    );

    test(
      'pictures are fetched for the Library first, then the stock in order',
      () async {
        await db.addStock([
          card(1),
          card(2, format: 'video'),
          card(3),
          card(4, picture: false),
        ]);
        await db.putInLibrary('later', {
          'saved_at': '2026-10-31T10:00:00Z',
          'discover_cards': card(9),
        }, 'saved_at');
        await db.addFile('cards/sample/card-1/image.webp', 'f1', 10);
        expect(await db.missingMedia(), [
          'cards/sample/card-9/image.webp',
          'cards/sample/card-3/image.webp',
        ]);
      },
    );

    test(
      'Online only clears the stock and pictures but keeps the outbox',
      () async {
        await db.addStock([card(1)]);
        await db.addFile('cards/sample/card-1/image.webp', 'f1', 10);
        await db.enqueue('like', {'card_id': 'sample/card-1'});
        expect(await db.clearDownloads(), ['f1']);
        expect(await db.unseenIds(), isEmpty);
        expect(await db.usedBytes(), 0);
        expect(await db.pendingCount(), 1);
      },
    );
  });

  test(
    'offline feed: unseen stock in order, by format, leaving out loaded cards',
    () async {
      await db.addStock([card(1), card(2, format: 'quote'), card(3), card(4)]);
      await db.addStock([card(1), card(5)]);
      await db.markSeen(['sample/card-3']);
      List<String> ids(List<Map<String, dynamic>> rows) => [
        for (final r in rows) r['id'] as String,
      ];
      expect(ids(await db.stock(filter: 'mix', exclude: {}, limit: 10)), [
        'sample/card-1',
        'sample/card-2',
        'sample/card-4',
        'sample/card-5',
      ]);
      expect(
        ids(
          await db.stock(
            filter: 'concept',
            exclude: {'sample/card-1'},
            limit: 1,
          ),
        ),
        ['sample/card-4'],
      );
    },
  );

  group('practice', () {
    Map<String, dynamic> like(String id, String next, {bool paused = false}) =>
        {
          'discover_card_id': id,
          'liked_at': '2026-10-01T10:00:00Z',
          'review_level': 1,
          'next_review_at': next,
          'last_reviewed_at': '2026-10-20T10:00:00Z',
          'reviews_paused': paused,
          'discover_cards': {'id': id, 'practice_links': []},
        };
    Map<String, dynamic> answer(String id, String at, {int level = 2}) => {
      'p_id': id,
      'p_practice_card_id': 's/flash',
      'p_practice_card_version': 1,
      'p_discover_card_id': 's/a',
      'p_answer': 'good',
      'p_result': 'good',
      'p_answered_at': at,
      'p_review_level': level,
      'p_next_review_at': '2026-11-30T10:00:00Z',
    };
    Future<Map<String, dynamic>> timetable() async =>
        (await db.libraryRow('liked', 's/a'))!;

    setUp(() async {
      await db.putInLibrary(
        'liked',
        like('s/a', '2026-11-02T10:00:00Z'),
        'liked_at',
      );
      await db.putInLibrary(
        'liked',
        like('s/b', '2026-11-01T10:00:00Z'),
        'liked_at',
      );
      await db.putInLibrary(
        'liked',
        like('s/paused', '2026-10-01T10:00:00Z', paused: true),
        'liked_at',
      );
      await db.replacePractice({
        for (final id in ['s/a', 's/b', 's/paused', 's/unliked'])
          id: [
            {
              'id': 's/flash',
              'type': 'flashcard',
              'practice_answers': [
                {'answered_at': '2026-10-20T10:00:00Z'},
              ],
            },
          ],
      });
    });

    test(
      'window rows: liked and unpaused, soonest first, tests in place',
      () async {
        final rows = await db.practiceRows();
        expect(rows.map((r) => r['discover_card_id']), ['s/b', 's/a']);
        expect(
          rows
              .first['discover_cards']['practice_links']
              .first['practice_cards']['type'],
          'flashcard',
        );
        expect(await db.practiceCount(), 3);
      },
    );

    test(
      'replaying the same answer gives one row and one action to send',
      () async {
        final a = answer(
          '00000000-0000-4000-8000-000000000001',
          '2026-10-31T10:00:00Z',
        );
        expect(await db.saveAnswer(a, send: true), true);
        expect(await db.saveAnswer(a, send: true), false);
        expect(await db.pendingCount(), 1);
        final sent = <OutboxEntry>[];
        await db.drain((e) async => sent.add(e), refused: (_) => false);
        expect(sent.single.action, 'answer');
        expect(sent.single.payload, a);
        final like = await timetable();
        expect(like['review_level'], 2);
        expect(like['next_review_at'], '2026-11-30T10:00:00Z');
        expect(like['last_reviewed_at'], '2026-10-31T10:00:00Z');
        expect(
          (await db.lastAnswers())['s/flash'],
          DateTime.utc(2026, 10, 31, 10),
        );
      },
    );

    test('the later answer wins the timetable, whatever the order', () async {
      await db.saveAnswer(
        answer('00000000-0000-4000-8000-000000000002', '2026-10-31T10:00:00Z'),
        send: true,
      );
      await db.saveAnswer(
        answer(
          '00000000-0000-4000-8000-000000000003',
          '2026-10-30T10:00:00Z',
          level: 4,
        ),
        send: true,
      );
      expect((await timetable())['review_level'], 2);
      expect(await db.pendingCount(), 2, reason: 'both answers are kept');
      expect(
        (await db.lastAnswers())['s/flash'],
        DateTime.utc(2026, 10, 31, 10),
      );
    });

    test(
      'an answer Supabase already has moves the timetable, sends nothing',
      () async {
        await db.saveAnswer(
          answer(
            '00000000-0000-4000-8000-000000000004',
            '2026-10-31T10:00:00Z',
          ),
          send: false,
        );
        expect(await db.pendingCount(), 0);
        expect((await timetable())['review_level'], 2);
      },
    );

    test('Online only forgets the window', () async {
      await db.clearDownloads();
      expect(await db.practiceRows(), isEmpty);
    });
  });

  test('a ticket 08 database gains the Practice tables', () async {
    final old = OfflineDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('create table cards (id text primary key)');
          raw.execute(
            'create table files (path text primary key, file text not null, bytes integer not null)',
          );
          raw.execute('pragma user_version = 1');
        },
      ),
    );
    await old.replacePractice({'s/a': []});
    expect(await old.lastAnswers(), isEmpty);
    await old.close();
  });
}
