import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_scrolling/data/services/sharing_service.dart';
import 'package:smart_scrolling/domain/models/discover_card.dart';

void main() {
  test(
    'card attribution and a valid JSON export are sent to the share sheet',
    () async {
      final sent = <ShareParams>[];
      final service = SharingService(
        share: (params) async {
          sent.add(params);
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      );
      const card = DiscoverCard(
        id: 'sample/card',
        sourceId: 'sample',
        format: 'quote',
        title: 'Sample',
        front: 'Sample text',
        speaker: 'Sample speaker',
        sourceTitle: 'Sample source',
        location: 'p. 3',
      );
      await service.card(card, Rect.zero);
      expect(sent.single.text, 'Sample text — Sample speaker, p. 3');
      final data = {
        'profiles': [],
        'likes': [
          {'note': 'Private Ω'},
        ],
      };
      await service.export(data, Rect.zero);
      expect(sent.last.fileNameOverrides, ['smartscrolling-data.json']);
      expect(
        jsonDecode(utf8.decode(await sent.last.files!.single.readAsBytes())),
        data,
      );
    },
  );
}
