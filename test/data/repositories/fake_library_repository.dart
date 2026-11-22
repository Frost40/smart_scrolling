import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';
import 'package:smart_scrolling/domain/models/library_card.dart';

/// Liked and saved sample cards: even numbers are liked (newest first), odd are saved.
/// Card i is a concept for even i/2, a quote otherwise, from source a or b, about topic x or y.
List<LibraryCard> sampleLibrary(int count, {required bool liked}) => [
  for (var i = liked ? 0 : 1; i < count; i += 2)
    LibraryCard(
      card: DiscoverCard(
        id: 'sample-${i % 4 < 2 ? 'a' : 'b'}/card-$i',
        sourceId: 'sample-${i % 4 < 2 ? 'a' : 'b'}',
        format: (i ~/ 2).isEven ? 'concept' : 'quote',
        title: 'Card $i',
        front: 'Front text $i',
        sourceTitle: 'Sample ${i % 4 < 2 ? 'A' : 'B'}',
        sourceKind: 'book',
      ),
      at: DateTime.utc(2026, 10, 30).subtract(Duration(hours: i)),
      topics: {(i % 3 == 0 ? 'x' : 'y'): i % 3 == 0 ? 'Topic X' : 'Topic Y'},
      nextReviewAt: liked ? DateTime.utc(2030, 11, 3) : null,
      hasTests: i % 4 != 2,
    ),
];

/// Stands in for Supabase in tests: fixed lists and a record of what was changed.
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository({List<LibraryCard>? liked, List<LibraryCard>? later})
    : likedCards = liked ?? sampleLibrary(8, liked: true),
      laterCards = later ?? sampleLibrary(8, liked: false);

  final List<LibraryCard> likedCards, laterCards;
  final unliked = <String>[], restoredLikes = <String>[];
  final unsaved = <String>[], restoredSaves = <String>[];
  final pauses = <(String, bool)>[];
  bool fail = false;
  final collectionNames = <String, String>{};
  final notes = <String, String>{};
  final memberships = <(String, String, bool)>[];

  @override
  Future<Map<String, String>> collections() async {
    _check();
    return Map.of(collectionNames);
  }

  @override
  Future<String> createCollection(String name) async {
    _check();
    final id = 'collection-${collectionNames.length}';
    collectionNames[id] = name.trim();
    return id;
  }

  @override
  Future<void> renameCollection(String id, String name) async {
    _check();
    collectionNames[id] = name;
  }

  @override
  Future<void> deleteCollection(String id) async {
    _check();
    collectionNames.remove(id);
  }

  @override
  Future<void> saveNote(String cardId, String note) async {
    _check();
    notes[cardId] = note;
  }

  @override
  Future<void> setMembership(String cardId, String id, bool included) async {
    _check();
    memberships.add((cardId, id, included));
  }

  void _check() {
    if (fail) throw Exception('offline');
  }

  @override
  Future<List<LibraryCard>> liked() async {
    _check();
    return List.of(likedCards);
  }

  @override
  Future<List<LibraryCard>> later() async {
    _check();
    return List.of(laterCards);
  }

  @override
  Future<RemovedLike> unlike(String cardId) async {
    _check();
    unliked.add(cardId);
    return RemovedLike({'discover_card_id': cardId}, const []);
  }

  @override
  Future<void> restoreLike(RemovedLike removed) async {
    _check();
    restoredLikes.add(removed.like['discover_card_id'] as String);
  }

  @override
  Future<void> unsave(String cardId) async {
    _check();
    unsaved.add(cardId);
  }

  @override
  Future<void> restoreSaved(LibraryCard saved) async {
    _check();
    restoredSaves.add(saved.card.id);
  }

  @override
  Future<void> setReviewsPaused(String cardId, bool paused) async {
    _check();
    pauses.add((cardId, paused));
    final i = likedCards.indexWhere((c) => c.card.id == cardId);
    if (i >= 0) likedCards[i] = likedCards[i].withPaused(paused);
  }
}
