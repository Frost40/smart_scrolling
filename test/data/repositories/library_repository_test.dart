import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/data/local/offline_database.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/offline_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PhoneOnly implements OfflineRepository {
  PhoneOnly(this.db, {this.online = false});
  @override
  final OfflineDatabase db;
  @override
  final bool online;
  @override
  bool get resetting => false;
  @override
  Future<bool> canReadServer() async => online;
  @override
  Future<List<Map<String, dynamic>>> library(String list) => db.library(list);
  @override
  Future<Map<String, String>> localMedia(Iterable<String> paths) async => {};
  @override
  Future<void> queue(String action, Map<String, dynamic> payload) =>
      db.enqueue(action, payload);
  @override
  Future<void> count() async {}
  @override
  Future<bool> flush() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DisconnectedClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      throw const SocketException('Disconnected Wi-Fi');
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late OfflineDatabase db;
  late LibraryRepository repo;
  late SupabaseClient client;
  setUp(() async {
    db = OfflineDatabase(NativeDatabase.memory());
    client = SupabaseClient('http://localhost:54321', 'public-test-key');
    final offline = PhoneOnly(db);
    repo = LibraryRepository(
      client,
      DiscoverRepository(client, offline),
      offline,
    );
    await db.putInLibrary('liked', {
      'discover_card_id': 'sample/a',
      'liked_at': '2026-10-31T10:00:00Z',
      'review_level': 3,
      'next_review_at': '2026-11-14T10:00:00Z',
      'reviews_paused': true,
      'collection_cards': [],
      'discover_cards': {
        'id': 'sample/a',
        'source_id': 'sample',
        'title': 'Sample A',
        'front': 'Sample front',
        'format': 'concept',
      },
    }, 'liked_at');
  });
  tearDown(() async {
    await db.close();
    await client.dispose();
  });

  test('reported-online transport failure still opens cached cards and creates a first collection', () async {
    await HttpOverrides.runZoned(() async {
      final disconnected = SupabaseClient(
        'http://localhost:54321',
        'public-test-key',
      );
      final offline = PhoneOnly(db, online: true);
      final discover = DiscoverRepository(disconnected, offline);
      final library = LibraryRepository(disconnected, discover, offline);
      final cached = {
        ...(await db.libraryRow('liked', 'sample/a'))!['discover_cards']
            as Map<String, dynamic>,
        'likes': [
          {'note': 'Stale embedded note'},
        ],
      };
      await db.addStock([cached]);
      await library.saveNote('sample/a', 'Fresh phone note');
      expect((await discover.card('sample/a')).note, 'Fresh phone note');
      await library.saveNote('sample/a', '');
      expect(
        (await discover.cardsFrom([cached], fromCache: true)).single.note,
        isNull,
      );
      expect(await library.collections(), isEmpty);
      final id = await library.createCollection('First offline');
      expect(await library.collections(), {id: 'First offline'});
      await disconnected.dispose();
    }, createHttpClient: (_) => DisconnectedClient());
  });

  test('offline collection CRUD, notes and memberships survive Unlike and Undo exactly', () async {
    final id = await repo.createCollection('  My samples  ');
    expect(await repo.collections(), {id: 'My samples'});
    await repo.setMembership('sample/a', id, true);
    await repo.saveNote('sample/a', 'Private sample note');
    final before = await db.libraryRow('liked', 'sample/a');
    final liked = (await repo.liked()).single;
    expect(liked.note, 'Private sample note');
    expect(liked.collectionIds, {id});
    final removed = await repo.unlike('sample/a');
    expect(await repo.liked(), isEmpty);
    await repo.restoreLike(removed);
    expect(await db.libraryRow('liked', 'sample/a'), before);
    await repo.renameCollection(id, 'Renamed');
    expect(await repo.collections(), {id: 'Renamed'});
    await repo.deleteCollection(id);
    final kept = (await repo.liked()).single;
    expect(kept.collectionIds, isEmpty);
    expect(kept.note, 'Private sample note');
    expect(kept.reviewsPaused, true);
    await repo.saveNote('sample/a', '');
    expect((await repo.liked()).single.note, isNull);
    final sent = <OutboxEntry>[];
    await db.drain((e) async => sent.add(e), refused: (_) => false);
    expect(sent.map((e) => e.action), [
      'collection_create',
      'membership',
      'note',
      'unlike',
      'restore_like',
      'collection_rename',
      'collection_delete',
      'note',
    ]);
    expect(sent[4].payload['collections'], removed.collections);
  });

  test(
    'invalid or duplicate names and non-liked edits change nothing',
    () async {
      await repo.createCollection('Samples');
      for (final name in ['', '   ', 'x' * 61, 'Samples']) {
        await expectLater(repo.createCollection(name), throwsArgumentError);
      }
      await expectLater(
        repo.saveNote('sample/missing', 'note'),
        throwsStateError,
      );
      await expectLater(
        repo.setMembership('sample/a', 'missing', true),
        throwsStateError,
      );
      expect(await db.pendingCount(), 1);
    },
  );
}
