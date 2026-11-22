import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/source.dart';
import '../../domain/models/topic.dart';
import 'discover_repository.dart';

class ExploreRepository {
  ExploreRepository(this._client);
  final SupabaseClient _client;
  String get _me => _client.auth.currentUser!.id;

  Future<List<Source>> searchSources(String text) => _search(text, null);
  Future<List<Source>> sourcesByTopic(String topicId) => _search('', topicId);
  Future<List<Source>> _search(String text, String? topic) async {
    final rows = <Map<String, dynamic>>[];
    for (var start = 0; ; start += 500) {
      final page = await _client
          .rpc(
            'search_sources',
            params: {'p_text': text.trim(), 'p_topic': topic},
          )
          .range(start, start + 499);
      rows.addAll((page as List).cast<Map<String, dynamic>>());
      if (page.length < 500) break;
    }
    final paths = [
      for (final r in rows)
        if (r['source']['cover_path'] != null)
          r['source']['cover_path'] as String,
    ];
    final links = await signedLinks(_client, paths);
    final sources = <Source>[
      for (final row in rows)
        Source.fromRow(
          Map<String, dynamic>.from(row['source'] as Map),
          cardCount: (row['card_count'] as num).toInt(),
          coverUrl: links[row['source']['cover_path']],
        ),
    ];
    return sources;
  }

  Future<List<Topic>> topicTree() async {
    final rows = await _client
        .from('topics')
        .select()
        .order('position', ascending: true)
        .order('name', ascending: true);
    return [
      for (final r in rows)
        Topic(
          r['id'] as String,
          r['name'] as String,
          r['parent_id'] as String?,
        ),
    ];
  }

  Future<Map<String, String>> topicChoices() async {
    final rows = await _client.from('user_topics').select().eq('user_id', _me);
    return {
      for (final r in rows) r['topic_id'] as String: r['choice'] as String,
    };
  }

  Future<String?> sourceChoice(String id) async =>
      (await _client
              .from('user_sources')
              .select('choice')
              .eq('user_id', _me)
              .eq('source_id', id)
              .maybeSingle())?['choice']
          as String?;
  Future<void> followSource(String id) => _source(id, 'follow');
  Future<void> hideSource(String id) => _source(id, 'hide');
  Future<void> _source(String id, String choice) =>
      _client.from('user_sources').upsert({
        'user_id': _me,
        'source_id': id,
        'choice': choice,
      }, onConflict: 'user_id,source_id');
  Future<void> forgetSource(String id) => _client
      .from('user_sources')
      .delete()
      .eq('user_id', _me)
      .eq('source_id', id);
  Future<void> followTopic(String id) => _topic(id, 'follow');
  Future<void> hideTopic(String id) => _topic(id, 'hide');
  Future<void> _topic(String id, String choice) =>
      _client.from('user_topics').upsert({
        'user_id': _me,
        'topic_id': id,
        'choice': choice,
      }, onConflict: 'user_id,topic_id');
  Future<void> forgetTopic(String id) => _client
      .from('user_topics')
      .delete()
      .eq('user_id', _me)
      .eq('topic_id', id);
  Future<void> askForMoreCards(String id, String message) =>
      _client.from('content_requests').insert({
        'user_id': _me,
        'kind': 'more_cards',
        'source_id': id,
        'message': message.trim().isEmpty ? null : message.trim(),
      });
}
