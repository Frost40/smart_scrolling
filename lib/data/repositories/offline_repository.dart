import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/offline_mode.dart';
import '../local/offline_database.dart';
import '../services/media_download_service.dart';
import 'discover_repository.dart';

/// Offline Discover, Library and Practice (PRD section 8): the phone
/// database, the outbox, refills and the space cap. The repositories ask it
/// whether to read the phone or Supabase, and put every action in its outbox.
class OfflineRepository extends ChangeNotifier with WidgetsBindingObserver {
  OfflineRepository(
    this._client, {
    Stream<List<ConnectivityResult>>? connectivity,
    OfflineDatabase Function(String userId)? openDatabase,
  }) : _openDatabase = openDatabase ?? _phoneDatabase {
    WidgetsBinding.instance.addObserver(this);
    _connection = (connectivity ?? Connectivity().onConnectivityChanged).listen(
      _connectionChanged,
      onError: (Object _) {},
    );
    if (connectivity == null) {
      Connectivity().checkConnectivity().then(
        _connectionChanged,
        onError: (_) {},
      );
    }
  }

  static OfflineDatabase _phoneDatabase(String userId) =>
      OfflineDatabase(driftDatabase(name: 'offline_$userId'));

  final SupabaseClient _client;
  final OfflineDatabase Function(String userId) _openDatabase;
  late final StreamSubscription<List<ConnectivityResult>> _connection;

  OfflineDatabase? _db;
  String? _userId;
  Directory? _files;
  OfflineMode mode = OfflineMode.standard;
  bool mobileData = false, online = true, wifi = true;

  /// What Settings shows.
  int unseen = 0, liked = 0, later = 0, practice = 0, pending = 0;
  int usedBytes = 0;
  bool downloading = false;

  /// Why the last refill stopped early, in plain words; null when it did not.
  String? note;

  Future<bool>? _flushing;
  Future<void>? _refilling;
  bool _resetting = false;
  bool get resetting => _resetting;

  /// Stop background work so neither an old snapshot nor the outbox can restore deleted activity.
  Future<void> deleteActivity(Future<void> Function() deleteOnServer) async {
    if (!online || _resetting) throw StateError('Connect before deleting');
    final db = _db;
    _resetting = true;
    try {
      await _refilling;
      await _flushing;
      if (db == null || db != _db) throw StateError('Account changed');
      final files = await db.clearActivity();
      if (_files != null) await _delete(files, _files!);
      // Retrying the same reset is safe when the server committed but its response was lost.
      final sent = await db.drain(
        (_) => deleteOnServer(),
        refused: (_) => false,
      );
      await count();
      if (!sent) {
        throw StateError(
          'Deletion is waiting to sync. Reconnect and try again.',
        );
      }
    } finally {
      _resetting = false;
    }
  }

  /// The signed-in person's database; null while signed out.
  OfflineDatabase? get db => _db;

  /// Opens [userId]'s own database (null closes it). The first [configure] refills.
  Future<void> use(String? userId) async {
    if (userId == _userId) return;
    final old = _db;
    _db = null;
    _files = null;
    _configured = false;
    _userId = userId;
    await old?.close();
    if (userId != null) {
      _db = _openDatabase(userId);
      final base = await getApplicationSupportDirectory();
      _files = Directory('${base.path}/offline_media/$userId');
      await _files!.create(recursive: true);
      await count();
    }
  }

  bool _configured = false, _again = false;

  /// Applies `devices.offline_mode` and `download_on_mobile_data`.
  void configure(String modeName, bool useMobileData) {
    final next = OfflineMode.parse(modeName);
    if (_configured && next == mode && useMobileData == mobileData) return;
    _configured = _db != null;
    mode = next;
    mobileData = useMobileData;
    unawaited(refill());
  }

