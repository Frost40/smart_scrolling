import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/practice_card.dart';
import '../../domain/models/progress_summary.dart';
import '../../domain/models/discover_card.dart';
import '../../domain/review_schedule.dart';
import '../../domain/test_picker.dart';
import '../services/local_store.dart';
import 'discover_repository.dart';
import 'offline_repository.dart';

class PracticeUnavailable implements Exception {
  const PracticeUnavailable();
}

/// Due tests and answers. Online it reads Supabase; offline it reads the
/// Practice window on the phone and picks tests by the same rule (D32).
/// Answers given offline wait in the outbox (A3-3).
class PracticeRepository {
  PracticeRepository(this._client, this._discover, this._offline);

  final SupabaseClient _client;
  final DiscoverRepository _discover;
  final OfflineRepository _offline;

  Future<DiscoverCard> card(String id) => _discover.card(id);

  Future<ProgressSummary> progress() async {
    if (!await _offline.canReadServer()) {
      throw StateError('Connect to sync first');
    }
    final me = _client.auth.currentUser!.id;
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    final likes = <Map<String, dynamic>>[], answers = <Map<String, dynamic>>[];
    // Page explicitly: Supabase's response cap must not turn totals into partial counts.
    for (var offset = 0; ; offset += 500) {
      final rows = await _client
          .from('likes')
          .select('reviews_paused,next_review_at,discover_cards(format)')
          .eq('user_id', me)
          .order('discover_card_id')
          .range(offset, offset + 499);
      likes.addAll(rows);
      if (rows.length < 500) break;
    }
    for (var offset = 0; ; offset += 500) {
      final rows = await _client
          .from('practice_answers')
          .select('answered_at')
          .eq('user_id', me)
          .gte('answered_at', monday.toUtc().toIso8601String())
          .lte('answered_at', now.toUtc().toIso8601String())
          .order('id')
          .range(offset, offset + 499);
      answers.addAll(rows);
      if (rows.length < 500) break;
    }
    final profile = await _client
        .from('profiles')
        .select('weekly_goal_days')
        .eq('user_id', me)
        .single();
    return ProgressSummary.fromRows(
      likes,
      answers,
      now: now,
      goal: profile['weekly_goal_days'] as int?,
    );
  }

  Future<PracticeBatch> due({
    int limit = 10,
    String filter = 'mix',
    Iterable<String> exclude = const [],
  }) => _read(limit, filter, exclude, early: false);

  Future<PracticeBatch> practiceNow({
    int limit = 10,
    String filter = 'mix',
    Iterable<String> exclude = const [],
  }) => _read(limit, filter, exclude, early: true);

  Future<PracticeBatch> _read(
    int limit,
    String filter,
    Iterable<String> exclude, {
    required bool early,
  }) async {
    if (!practiceFilters.contains(filter)) throw ArgumentError.value(filter);
    if (limit < 1) throw ArgumentError.value(limit);
    Future<PracticeBatch> phone() async => _batch(
      await _offline.practiceRows(),
      limit,
      filter,
      exclude,
      early: early,
      lastAnswers: await _offline.lastAnswers(),
    );
    if (!await _offline.canReadServer()) return phone();
    try {
      return await _batch(
        await _serverRows(),
        limit,
        filter,
        exclude,
        early: early,
      );
    } catch (_) {
      final batch = await phone();
      if (batch.entries.isEmpty) rethrow;
      return batch;
    }
  }

