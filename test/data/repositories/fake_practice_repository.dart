import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:smart_scrolling/domain/models/practice_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_discover_repository.dart';
import 'fake_offline_repository.dart';

class FakePracticeRepository extends PracticeRepository {
  FakePracticeRepository({int count = 12, this.early = false})
    : entries = [
        for (var i = 0; i < count; i++)
          PracticeEntry(
            card: FakeDiscoverRepository().cards[i % 20],
            test: PracticeCard(
              id: 'test-$i',
              type: i.isEven ? 'flashcard' : 'multiple_choice',
              prompt: 'Question $i',
              answer: 'Answer $i',
              choices: const ['No', 'Yes'],
              correctChoice: 1,
              explanation: 'Explanation $i',
            ),
            level: 0,
          ),
      ],
      super(
        SupabaseClient(
          'https://test.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
        FakeDiscoverRepository(),
        FakeOfflineRepository(),
      );

  final List<PracticeEntry> entries;
  bool early, failSave = false, failLoad = false, unavailable = false;
  final answers = <PracticeAnswer>[];

  PracticeBatch batch(
    int limit,
    String filter,
    Iterable<String> exclude,
    bool now,
  ) {
    if (failLoad) throw StateError('offline');
    final filtered = entries
        .where((e) => filter == 'mix' || e.test.type == filter)
        .toList();
    final remaining = filtered
        .where((e) => !e.saved && !exclude.contains(e.card.id))
        .toList();
    return PracticeBatch(
      now != early ? [] : remaining.take(limit).toList(),
      due: early ? 0 : filtered.where((e) => !e.saved).length,
      waiting: 2,
      hasMore: now == early && remaining.length > limit,
    );
  }

  @override
  Future<PracticeBatch> due({
    int limit = 10,
    String filter = 'mix',
    Iterable<String> exclude = const [],
  }) async => batch(limit, filter, exclude, false);

  @override
  Future<PracticeBatch> practiceNow({
    int limit = 10,
    String filter = 'mix',
    Iterable<String> exclude = const [],
  }) async => batch(limit, filter, exclude, true);

  @override
  Future<void> recordAnswer(PracticeAnswer answer) async {
    answers.add(answer);
    if (unavailable) throw const PracticeUnavailable();
    if (failSave) throw StateError('offline');
  }
}