  void _connectionChanged(List<ConnectivityResult> results) {
    final was = (online, wifi);
    online = results.any((r) => r != ConnectivityResult.none);
    wifi =
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    notifyListeners();
    if (!online) return;
    // Sending actions is not a download: any connection will do.
    unawaited(flush());
    // Coming back often reports mobile data first and Wi-Fi a moment later.
    if ((online, wifi) != was) unawaited(refill());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refill());
  }

  /// True when Supabase can be read: online and nothing left waiting to send,
  /// so a fresh read never hides an action taken offline.
  Future<bool> canReadServer() async => online && await flush();

  /// Unseen stock in feed order; empty while signed out.
  Future<List<Map<String, dynamic>>> stock({
    required String filter,
    required Set<String> exclude,
    required int limit,
  }) async =>
      await _db?.stock(filter: filter, exclude: exclude, limit: limit) ?? [];

  /// A Library list kept on the phone (`liked` or `later`), newest first.
  Future<List<Map<String, dynamic>>> library(String list) async =>
      await _db?.library(list) ?? [];

  /// The Practice window's unpaused Likes in timetable order, with their tests.
  Future<List<Map<String, dynamic>>> practiceRows() async =>
      await _db?.practiceRows() ?? [];

  /// The latest answer time of each test in the window.
  Future<Map<String, DateTime>> lastAnswers() async =>
      await _db?.lastAnswers() ?? {};

  /// Keeps an answer and its timetable on the phone. With [send] it also goes
  /// to the outbox; without, Supabase has it already.
  Future<void> saveAnswer(
    Map<String, dynamic> params, {
    required bool send,
  }) async {
    if (_resetting) throw StateError('Activity is being deleted');
    final db = _db;
    if (db == null) {
      if (send) throw StateError('Not signed in');
      return;
    }
    if (await db.saveAnswer(params, send: send) && send) {
      await count();
      unawaited(flush());
    }
  }

  /// Puts an action in the outbox and tries to send it at once.
  Future<void> queue(String action, Map<String, dynamic> payload) async {
    if (_resetting) throw StateError('Activity is being deleted');
    final db = _db;
    if (db == null) throw StateError('Not signed in');
    await db.enqueue(action, payload);
    await count();
    unawaited(flush());
  }

  /// Sends the outbox in order; returns true when it is empty.
  Future<bool> flush() {
    if (_resetting) return Future.value(false);
    final db = _db;
    final owner = _userId;
    if (db == null) return Future.value(true);
    if (!online) return db.pendingCount().then((n) => n == 0);
    return _flushing ??= db
        .drain((entry) {
          if (db != _db || owner != _client.auth.currentUser?.id) {
            throw StateError('Account changed');
          }
          return _send(entry, owner!);
        }, refused: (e) => e is PostgrestException)
        .catchError((Object _) => false)
        .whenComplete(() async {
          _flushing = null;
          if (db == _db) await count();
        });
  }

  String get _me => _client.auth.currentUser!.id;

  /// One outbox action, sent to Supabase. Every one is safe to send twice.
  Future<void> _send(OutboxEntry e, String owner) async {
    final p = e.payload;
    final card = p['card_id'];
    switch (e.action) {
      case 'delete_data':
        try {
          final session = _client.auth.currentSession;
          if (session == null || session.user.id != owner) {
            throw StateError('Account changed');
          }
          await _client
              .rpc('delete_my_data')
              .setHeader('Authorization', 'Bearer ${session.accessToken}');
        } on PostgrestException {
          // A confirmed deletion must never fall out of the queue after five refusals.
          throw StateError('Deletion is waiting to sync');
        }
      case 'collection_create':
        await _client
            .from('collections')
            .upsert(p, onConflict: 'id', ignoreDuplicates: true);
      case 'collection_rename':
        await _client
            .from('collections')
            .update({'name': p['name']})
            .eq('user_id', _me)
            .eq('id', p['id']);
      case 'collection_delete':
        await _client
            .from('collections')
            .delete()
            .eq('user_id', _me)
            .eq('id', p['id']);
      case 'note':
        await _client
            .from('likes')
            .update({'note': p['note']})
            .eq('user_id', _me)
            .eq('discover_card_id', card);
      case 'membership':
        if (p['included'] == true) {
          await _client
              .from('collection_cards')
              .upsert(
                {
                  'collection_id': p['collection_id'],
                  'discover_card_id': card,
                  'added_at': p['added_at'],
                },
                onConflict: 'collection_id,discover_card_id',
                ignoreDuplicates: true,
              );
        } else {
          await _client
              .from('collection_cards')
              .delete()
              .eq('user_id', _me)
              .eq('collection_id', p['collection_id'])
              .eq('discover_card_id', card);
        }
      case 'like':
        await _client.rpc('like_card', params: {'p_card_id': card});
      case 'undo_like':
        await _client.rpc(
          'undo_like',
          params: {'p_card_id': card, 'p_saved_at': p['saved_at']},
        );
      case 'save':
        await _client.rpc('save_for_later', params: {'p_card_id': card});
      case 'resume':
        await _client
            .from('saved_for_later')
            .update({'resume_at_seconds': p['seconds']})
            .eq('user_id', _me)
            .eq('discover_card_id', card);
      case 'unsave':
        await _client
            .from('saved_for_later')
            .delete()
            .eq('user_id', _me)
            .eq('discover_card_id', card);
      case 'seen':
        await _client.from('seen_cards').upsert([
          for (final id in p['card_ids'] as List)
            {'discover_card_id': id, 'last_seen_at': p['at']},
        ], onConflict: 'user_id,discover_card_id');
      case 'unlike':
        await _client
            .from('likes')
            .delete()
            .eq('user_id', _me)
            .eq('discover_card_id', card);
      case 'restore_like':
        await _client
            .from('likes')
            .upsert(
              p['like'] as Map<String, dynamic>,
              onConflict: 'user_id,discover_card_id',
              ignoreDuplicates: true,
            );
        final places = p['collections'] as List;
        if (places.isNotEmpty) {
          await _client
              .from('collection_cards')
              .upsert(
                places.cast<Map<String, dynamic>>(),
                onConflict: 'collection_id,discover_card_id',
                ignoreDuplicates: true,
              );
        }
      case 'restore_saved':
        await _client
            .from('saved_for_later')
            .upsert(
              p['saved'] as Map<String, dynamic>,
              onConflict: 'user_id,discover_card_id',
            );
      case 'answer':
        // The phone-made id makes a resend harmless; the later answer wins.
        await _client.rpc('record_answer', params: p);
      case 'pause':
        await _client
            .from('likes')
            .update({'reviews_paused': p['paused']})
            .eq('user_id', _me)
            .eq('discover_card_id', card);
    }
  }

  /// Download now (Settings), also run on start, resume and reconnect.
  /// A refill asked for while one runs follows it, so a new mode always applies.
  Future<void> refill() {
    if (_resetting) return Future.value();
    if (_refilling case final running?) {
      _again = true;
      return running;
    }
    return _refilling = () async {
      do {
        _again = false;
        await _refill();
      } while (_again);
    }().whenComplete(() => _refilling = null);
  }

  Future<void> _refill() async {
    final db = _db;
    final files = _files;
    if (db == null || files == null || !_configured) return;
    note = null;
    try {
      await _delete(await db.trimMedia(mode.capBytes), files);
      if (mode == OfflineMode.onlineOnly) {
        await _delete(await db.clearDownloads(), files);
        return;
      }
      if (!online) return;
      if (!wifi && !mobileData) {
        note = 'Waiting for Wi-Fi. Turn on "Use mobile data" to download now.';
        return;
      }
      downloading = true;
      notifyListeners();
      final revision = await db.outboxRevision();
      if (!await flush()) return;
      await db.dropSeen();
      final have = await db.unseenIds();
      final need = mode.cardsToFetch(have.length);
      if (need > 0) {
        await db.addStock(await _feedRows(need, have));
      }
      final likes = await _client
          .from('likes')
          .select('*, ${DiscoverRepository.likeColumns}')
          .order('liked_at', ascending: false);
      final saved = await _client
          .from('saved_for_later')
          .select('*, ${DiscoverRepository.libraryCard}')
          .order('saved_at', ascending: false)
          .limit(mode.forLater);
      final collections = await _client
          .from('collections')
          .select()
          .order('name', ascending: true);
      final window = await _practiceWindow();
      if (db != _db || !await flush()) return;
      final kept = await db.keepSnapshot(revision, () async {
        await db.replaceLibrary('liked', likes, 'liked_at');
        await db.replaceLibrary('later', saved, 'saved_at');
        await db.replaceCollections(collections);
        await db.replacePractice(window);
      });
      if (!kept) {
        _again = true;
        return;
      }
      await _downloadMedia(db);
    } catch (_) {
      note ??=
          'The last download stopped early. It continues when you are online.';
    } finally {
      downloading = false;
      if (db == _db) await count();
    }
  }

  /// The next [count] feed cards, leaving out [have].
  Future<List<Map<String, dynamic>>> _feedRows(
    int count,
    List<String> have,
  ) async {
    final rows = await _client
        .rpc('discover_feed', params: {'p_limit': count, 'p_exclude': have})
        .select(DiscoverRepository.cardColumns);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// The Practice window (A3-13): unpaused Likes due in the next 14 days,
  /// soonest first, up to the mode's count, each with its published tests
  /// and each test's latest answer (to pick tests on the phone, D32).
  Future<Map<String, List<dynamic>>> _practiceWindow() async {
    const answers =
        'discover_cards.practice_links.practice_cards.practice_answers';
    final rows = await _client
        .from('likes')
        .select(
          'discover_card_id, discover_cards!inner(practice_links!inner('
          'practice_cards!inner(*, practice_answers(answered_at))))',
        )
        .eq('reviews_paused', false)
        .lte(
          'next_review_at',
          DateTime.now()
              .toUtc()
              .add(const Duration(days: 14))
              .toIso8601String(),
        )
        .order('answered_at', referencedTable: answers, ascending: false)
        .limit(1, referencedTable: answers)
        .order('next_review_at', ascending: true)
        .order('discover_card_id', ascending: true)
        .limit(mode.practiceWindow);
    return {
      for (final r in rows)
        r['discover_card_id'] as String: [
          for (final link in r['discover_cards']['practice_links'] as List)
            link['practice_cards'],
        ],
    };
  }

  Future<void> _downloadMedia(OfflineDatabase db) async {
    final files = _files!;
    final cap = mode.capBytes;
    for (final isMedia in [false, true]) {
      final missing = await db.missingMedia(isMedia: isMedia);
      for (var i = 0; i < missing.length; i += 50) {
        final links = await signedLinks(
          _client,
          missing.sublist(i, (i + 50).clamp(0, missing.length)),
        );
        for (final MapEntry(key: path, value: url) in links.entries) {
          if (db != _db ||
              mode.capBytes != cap ||
              !online ||
              (!wifi && !mobileData)) {
            return;
          }
          final name =
              '${base64Url.encode(utf8.encode(path))}${isMedia ? '.${path.split('.').last}' : ''}';
          final staging = File('${files.path}/$name.download');
          final bytes = await downloadMedia(
            url,
            staging,
            isMedia ? cap ~/ 5 : cap,
          );
          if (bytes == null) continue;
          if (db != _db || mode.capBytes != cap) {
            await staging.delete();
            return;
          }
          final room = await db.makeRoom(bytes, cap, isMedia: isMedia);
          await _delete(room.gone, files);
          if (!room.fits) {
            await staging.delete();
            note = 'The space limit is reached. Seen cards make room as you scroll.';
            continue;
          }
          await staging.rename('${files.path}/$name');
          await db.addFile(path, name, bytes, isMedia: isMedia);
        }
      }
    }
  }

  Future<void> _delete(List<String> names, Directory files) async {
    for (final name in names) {
      final f = File('${files.path}/$name');
      if (await f.exists()) await f.delete();
    }
  }

  /// `file://` addresses of the downloaded pictures among [paths].
  Future<Map<String, String>> localMedia(Iterable<String> paths) async {
    final db = _db;
    if (db == null || _files == null) return {};
    return {
      for (final MapEntry(key: path, value: name) in (await db.localFiles(
        paths,
      )).entries)
        path: Uri.file('${_files!.path}/$name').toString(),
    };
  }

  /// Refreshes the numbers Settings shows.
  Future<void> count() async {
    final db = _db;
    if (db == null) return;
    unseen = (await db.unseenIds()).length;
    liked = await db.libraryCount('liked');
    later = await db.libraryCount('later');
    practice = await db.practiceCount();
    pending = await db.pendingCount();
    usedBytes = await db.usedBytes();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connection.cancel();
    _db?.close();
    super.dispose();
  }
}
