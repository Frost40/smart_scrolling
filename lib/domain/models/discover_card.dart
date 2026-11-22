/// One Discover card as the app shows it, with the few source facts its back needs.
class DiscoverCard {
  const DiscoverCard({
    required this.id,
    required this.sourceId,
    required this.format,
    required this.title,
    required this.front,
    this.back,
    this.location,
    this.level,
    this.speaker,
    this.mediaPath,
    this.mediaUrl,
    this.mediaAlt,
    this.posterPath,
    this.posterUrl,
    this.captionsPath,
    this.transcript,
    this.sourceTitle = '',
    this.sourceKind = '',
    this.newspaper,
    this.publishedOn,
    this.related = const {},
    this.liked = false,
    this.note,
  });

  /// A `discover_cards` row, with its source embedded as `sources`.
  factory DiscoverCard.fromRow(
    Map<String, dynamic> row, {
    String? mediaUrl,
    String? posterUrl,
  }) {
    final source = one(row['sources']) ?? const {};
    final like = one(row['likes']);
    return DiscoverCard(
      id: row['id'] as String,
      sourceId: row['source_id'] as String,
      format: row['format'] as String,
      title: row['title'] as String,
      front: row['front'] as String,
      back: row['back'] as String?,
      location: row['location'] as String?,
      level: row['level'] as String?,
      speaker: row['speaker'] as String?,
      mediaPath: row['media_path'] as String?,
      mediaUrl: mediaUrl,
      mediaAlt: row['media_alt'] as String?,
      posterPath: row['poster_path'] as String?,
      posterUrl: posterUrl,
      captionsPath: row['captions_path'] as String?,
      transcript: row['transcript'] as String?,
      sourceTitle: source['title'] as String? ?? '',
      sourceKind: source['kind'] as String? ?? '',
      newspaper: one(source['news_details'])?['newspaper'] as String?,
      publishedOn: source['published_on'] as String?,
      related: {
        for (final link in [
          ...row['outgoing'] as List? ?? const [],
          ...row['incoming'] as List? ?? const [],
        ])
          if (one(link['card']) case final card?)
            card['id'] as String: card['title'] as String,
      },
      liked: like != null,
      note: like?['note'] as String?,
    );
  }

  final String id, sourceId, format, title, front, sourceTitle, sourceKind;
  final String? back, location, level, speaker, mediaPath, mediaUrl, mediaAlt;
  final String? newspaper, publishedOn;
  final String? posterPath, posterUrl, captionsPath, transcript;
  final Map<String, String> related;
  final bool liked;
  final String? note;
}

/// Fresh playback addresses and this account's resume persistence.
typedef CardMediaData = ({
  String url,
  String captions,
  int resume,
  Future<void> Function(int seconds) save,
});

/// An embedded one-to-one row: Supabase sends an object, or a list of at most one.
Map<String, dynamic>? one(Object? value) => switch (value) {
  final Map<String, dynamic> map => map,
  [final Map<String, dynamic> map, ...] => map,
  _ => null,
};
