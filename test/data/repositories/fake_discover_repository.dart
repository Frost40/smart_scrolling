import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';
import 'package:smart_scrolling/domain/models/source.dart';

/// [count] sample cards from two sources, formats taking turns.
List<DiscoverCard> sampleCards(int count) => [
  for (var i = 0; i < count; i++)
    DiscoverCard(
      id: 'sample-${i.isEven ? 'a' : 'b'}/card-$i',
      sourceId: 'sample-${i.isEven ? 'a' : 'b'}',
      format: const ['concept', 'quote', 'myth', 'news'][i % 4],
      title: 'Card $i',
      front: 'Front $i',
      back: 'Back $i',
      speaker: i % 4 == 1 ? 'Ada Sample' : null,
      sourceTitle: 'Sample ${i.isEven ? 'A' : 'B'}',
      sourceKind: 'book',
    ),
];

/// Stands in for Supabase in tests: a fixed card list and the person's marks.
class FakeDiscoverRepository implements DiscoverRepository {
  @override
  Future<CardMediaData> loadMedia(DiscoverCard card) async =>
      throw StateError('No sample media in this fake');
  @override
  Future<Map<String, String>> mediaLinks(List<String> paths) async => {};

  FakeDiscoverRepository({List<DiscoverCard>? cards})
    : cards = cards ?? sampleCards(30);

  final List<DiscoverCard> cards;
  final feedExcludes = <Set<String>>[];
  final seenBatches = <List<String>>[];
  final seen = <String>{}, liked = <String>{};
  final saved = <String, DateTime>{};
  final reports = <(String, String)>[];
  bool fail = false;

  void _check() {
    if (fail) throw Exception('offline');
  }

  @override
  Future<List<DiscoverCard>> feed({
    int limit = 20,
    Iterable<String> exclude = const [],
    String filter = 'mix',
  }) async {
    _check();
    feedExcludes.add(exclude.toSet());
    return cards
        .where((c) => !seen.contains(c.id) && !exclude.contains(c.id))
        .take(limit)
        .toList();
  }

  @override
  Future<void> like(String cardId) async {
    _check();
    liked.add(cardId);
    saved.remove(cardId);
    seen.add(cardId);
  }

  @override
  Future<void> undoLike(String cardId, {DateTime? savedAt}) async {
    _check();
    liked.remove(cardId);
    if (savedAt != null) saved[cardId] = savedAt;
  }

  @override
  Future<DateTime> saveForLater(String cardId) async {
    _check();
    seen.add(cardId);
    return saved[cardId] = DateTime.utc(2026, 10, 30, 12);
  }

  @override
  Future<void> unsave(String cardId) async {
    _check();
    saved.remove(cardId);
  }

  @override
  Future<void> markSeen(Iterable<String> cardIds) async {
    _check();
    seenBatches.add(cardIds.toList());
    seen.addAll(cardIds);
  }

  @override
  Future<void> reportProblem(String cardId, String message) async {
    _check();
    reports.add((cardId, message));
  }

  @override
  Future<List<DiscoverCard>> cardsFrom(
    List<Map<String, dynamic>> rows, {
    bool fromCache = false,
  }) => throw UnimplementedError();

  @override
  Future<DiscoverCard> card(String id) async {
    _check();
    return cards.firstWhere((c) => c.id == id);
  }

  @override
  Future<Source> source(String id) async {
    _check();
    return Source(
      id: id,
      kind: 'book',
      title: 'Sample book $id',
      authors: const ['Ada Sample'],
      details: const {'Publisher': 'Sample Press'},
      cards: cards.where((c) => c.sourceId == id).toList(),
    );
  }
}