  /// Every unpaused Like in timetable order, with its card and test types.
  Future<List<Map<String, dynamic>>> _serverRows() async {
    final rows = <Map<String, dynamic>>[];
    // shortcut: scan Like metadata for counts; move counts/paging into SQL when
    // large libraries make this slow. Range paging avoids the API's row cap.
    const pageSize = 1000;
    for (var start = 0; ; start += pageSize) {
      final page = await _client
          .from('likes')
          .select('*, discover_cards!inner(${DiscoverRepository.cardColumns})')
          .eq('reviews_paused', false)
          .order('next_review_at', ascending: true)
          .order('discover_card_id', ascending: true)
          .range(start, start + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    return rows;
  }

  /// One page of [rows] (unpaused Likes in timetable order with their tests).
  /// Without [lastAnswers] Supabase picks each test; with them, the phone.
  Future<PracticeBatch> _batch(
    List<Map<String, dynamic>> rows,
    int limit,
    String filter,
    Iterable<String> exclude, {
    required bool early,
    Map<String, DateTime>? lastAnswers,
  }) async {
    final now = DateTime.now().toUtc();
    final eligible = <Map<String, dynamic>>[];
    var dueCount = 0, waiting = 0;
    final excluded = exclude.toSet();
    for (final row in rows) {
      final card = row['discover_cards'] as Map<String, dynamic>;
      final matches = (card['practice_links'] as List).any((link) {
        final test = link['practice_cards'] as Map?;
        return test != null && testMatches(test['type'] as String, filter);
      });
      if (!matches) {
        waiting++;
        continue;
      }
      final isDue = !DateTime.parse(row['next_review_at'] as String)
          .isAfter(now);
      if (isDue) dueCount++;
      if (isDue != early && !excluded.contains(row['discover_card_id'])) {
        eligible.add(row);
      }
    }
    final selected = eligible.take(limit).toList();
    final cards = await _discover.cardsFrom([
      for (final row in selected) row['discover_cards'] as Map<String, dynamic>,
    ]);
    final tests = lastAnswers == null
        ? await Future.wait([
            for (final card in cards) _serverTest(card.id, filter),
          ])
        : [
            for (final row in selected)
              pickTest(
                [
                  for (final link
                      in row['discover_cards']['practice_links'] as List)
                    PracticeCard.fromRow(link['practice_cards']),
                ],
                lastAnswers,
                filter: filter,
              ),
          ];
    return PracticeBatch(
      [
        for (var i = 0; i < cards.length; i++)
          if (tests[i] != null)
            PracticeEntry(
              card: cards[i],
              test: tests[i]!,
              level: selected[i]['review_level'] as int,
            ),
      ],
      due: dueCount,
      waiting: waiting,
      hasMore: eligible.length > limit,
    );
  }

  Future<PracticeCard?> _serverTest(
    String discoverCardId,
    String filter,
  ) async {
    final row = await _client.rpc(
      'pick_test',
      params: {'p_discover_card_id': discoverCardId, 'p_filter': filter},
    );
    if (row == null || (row as Map)['id'] == null) return null;
    return PracticeCard.fromRow(Map<String, dynamic>.from(row));
  }

  PracticeAnswer newAnswer(PracticeEntry entry, String result, Object? value) {
    final at = DateTime.now().toUtc();
    return PracticeAnswer(
      id: uuid(),
      entry: entry,
      result: result,
      value: value,
      answeredAt: at,
      step: nextReview(level: entry.level, result: result, answeredAt: at),
    );
  }

  /// Online with nothing waiting to send, the answer goes straight to
  /// Supabase, so a removed Like or test shows at once. Otherwise, or when
  /// the connection drops, it waits in the outbox with the same id. Either
  /// way the phone keeps it and moves its timetable.
  Future<void> recordAnswer(PracticeAnswer answer) async {
    final params = {
      'p_id': answer.id,
      'p_practice_card_id': answer.entry.test.id,
      'p_practice_card_version': answer.entry.test.version,
      'p_discover_card_id': answer.entry.card.id,
      'p_answer': answer.value,
      'p_result': answer.result,
      'p_answered_at': answer.answeredAt.toUtc().toIso8601String(),
      'p_review_level': answer.step.level,
      'p_next_review_at': answer.step.nextReviewAt.toUtc().toIso8601String(),
    };
    if (await _offline.canReadServer()) {
      try {
        await _client.rpc('record_answer', params: params);
        await _offline.saveAnswer(params, send: false);
        return;
      } on PostgrestException catch (error) {
        if (error.code == 'P0002') throw const PracticeUnavailable();
        rethrow;
      } catch (_) {
        // No answer from Supabase: the outbox sends it later.
      }
    }
    await _offline.saveAnswer(params, send: true);
  }
}
