import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/library_card.dart';
import '../local/offline_database.dart';
import '../services/local_store.dart';
import 'discover_repository.dart';
import 'offline_repository.dart';

/// What an unlike deleted, so Undo can put it back exactly (A3-12).
class RemovedLike {
  const RemovedLike(this.like, this.collections);

  /// The whole `likes` row: timetable, note and pause (with its card embedded).
  final Map<String, dynamic> like;

  /// The `collection_cards` rows the like was in.
  final List<Map<String, dynamic>> collections;
}

/// The only door to the Library: liked and saved cards, and what you do with them.
/// Online it reads Supabase and keeps a copy on the phone; offline it reads
/// that copy. Every change goes to the outbox (PRD section 8).
class LibraryRepository {
  LibraryRepository(this._client, this._discover, this._offline);

  final SupabaseClient _client;
  final DiscoverRepository _discover;
  final OfflineRepository _offline;

  Future<Map<String, String>> collections() async {
    final db = _offline.db;
    var rows = await db?.collections() ?? [];
    final revision = await db?.outboxRevision();
    if (await _offline.canReadServer()) {
      try {
        rows = await _client
            .from('collections')
            .select()
            .order('name', ascending: true);
        if (db != null &&
            !await db.keepSnapshot(
              revision!,
              () => db.replaceCollections(rows),
            )) {
          rows = await db.collections();
        }
      } on PostgrestException {
        rethrow;
      } catch (_) {
        /* The cached list can legitimately be empty. */
      }
    }
    rows.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return {for (final r in rows) r['id'] as String: r['name'] as String};
  }

  Future<String> _collectionName(String name, {String? except}) async {
    final value = name.trim();
    if (value.isEmpty ||
        value.runes.length > 60 ||
        (await collections()).entries.any(
          (c) => c.key != except && c.value == value,
        )) {
      throw ArgumentError('Use a unique name of 1–60 characters.');
    }
    return value;
  }

