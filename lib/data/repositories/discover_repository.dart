import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/discover_card.dart';
import '../../domain/models/source.dart';
import 'offline_repository.dart';

/// The only door to the Discover feed, its actions and source pages.
/// Online it reads Supabase; offline it reads the stock on the phone.
/// Every action goes to the outbox (PRD section 8).
class DiscoverRepository {
  DiscoverRepository(this._client, this._offline);

  final SupabaseClient _client;
  final OfflineRepository _offline;

  /// A card with its source, topics and linked tests, so the same row serves
  /// the feed, the offline stock and the Library.
  static const cardColumns =
      '*, sources(title, kind, published_on, news_details(newspaper), '
      'source_topics(topics(id, name))), '
      'card_topics(topics(id, name)), practice_links(practice_cards(id,type)), likes(note), '
      'outgoing:related_cards!discover_card_id(card:discover_cards!related_card_id(id,title)), '
      'incoming:related_cards!related_card_id(card:discover_cards!discover_card_id(id,title))';

  /// The card embedded in a `likes` or `saved_for_later` row. The access rules
  /// hide unpublished cards (so they leave the Library) and unpublished tests
  /// (so a card with none of them is "waiting for tests").
  static const libraryCard = 'discover_cards!inner($cardColumns)';

  /// A like with its card and its collection places, so Undo restores both.
  static const likeColumns =
      '$libraryCard, collection_cards(collection_id, discover_card_id, added_at)';

  /// Rows of cards shown recently, so an action can update the phone's lists.
  final Map<String, Map<String, dynamic>> _rows = {};

  /// The next [limit] cards of the feed, leaving out [exclude] (D34, A3-5).
  /// [filter] is `mix` or one format; Supabase reads it from the profile.
  Future<List<DiscoverCard>> feed({
    int limit = 20,
    Iterable<String> exclude = const [],
    String filter = 'mix',
  }) async {
    Future<List<DiscoverCard>> stock() async => cardsFrom(
      await _offline.stock(
        filter: filter,
        exclude: exclude.toSet(),
        limit: limit,
      ),
      fromCache: true,
    );
    if (!await _offline.canReadServer()) return stock();
    try {
      final rows = await _client
          .rpc(
            'discover_feed',
            params: {'p_limit': limit, 'p_exclude': exclude.toList()},
          )
          .select(cardColumns);
      return await cardsFrom(rows);
    } catch (_) {
      final cards = await stock();
      if (cards.isEmpty) rethrow;
      return cards;
    }
  }

  Future<void> like(String cardId) async {
    final db = _offline.db;
    final row = _rows[cardId] ?? await db?.cardRow(cardId);
    if (db != null && row != null) {
      if (await db.libraryRow('liked', cardId) == null) {
        final now = DateTime.now().toUtc();
        await db.putInLibrary('liked', {
          'user_id': _client.auth.currentUser?.id,
          'discover_card_id': cardId,
          'liked_at': now.toIso8601String(),
          'review_level': 0,
          'next_review_at': now.add(const Duration(days: 1)).toIso8601String(),
          'reviews_paused': false,
          'discover_cards': row,
          'collection_cards': const [],
        }, 'liked_at');
      }
      await db.removeFromLibrary('later', cardId);
      await db.markSeen([cardId]);
    }
    await _offline.queue('like', {'card_id': cardId});
  }

  /// Undoes a Like; [savedAt] puts the card back in For later as it was.
  Future<void> undoLike(String cardId, {DateTime? savedAt}) async {
    final at = savedAt?.toUtc().toIso8601String();
    await _offline.db?.removeFromLibrary('liked', cardId);
    if (at != null) await _keepSaved(cardId, at);
    await _offline.queue('undo_like', {'card_id': cardId, 'saved_at': at});
  }

  /// Saves the card for later and returns when it was saved.
  Future<DateTime> saveForLater(String cardId) async {
    final now = DateTime.now().toUtc();
    await _keepSaved(cardId, now.toIso8601String());
    await _offline.db?.markSeen([cardId]);
    await _offline.queue('save', {'card_id': cardId});
    final position = await _offline.db?.resume(cardId);
    if (position != null) {
      await _offline.queue('resume', {'card_id': cardId, 'seconds': position});
    }
    return now;
  }

  Future<void> _keepSaved(String cardId, String at) async {
    final db = _offline.db;
    final row = _rows[cardId] ?? await db?.cardRow(cardId);
    if (db == null || row == null) return;
    await db.putInLibrary('later', {
      'discover_card_id': cardId,
      'saved_at': at,
      'resume_at_seconds': await db.resume(cardId),
      'discover_cards': row,
    }, 'saved_at');
  }

  Future<void> unsave(String cardId) async {
    await _offline.db?.removeFromLibrary('later', cardId);
    await _offline.queue('unsave', {'card_id': cardId});
  }

