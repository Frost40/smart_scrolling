import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';

void main() {
  test(
    'related links merge both directions, deduplicate and omit hidden targets',
    () {
      final card = DiscoverCard.fromRow({
        'id': 'sample/a',
        'source_id': 'sample',
        'format': 'concept',
        'title': 'Sample',
        'front': 'Front',
        'outgoing': [
          {
            'card': {'id': 'sample/b', 'title': 'B'},
          },
          {'card': null},
        ],
        'incoming': [
          {
            'card': {'id': 'sample/c', 'title': 'C'},
          },
          {
            'card': {'id': 'sample/b', 'title': 'B'},
          },
        ],
        'likes': [
          {'note': 'Only mine'},
        ],
      });
      expect(card.related, {'sample/b': 'B', 'sample/c': 'C'});
      expect(card.liked, true);
      expect(card.note, 'Only mine');
    },
  );
}
