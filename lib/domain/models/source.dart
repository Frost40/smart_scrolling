import 'discover_card.dart';

/// One source for its source page: the facts, the kind details and its published cards in order.
class Source {
  const Source({
    required this.id,
    required this.kind,
    required this.title,
    this.authors = const [],
    this.publishedOn,
    this.description,
    this.link,
    this.coverUrl,
    this.details = const {},
    this.cards = const [],
    this.cardCount = 0,
  });

  /// A `sources` row with `book_details`, `paper_details` and `news_details` embedded.
  factory Source.fromRow(
    Map<String, dynamic> row, {
    String? coverUrl,
    List<DiscoverCard> cards = const [],
    int cardCount = 0,
  }) {
    final book = one(row['book_details']) ?? const {};
    final paper = one(row['paper_details']) ?? const {};
    final news = one(row['news_details']) ?? const {};
    final details = <String, Object?>{
      'Publisher': book['publisher'],
      'Edition': book['edition'],
      'Pages': book['pages'],
      'ISBN': book['isbn'],
      'Journal': paper['journal'],
      'DOI': paper['doi'],
      'Paper status': paper['paper_status'],
      'Newspaper': news['newspaper'],
    };
    return Source(
      id: row['id'] as String,
      kind: row['kind'] as String,
      title: row['title'] as String,
      authors: (row['authors'] as List? ?? const []).cast<String>(),
      publishedOn: row['published_on'] as String?,
      description: row['description'] as String?,
      link: row['link'] as String?,
      coverUrl: coverUrl,
      details: {
        for (final e in details.entries)
          if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
      },
      cards: cards,
      cardCount: cardCount,
    );
  }

  final int cardCount;
  final String id, kind, title;
  final List<String> authors;
  final String? publishedOn, description, link, coverUrl;

  /// Kind details as label → value, only the ones that are filled in.
  final Map<String, String> details;
  final List<DiscoverCard> cards;
}
