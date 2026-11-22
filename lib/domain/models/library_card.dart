import 'discover_card.dart';

/// One card in the Library: a liked or saved Discover card with its place in the timetable.
class LibraryCard {
  const LibraryCard({
    required this.card,
    required this.at,
    this.topics = const {},
    this.nextReviewAt,
    this.reviewsPaused = false,
    this.hasTests = false,
    this.resumeAtSeconds,
    this.note,
    this.collectionIds = const {},
  });

  /// A `likes` or `saved_for_later` row with its `discover_cards` row embedded
  /// (topics from the source and the card, and the readable linked tests).
  factory LibraryCard.fromRow(
    Map<String, dynamic> row,
    DiscoverCard card, {
    required bool liked,
  }) {
    final cardRow = one(row['discover_cards']) ?? const {};
    final source = one(cardRow['sources']) ?? const {};
    final topics = <String, String>{};
    for (final link in [
      ...(source['source_topics'] as List? ?? const []),
      ...(cardRow['card_topics'] as List? ?? const []),
    ]) {
      final topic = one((link as Map)['topics']);
      if (topic != null) {
        topics[topic['id'] as String] = topic['name'] as String;
      }
    }
    final next = row['next_review_at'] as String?;
    return LibraryCard(
      card: card,
      at: DateTime.parse(row[liked ? 'liked_at' : 'saved_at'] as String),
      topics: topics,
      nextReviewAt: next == null ? null : DateTime.parse(next),
      reviewsPaused: row['reviews_paused'] == true,
      // A hidden test is not sent at all, so its link points at nothing.
      hasTests: (cardRow['practice_links'] as List? ?? const []).any(
        (l) => one((l as Map)['practice_cards']) != null,
      ),
      resumeAtSeconds: row['resume_at_seconds'] as int?,
      note: row['note'] as String?,
      collectionIds: {
        for (final c in row['collection_cards'] as List? ?? const [])
          c['collection_id'] as String,
      },
    );
  }

  final DiscoverCard card;

  /// When it was liked or saved; the Library shows the newest first.
  final DateTime at;

  /// Topic id → name, from the source and the card.
  final Map<String, String> topics;
  final DateTime? nextReviewAt;
  final bool reviewsPaused, hasTests;
  final int? resumeAtSeconds;
  final String? note;
  final Set<String> collectionIds;

  LibraryCard withPaused(bool paused) => LibraryCard(
    card: card,
    at: at,
    topics: topics,
    nextReviewAt: nextReviewAt,
    reviewsPaused: paused,
    hasTests: hasTests,
    resumeAtSeconds: resumeAtSeconds,
    note: note,
    collectionIds: collectionIds,
  );

  /// What a liked card says about its tests: paused, waiting for tests, or the next date.
  String reviewStatus(DateTime now) {
    if (reviewsPaused) return 'Reviews paused';
    if (!hasTests) return 'Waiting for tests';
    final next = nextReviewAt?.toLocal();
    if (next == null || !next.isAfter(now)) return 'Test due now';
    return 'Next test: ${next.day} ${_months[next.month - 1]}';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Search: title, front text and source title, any case.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        '${card.title}\n${card.front}\n${card.sourceTitle}'
            .toLowerCase()
            .contains(q);
  }
}
