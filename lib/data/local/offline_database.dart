import 'dart:convert';

import 'package:drift/drift.dart';

/// One action waiting to be sent, oldest first.
typedef OutboxEntry = ({int id, String action, Map<String, dynamic> payload});

/// The phone's own database (drift, plain SQL): the Discover stock, the
/// Library lists, the Practice window, downloaded pictures and the outbox
/// ("to send" list).
/// One file per person, so two accounts on one phone never mix.
class OfflineDatabase extends GeneratedDatabase {
  OfflineDatabase(super.executor);

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      // cards: the Discover stock in feed order. The row is the whole
      // `discover_cards` row with its source and topics embedded.
      await customStatement(
        'create table cards (id text primary key, format text not null, '
        'media text, place integer not null, seen integer not null default 0, '
        'row text not null)',
      );
      // library: Liked and For later rows (with the card embedded), list = liked or later.
      await customStatement(
        'create table library (list text not null, card_id text not null, '
        'at text not null, media text, row text not null, '
        'primary key (list, card_id))',
      );
      // files: downloaded pictures, by media path.
      await customStatement(
        'create table files (path text primary key, file text not null, '
        'bytes integer not null)',
      );
      await customStatement(
        'create table outbox (id integer primary key autoincrement, '
        'action text not null, payload text not null, '
        'created_at text not null, tries integer not null default 0)',
      );
      await _createPractice();
      await _createCollections();
      await _createMedia();
    },
    onUpgrade: (_, from, _) async {
      if (from < 2) await _createPractice();
      if (from < 3) await _createCollections();
      if (from < 4) await _createMedia();
    },
  );

  Future<void> _createMedia() async {
    await customStatement(
      'alter table files add column is_media integer not null default 0',
    );
    await customStatement(
      "update files set is_media = 1 where path like '%.mp4' or path like '%.m4a' "
      "or path like '%.mp3' or path like '%.wav'",
    );
    await customStatement(
      'create table media_resume (card_id text primary key, seconds integer not null check(seconds >= 0))',
    );
  }

  Future<int?> resume(String id) async => (await customSelect(
    'select seconds from media_resume where card_id = ?',
    variables: [Variable(id)],
  ).getSingleOrNull())?.read<int>('seconds');

  Future<void> setResume(String id, int seconds) {
    if (seconds < 0) throw ArgumentError.value(seconds, 'seconds');
    return customStatement(
      'insert or replace into media_resume values (?, ?)',
      [id, seconds],
    );
  }

  Future<void> _createCollections() => customStatement(
    'create table collections (id text primary key, row text not null)',
  );

  Future<List<Map<String, dynamic>>> collections() async => [
    for (final r in await customSelect('select row from collections').get())
      jsonDecode(r.read<String>('row')) as Map<String, dynamic>,
  ];

  Future<void> putCollection(Map<String, dynamic> row) => customStatement(
    'insert or replace into collections (id, row) values (?, ?)',
    [row['id'], jsonEncode(row)],
  );

  Future<void> replaceCollections(List<Map<String, dynamic>> rows) =>
      transaction(() async {
        await customStatement('delete from collections');
        for (final row in rows) {
          await putCollection(row);
        }
      });

  Future<void> deleteCollection(String id) => transaction(() async {
    await customStatement('delete from collections where id = ?', [id]);
    for (final row in await library('liked')) {
      (row['collection_cards'] as List?)?.removeWhere(
        (c) => c['collection_id'] == id,
      );
      await putInLibrary('liked', row, 'liked_at');
    }
  });

  Future<void> _createPractice() async {
    // practice: the Practice window. Each Like's linked `practice_cards`
    // rows, each with its latest answer from Supabase (`practice_answers`).
    await customStatement(
      'create table practice (card_id text primary key, tests text not null)',
    );
    // answers: answers given on this phone. The id keeps a replay from
    // counting twice.
    await customStatement(
      'create table answers (id text primary key, test_id text not null, '
      'answered_at text not null)',
    );
  }

  // --- Discover stock ---

  /// Adds cards after the ones already in stock; cards already there keep their place.
  Future<void> addStock(List<Map<String, dynamic>> rows) =>
      transaction(() async {
        final top = await customSelect(
          'select coalesce(max(place), 0) as top from cards',
        ).getSingle();
        var place = top.read<int>('top');
        for (final r in rows) {
          await customStatement(
            'insert or ignore into cards (id, format, media, place, row) '
            'values (?, ?, ?, ?, ?)',
            [r['id'], r['format'], r['media_path'], ++place, jsonEncode(r)],
          );
        }
      });

  /// Unseen stock in feed order: [filter] is `mix` or one format.
  Future<List<Map<String, dynamic>>> stock({
    required String filter,
    required Set<String> exclude,
    required int limit,
  }) async {
    final rows = await customSelect(
      'select id, format, row from cards where seen = 0 order by place',
    ).get();
    return [
      for (final r in rows)
        if ((filter == 'mix' || r.read<String>('format') == filter) &&
            !exclude.contains(r.read<String>('id')))
          jsonDecode(r.read<String>('row')) as Map<String, dynamic>,
    ].take(limit).toList();
  }

  Future<List<String>> unseenIds() async => [
    for (final r in await customSelect(
      'select id from cards where seen = 0 order by place',
    ).get())
      r.read<String>('id'),
  ];

  Future<void> markSeen(Iterable<String> ids) async {
    for (final id in ids) {
      await customStatement('update cards set seen = 1 where id = ?', [id]);
    }
  }

  /// Seen cards are no use offline; a refill takes them out.
  Future<void> dropSeen() =>
      customStatement('delete from cards where seen = 1');

  /// A card's row from the stock or the Library, or null.
  Future<Map<String, dynamic>?> cardRow(String id) async {
    final stocked = await customSelect(
      'select row from cards where id = ?',
      variables: [Variable(id)],
    ).getSingleOrNull();
    if (stocked != null) {
      return jsonDecode(stocked.read<String>('row')) as Map<String, dynamic>;
    }
    final kept = await customSelect(
      'select row from library where card_id = ? limit 1',
      variables: [Variable(id)],
    ).getSingleOrNull();
    if (kept == null) return null;
    final row = jsonDecode(kept.read<String>('row')) as Map<String, dynamic>;
    return row['discover_cards'] as Map<String, dynamic>?;
  }

  // --- Library ---

  /// Replaces a whole list with fresh rows from Supabase.
  Future<void> replaceLibrary(
    String list,
    List<Map<String, dynamic>> rows,
    String atColumn,
  ) => transaction(() async {
    await customStatement('delete from library where list = ?', [list]);
    for (final r in rows) {
      await putInLibrary(list, r, atColumn);
    }
  });

  /// A `likes` or `saved_for_later` row with `discover_cards` embedded.
  Future<void> putInLibrary(
    String list,
    Map<String, dynamic> row,
    String atColumn,
  ) {
    final card = row['discover_cards'] as Map<String, dynamic>;
    return customStatement(
      'insert or replace into library (list, card_id, at, media, row) '
      'values (?, ?, ?, ?, ?)',
      [list, card['id'], row[atColumn], card['media_path'], jsonEncode(row)],
    );
  }

  /// Newest first.
  Future<List<Map<String, dynamic>>> library(String list) async => [
    for (final r in await customSelect(
      'select row from library where list = ? order by at desc',
      variables: [Variable(list)],
    ).get())
      jsonDecode(r.read<String>('row')) as Map<String, dynamic>,
  ];

  Future<Map<String, dynamic>?> libraryRow(String list, String cardId) async {
    final r = await customSelect(
      'select row from library where list = ? and card_id = ?',
      variables: [Variable(list), Variable(cardId)],
    ).getSingleOrNull();
    return r == null
        ? null
        : jsonDecode(r.read<String>('row')) as Map<String, dynamic>;
  }

  Future<void> removeFromLibrary(String list, String cardId) => customStatement(
    'delete from library where list = ? and card_id = ?',
    [list, cardId],
  );

  Future<int> libraryCount(String list) async => (await customSelect(
    'select count(*) as n from library where list = ?',
    variables: [Variable(list)],
  ).getSingle()).read<int>('n');

  // --- Practice window ---

  /// Replaces the window: liked card id → its linked tests.
  Future<void> replacePractice(Map<String, List<dynamic>> window) =>
      transaction(() async {
        await customStatement('delete from practice');
        for (final MapEntry(key: card, value: tests) in window.entries) {
          await customStatement(
            'insert into practice (card_id, tests) values (?, ?)',
            [card, jsonEncode(tests)],
          );
        }
      });

  Future<int> practiceCount() async => (await customSelect(
    "select count(*) as n from practice p join library l "
    "on l.list = 'liked' and l.card_id = p.card_id",
  ).getSingle()).read<int>('n');

  /// The window's unpaused Likes in timetable order, as the phone knows them
  /// now, with the full tests in place of the card's `practice_links`, so
  /// they read like the rows Practice gets from Supabase.
  Future<List<Map<String, dynamic>>> practiceRows() async {
    final rows = [
      for (final r in await customSelect(
        "select l.row, p.tests from practice p join library l "
        "on l.list = 'liked' and l.card_id = p.card_id",
      ).get())
        jsonDecode(r.read<String>('row')) as Map<String, dynamic>
          ..['discover_cards']['practice_links'] = [
            for (final t in jsonDecode(r.read<String>('tests')) as List)
              {'practice_cards': t},
          ],
    ]..removeWhere((r) => r['reviews_paused'] == true);
    DateTime due(Map<String, dynamic> r) =>
        DateTime.parse(r['next_review_at'] as String);
    return rows..sort((a, b) {
      final byDate = due(a).compareTo(due(b));
      return byDate != 0
          ? byDate
          : (a['discover_card_id'] as String).compareTo(
              b['discover_card_id'] as String,
            );
    });
  }

  /// The latest answer time of each test: from Supabase (kept with the
  /// window) or given on this phone, whichever is later.
  Future<Map<String, DateTime>> lastAnswers() async {
    final last = <String, DateTime>{};
    void keep(String test, String at) {
      final time = DateTime.parse(at);
      if (last[test]?.isBefore(time) ?? true) last[test] = time;
    }

    for (final r in await customSelect('select tests from practice').get()) {
      for (final t in jsonDecode(r.read<String>('tests')) as List) {
        for (final a in t['practice_answers'] as List? ?? const []) {
          keep(t['id'] as String, a['answered_at'] as String);
        }
      }
    }
    for (final r in await customSelect(
      'select test_id, answered_at from answers',
    ).get()) {
      keep(r.read<String>('test_id'), r.read<String>('answered_at'));
    }
    return last;
  }

  /// Keeps an answer ([p] holds the `record_answer` parameters) and moves the
  /// Like's timetable as the server does: the later `answered_at` wins. With
  /// [send] it also goes to the outbox. The same answer twice changes
  /// nothing; then it returns false.
  Future<bool> saveAnswer(Map<String, dynamic> p, {required bool send}) =>
      transaction(() async {
        final known = await customSelect(
          'select 1 from answers where id = ?',
          variables: [Variable(p['p_id'] as String)],
        ).getSingleOrNull();
        if (known != null) return false;
        final at = p['p_answered_at'] as String;
        await customStatement(
          'insert into answers (id, test_id, answered_at) values (?, ?, ?)',
          [p['p_id'], p['p_practice_card_id'], at],
        );
        final like = await libraryRow('liked', p['p_discover_card_id']);
        final last = like?['last_reviewed_at'] as String?;
        if (like != null &&
            (last == null ||
                DateTime.parse(at).isAfter(DateTime.parse(last)))) {
          like['review_level'] = p['p_review_level'];
          like['next_review_at'] = p['p_next_review_at'];
          like['last_reviewed_at'] = at;
          await putInLibrary('liked', like, 'liked_at');
        }
        if (send) await enqueue('answer', p);
        return true;
      });

  // --- Outbox ---

  /// Autoincrement survives a drained outbox, so a fetch detects intervening edits.
  Future<int> outboxRevision() async => (await customSelect(
    "select coalesce((select seq from sqlite_sequence where name = 'outbox'), 0) as n",
  ).getSingle()).read<int>('n');

  /// Keep a server snapshot only if no local action happened during its fetch.
  Future<bool> keepSnapshot(int revision, Future<void> Function() save) =>
      transaction(() async {
        if (await outboxRevision() != revision) return false;
        await save();
        return true;
      });

  Future<void> enqueue(String action, Map<String, dynamic> payload) =>
      customStatement(
        'insert into outbox (action, payload, created_at) values (?, ?, ?)',
        [action, jsonEncode(payload), DateTime.now().toUtc().toIso8601String()],
      );

  Future<int> pendingCount() async => (await customSelect(
    'select count(*) as n from outbox',
  ).getSingle()).read<int>('n');

  /// Sends waiting actions one by one, oldest first, and deletes each one sent.
  /// When the server refuses an action ([refused]), its tries go up and it is
  /// dropped after [maxTries]; any other error (no connection) stops until the
  /// next try. Sending twice is safe: the database actions are idempotent.
  /// Returns true when nothing is left to send.
  Future<bool> drain(
    Future<void> Function(OutboxEntry entry) send, {
    required bool Function(Object error) refused,
    int maxTries = 5,
  }) async {
    while (true) {
      final r = await customSelect(
        'select id, action, payload, tries from outbox order by id limit 1',
      ).getSingleOrNull();
      if (r == null) return true;
      final id = r.read<int>('id');
      try {
        await send((
          id: id,
          action: r.read<String>('action'),
          payload:
              jsonDecode(r.read<String>('payload')) as Map<String, dynamic>,
        ));
      } catch (e) {
        if (!refused(e)) return false;
        if (r.read<int>('tries') + 1 < maxTries) {
          await customStatement(
            'update outbox set tries = tries + 1 where id = ?',
            [id],
          );
          return false;
        }
      }
      await customStatement('delete from outbox where id = ?', [id]);
    }
  }

  // --- Pictures ---

  /// Library first, then unseen stock; media files have their own 20% budget.
  Future<Map<String, bool>> _references() async {
    final cards = [
      for (final list in ['liked', 'later'])
        for (final r in await library(list))
          r['discover_cards'] as Map<String, dynamic>,
      for (final r in await customSelect(
        'select row from cards where seen = 0 order by place',
      ).get())
        jsonDecode(r.read<String>('row')) as Map<String, dynamic>,
    ];
    return {
      for (final c in cards) ...{
        if (c['media_path'] case final String path)
          path: c['format'] == 'video' || c['format'] == 'audio',
        if (c['poster_path'] case final String path) path: false,
        if (c['captions_path'] case final String path) path: false,
      },
    };
  }

  Future<List<String>> missingMedia({bool isMedia = false}) async {
    final refs = await _references();
    final have = await localFiles(refs.keys);
    return [
      for (final e in refs.entries)
        if (e.value == isMedia && !have.containsKey(e.key)) e.key,
    ];
  }

  /// The downloaded file name of each path that has one.
  Future<Map<String, String>> localFiles(Iterable<String> paths) async {
    final wanted = paths.toSet();
    if (wanted.isEmpty) return const {};
    return {
      for (final r in await customSelect('select path, file from files').get())
        if (wanted.contains(r.read<String>('path')))
          r.read<String>('path'): r.read<String>('file'),
    };
  }

  Future<int> usedBytes() async => (await customSelect(
    'select coalesce(sum(bytes), 0) as n from files',
  ).getSingle()).read<int>('n');

  Future<int> mediaBytes() async => (await customSelect(
    'select coalesce(sum(bytes), 0) as n from files where is_media = 1',
  ).getSingle()).read<int>('n');

  /// A mode downgrade may evict downloaded media, even while its card stays.
  Future<List<String>> trimMedia(int cap) async {
    var used = await mediaBytes();
    final gone = <String>[];
    for (final f in await customSelect(
      'select * from files where is_media = 1 order by rowid',
    ).get()) {
      if (used <= cap ~/ 5) break;
      used -= f.read<int>('bytes');
      gone.add(f.read<String>('file'));
      await customStatement('delete from files where path = ?', [
        f.read<String>('path'),
      ]);
    }
    return gone;
  }

  Future<void> addFile(
    String path,
    String file,
    int bytes, {
    bool isMedia = false,
  }) => customStatement(
    'insert or replace into files (path, file, bytes, is_media) values (?, ?, ?, ?)',
    [path, file, bytes, isMedia ? 1 : 0],
  );

  /// Makes room for [bytes] more under [cap]. Already-seen cards leave first
  /// (oldest first), with pictures nothing uses any more. Unseen stock and
  /// Library pictures stay. Returns the file names to delete, and whether
  /// [bytes] now fit.
  Future<({List<String> gone, bool fits})> makeRoom(
    int bytes,
    int cap, {
    bool isMedia = false,
  }) => transaction(() async {
    var used = await usedBytes();
    var mediaUsed = await mediaBytes();
    bool fits() =>
        used + bytes <= cap && (!isMedia || mediaUsed + bytes <= cap ~/ 5);
    if (fits()) return (gone: <String>[], fits: true);
    final refs = await _references();
    final spare = await customSelect(
      'select f.path, f.file, f.bytes, f.is_media from files f '
      'order by (select min(place) from cards c where c.media = f.path) '
      'nulls first',
    ).get();
    final gone = <String>[];
    for (final f in spare) {
      if (fits()) break;
      if (refs.containsKey(f.read<String>('path'))) continue;
      used -= f.read<int>('bytes');
      if (f.read<int>('is_media') == 1) mediaUsed -= f.read<int>('bytes');
      gone.add(f.read<String>('file'));
      await customStatement('delete from files where path = ?', [
        f.read<String>('path'),
      ]);
      await customStatement('delete from cards where seen = 1 and media = ?', [
        f.read<String>('path'),
      ]);
    }
    return (gone: gone, fits: fits());
  });

  /// Atomically forgets activity and replaces old writes with a durable reset.
  Future<List<String>> clearActivity() => transaction(() async {
    final files = await clearDownloads();
    for (final table in [
      'outbox',
      'library',
      'collections',
      'answers',
      'media_resume',
    ]) {
      await customStatement('delete from $table');
    }
    // The new outbox id invalidates every snapshot fetched before the reset.
    await enqueue('delete_data', {});
    return files;
  });

  /// Online only: forgets downloads; personal activity and the outbox stay.
  Future<List<String>> clearDownloads() => transaction(() async {
    final files = [
      for (final r in await customSelect('select file from files').get())
        r.read<String>('file'),
    ];
    await customStatement('delete from files');
    await customStatement('delete from cards');
    await customStatement('delete from practice');
    return files;
  });
}