  /// Marks a small batch of cards as seen (A3-4).
  Future<void> markSeen(Iterable<String> cardIds) async {
    final ids = cardIds.toList();
    await _offline.db?.markSeen(ids);
    await _offline.queue('seen', {
      'card_ids': ids,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Adds a to-do for the owner about this card. Needs a connection.
  Future<void> reportProblem(String cardId, String message) =>
      _client.from('content_requests').insert({
        'kind': 'problem',
        'discover_card_id': cardId,
        'source_id': cardId.split('/').first,
        'message': message.trim().isEmpty ? null : message.trim(),
      });

  /// One source with its kind details and its published cards in order.
  Future<Source> source(String id) async {
    final row = await _client
        .from('sources')
        .select('*, book_details(*), paper_details(*), news_details(*)')
        .eq('id', id)
        .single();
    final cards = await _client
        .from('discover_cards')
        .select(cardColumns)
        .eq('source_id', id)
        .order('position', ascending: true)
        .order('id', ascending: true);
    final cover = row['cover_path'] as String?;
    return Source.fromRow(
      row,
      coverUrl: cover == null ? null : (await mediaLinks([cover]))[cover],
      cards: await cardsFrom(cards),
    );
  }

  /// Opens the exact related card. Offline it must already be on this phone.
  Future<DiscoverCard> card(String id) async {
    Map<String, dynamic>? row;
    var fromCache = false;
    if (await _offline.canReadServer()) {
      try {
        row = await _client
            .from('discover_cards')
            .select(cardColumns)
            .eq('id', id)
            .maybeSingle();
        if (row == null) throw StateError('Card is no longer published');
      } on PostgrestException {
        rethrow;
      } on StateError {
        rethrow;
      } catch (_) {
        row = await _offline.db?.cardRow(id);
        fromCache = true;
      }
    } else {
      row = await _offline.db?.cardRow(id);
      fromCache = true;
    }
    if (row == null) throw StateError('Card is not downloaded');
    return (await cardsFrom([row], fromCache: fromCache)).single;
  }

  /// Cards from `discover_cards` rows (also used by the Library and Practice).
  /// Pictures come from the phone when downloaded, otherwise from signed links.
  Future<List<DiscoverCard>> cardsFrom(
    List<Map<String, dynamic>> rows, {
    bool fromCache = false,
  }) async {
    if (fromCache || !_offline.online) {
      rows = [
        for (final row in rows)
          {
            ...row,
            'likes': [
              if (await _offline.db?.libraryRow('liked', row['id'])
                  case final like?)
                {'note': like['note']},
            ],
          },
      ];
    }
    final paths = {
      for (final r in rows)
        for (final key in ['media_path', 'poster_path'])
          if (r[key] != null) r[key] as String,
    };
    final links = await _offline.localMedia(paths);
    final rest = paths.where((p) => !links.containsKey(p)).toList();
    if (rest.isNotEmpty && _offline.online) {
      links.addAll(await mediaLinks(rest));
    }
    for (final r in rows) {
      _rows[r['id'] as String] = r;
    }
    return [
      for (final r in rows)
        DiscoverCard.fromRow(
          r,
          mediaUrl: links[r['media_path']],
          posterUrl: links[r['poster_path']],
        ),
    ];
  }

  /// Refresh signed URLs on Play; never use an hour-old feed address.
  Future<CardMediaData> loadMedia(DiscoverCard card) async {
    final db = _offline.db;
    if (db == null || card.mediaPath == null) {
      throw StateError('Media unavailable');
    }
    var saved = await db.libraryRow('later', card.id);
    if (await _offline.canReadServer()) {
      try {
        saved = await _client
            .from('saved_for_later')
            .select()
            .eq('user_id', _client.auth.currentUser!.id)
            .eq('discover_card_id', card.id)
            .maybeSingle();
      } catch (_) {
        /* The phone copy remains usable. */
      }
    }
    final paths = [card.mediaPath!, ?card.captionsPath];
    final links = await _offline.localMedia(paths);
    if (_offline.online) {
      links.addAll(
        await mediaLinks(paths.where((p) => !links.containsKey(p)).toList()),
      );
    }
    final url = links[card.mediaPath];
    if (url == null) throw StateError('Media is not downloaded');
    var captions = '';
    if (links[card.captionsPath] case final captionUrl?) {
      try {
        if (captionUrl.startsWith('file:')) {
          captions = await File.fromUri(Uri.parse(captionUrl)).readAsString();
        } else {
          final http = HttpClient()
            ..connectionTimeout = const Duration(seconds: 15);
          try {
            final response = await (await http.getUrl(Uri.parse(captionUrl)))
                .close()
                .timeout(const Duration(seconds: 15));
            if (response.statusCode == HttpStatus.ok) {
              captions = await utf8
                  .decodeStream(response)
                  .timeout(const Duration(seconds: 15));
            }
          } finally {
            http.close(force: true);
          }
        }
      } catch (_) {
        /* The transcript is still readable on the back. */
      }
    }
    return (
      url: url,
      captions: captions,
      resume:
          saved?['resume_at_seconds'] as int? ?? await db.resume(card.id) ?? 0,
      save: (int seconds) async {
        if (db != _offline.db) {
          return; // A disposed player cannot write another account's position.
        }
        await db.transaction(() async {
          await db.setResume(card.id, seconds);
          final later = await db.libraryRow('later', card.id);
          if (later != null) {
            later['resume_at_seconds'] = seconds;
            await db.putInLibrary('later', later, 'saved_at');
          }
          if (later != null || saved != null) {
            await db.enqueue('resume', {
              'card_id': card.id,
              'seconds': seconds,
            });
          }
        });
        await _offline.count();
        unawaited(_offline.flush());
      },
    );
  }

  /// Signed links for media paths. A missing link only hides that picture.
  Future<Map<String, String>> mediaLinks(List<String> paths) =>
      signedLinks(_client, paths);
}

/// Signed links for media paths, valid 1 hour (A3-7). A missing link only hides that picture.
Future<Map<String, String>> signedLinks(
  SupabaseClient client,
  List<String> paths,
) async {
  if (paths.isEmpty) return {};
  try {
    final results = await client.storage
        .from('media')
        .createSignedUrlsResult(paths, 3600);
    return {
      for (final r in results.whereType<SignedUrlSuccess>())
        r.path: r.signedUrl,
    };
  } catch (_) {
    return {};
  }
}