  Future<String> createCollection(String name) async {
    final row = {
      'id': uuid(),
      'name': await _collectionName(name),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _edit('collection_create', row, (db) => db.putCollection(row));
    return row['id']!;
  }

  Future<void> renameCollection(String id, String name) async {
    final value = await _collectionName(name, except: id);
    final rows = await _offline.db?.collections() ?? [];
    final row = rows.where((r) => r['id'] == id).firstOrNull;
    if (row == null) throw StateError('Collection not found');
    await _edit('collection_rename', {
      'id': id,
      'name': value,
    }, (db) => db.putCollection({...row, 'name': value}));
  }

  Future<void> deleteCollection(String id) =>
      _edit('collection_delete', {'id': id}, (db) => db.deleteCollection(id));

  Future<void> saveNote(String cardId, String note) => _editLike(
    cardId,
    'note',
    {'note': note.isEmpty ? null : note},
    (row) => row['note'] = note.isEmpty ? null : note,
  );

  Future<void> setMembership(String cardId, String id, bool included) async {
    if (!(await collections()).containsKey(id)) {
      throw StateError('Collection not found');
    }
    final at = DateTime.now().toUtc().toIso8601String();
    await _editLike(
      cardId,
      'membership',
      {'collection_id': id, 'included': included, 'added_at': at},
      (row) {
        final places = List<Map<String, dynamic>>.from(
          row['collection_cards'] as List? ?? [],
        );
        if (included && !places.any((c) => c['collection_id'] == id)) {
          places.add({
            'collection_id': id,
            'discover_card_id': cardId,
            'added_at': at,
          });
        } else if (!included) {
          places.removeWhere((c) => c['collection_id'] == id);
        }
        row['collection_cards'] = places;
      },
    );
  }

  Future<void> _editLike(
    String cardId,
    String action,
    Map<String, dynamic> payload,
    void Function(Map<String, dynamic>) change,
  ) => _edit(action, {'card_id': cardId, ...payload}, (db) async {
    final row = await db.libraryRow('liked', cardId);
    if (row == null) throw StateError('Like not found');
    change(row);
    await db.putInLibrary('liked', row, 'liked_at');
  });

  Future<void> _edit(
    String action,
    Map<String, dynamic> payload,
    Future<void> Function(OfflineDatabase) change,
  ) async {
    final db = _offline.db;
    if (db == null) throw StateError('Not signed in');
    await db.transaction(() async {
      if (_offline.resetting) throw StateError('Activity is being deleted');
      await change(db);
      await db.enqueue(action, payload);
    });
    await _offline.count();
    unawaited(_offline.flush());
  }

  /// For later rows removed this session, so Undo can put them back on the phone.
  final Map<String, Map<String, dynamic>> _unsaved = {};

  /// Liked cards, newest first.
  Future<List<LibraryCard>> liked() =>
      _read('liked', 'likes', 'liked_at', DiscoverRepository.likeColumns);

  /// Cards saved for later, newest first.
  Future<List<LibraryCard>> later() => _read(
    'later',
    'saved_for_later',
    'saved_at',
    DiscoverRepository.libraryCard,
  );

  Future<List<LibraryCard>> _read(
    String list,
    String table,
    String atColumn,
    String columns,
  ) async {
    final db = _offline.db;
    var rows = await _offline.library(list);
    final revision = await db?.outboxRevision();
    if (await _offline.canReadServer()) {
      try {
        rows = await _client
            .from(table)
            .select('*, $columns')
            .order(atColumn, ascending: false);
        // The phone keeps every like (Undo needs them) and the newest For later cards.
        if (db != null &&
            !await db.keepSnapshot(
              revision!,
              () => db.replaceLibrary(
                list,
                list == 'later'
                    ? rows.take(_offline.mode.forLater).toList()
                    : rows,
                atColumn,
              ),
            )) {
          rows = await db.library(list);
        }
      } catch (_) {
        if (rows.isEmpty) rethrow;
      }
    }
    final cards = await _discover.cardsFrom([
      for (final r in rows)
        {
          ...r['discover_cards'] as Map<String, dynamic>,
          if (list == 'liked')
            'likes': [
              {'note': r['note']},
            ],
        },
    ]);
    return [
      for (var i = 0; i < rows.length; i++)
        LibraryCard.fromRow(rows[i], cards[i], liked: list == 'liked'),
    ];
  }

  /// Deletes the like (and so its timetable, note and collection places) and
  /// returns what was deleted. Past answers stay (D40).
  Future<RemovedLike> unlike(String cardId) async {
    final db = _offline.db;
    // Online, the current row: its note or timetable may have changed since
    // the list loaded. Offline, the phone's copy.
    Map<String, dynamic>? row;
    if (await _offline.canReadServer()) {
      row = await _client
          .from('likes')
          .select('*, ${DiscoverRepository.likeColumns}')
          .eq('user_id', _client.auth.currentUser!.id)
          .eq('discover_card_id', cardId)
          .maybeSingle();
    }
    row ??= await db?.libraryRow('liked', cardId);
    if (db == null || row == null) throw StateError('Like $cardId not found');
    await _edit('unlike', {
      'card_id': cardId,
    }, (db) => db.removeFromLibrary('liked', cardId));
    return RemovedLike(row, [
      for (final c in row['collection_cards'] as List? ?? const [])
        Map<String, dynamic>.from(c as Map),
    ]);
  }

  /// Puts a removed like back exactly as it was.
  Future<void> restoreLike(RemovedLike removed) async {
    await _edit('restore_like', {
      'like': {...removed.like}
        ..remove('discover_cards')
        ..remove('collection_cards'),
      'collections': removed.collections,
    }, (db) => db.putInLibrary('liked', removed.like, 'liked_at'));
  }

  Future<void> unsave(String cardId) async {
    final db = _offline.db;
    final row = await db?.libraryRow('later', cardId);
    if (row != null) _unsaved[cardId] = row;
    await db?.removeFromLibrary('later', cardId);
    await _offline.queue('unsave', {'card_id': cardId});
  }

  /// Puts a removed For later card back with its time and video position.
  Future<void> restoreSaved(LibraryCard saved) async {
    final row = {
      'discover_card_id': saved.card.id,
      'saved_at': saved.at.toUtc().toIso8601String(),
      'resume_at_seconds': saved.resumeAtSeconds,
    };
    final kept = _unsaved.remove(saved.card.id);
    if (kept != null) {
      await _offline.db?.putInLibrary('later', kept, 'saved_at');
    }
    await _offline.queue('restore_saved', {'saved': row});
  }

  /// Pause or resume the tests of a liked card (`likes.reviews_paused`).
  Future<void> setReviewsPaused(String cardId, bool paused) async {
    final db = _offline.db;
    final row = await db?.libraryRow('liked', cardId);
    if (row != null) {
      await db!.putInLibrary('liked', {
        ...row,
        'reviews_paused': paused,
      }, 'liked_at');
    }
    await _offline.queue('pause', {'card_id': cardId, 'paused': paused});
  }
}
