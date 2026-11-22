import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';
import 'package:smart_scrolling/domain/models/library_card.dart';

void main() {
  Map<String, dynamic> row({List<Object?> links = const []}) => {
    'liked_at': '2026-10-30T10:00:00+00:00',
    'next_review_at': '2026-10-31T10:00:00+00:00',
    'reviews_paused': false,
    'discover_cards': {
      'sources': {
        'source_topics': [
          {
            'topics': {'id': 'psychology', 'name': 'Psychology'},
          },
        ],
      },
      'card_topics': [
        {
          'topics': {'id': 'neuroscience', 'name': 'Neuroscience'},
        },
      ],
      'practice_links': links,
    },
  };
  const card = DiscoverCard(
    id: 's/c',
    sourceId: 's',
    format: 'concept',
    title: 'T',
    front: 'F',
  );

  test('reads the like, the topics of source and card, and linked tests', () {
    final c = LibraryCard.fromRow(
      row(
        links: [
          {
            'practice_cards': {'id': 's/p'},
          },
        ],
      ),
      card,
      liked: true,
    );
    expect(c.topics, {
      'psychology': 'Psychology',
      'neuroscience': 'Neuroscience',
    });
    expect(c.hasTests, true);
    expect(c.at, DateTime.utc(2026, 10, 30, 10));
    expect(c.nextReviewAt, DateTime.utc(2026, 10, 31, 10));
  });

  test('a link to a hidden test does not count as a test', () {
    final c = LibraryCard.fromRow(
      row(
        links: [
          {'practice_cards': null},
        ],
      ),
      card,
      liked: true,
    );
    expect(c.hasTests, false);
    expect(c.reviewStatus(DateTime.utc(2026, 10, 30)), 'Waiting for tests');
  });

  test('status: paused beats everything, due tests say so', () {
    final c = LibraryCard.fromRow(
      row(
        links: [
          {
            'practice_cards': {'id': 'x'},
          },
        ],
      ),
      card,
      liked: true,
    );
    expect(c.reviewStatus(DateTime.utc(2026, 10, 30)), 'Next test: 31 Oct');
    expect(c.reviewStatus(DateTime.utc(2026, 11, 2)), 'Test due now');
    expect(
      c.withPaused(true).reviewStatus(DateTime.utc(2026, 11, 2)),
      'Reviews paused',
    );
  });

  test('a saved row reads saved_at and the video position', () {
    final c = LibraryCard.fromRow(
      {
        'saved_at': '2026-10-29T08:00:00+00:00',
        'resume_at_seconds': 42,
        'discover_cards': {'sources': {}},
      },
      card,
      liked: false,
    );
    expect(c.at, DateTime.utc(2026, 10, 29, 8));
    expect(c.resumeAtSeconds, 42);
    expect(c.nextReviewAt, isNull);
  });
}
