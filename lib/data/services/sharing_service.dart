import 'dart:convert';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import '../../domain/models/discover_card.dart';

class SharingService {
  SharingService({Future<ShareResult> Function(ShareParams)? share})
    : _share = share ?? SharePlus.instance.share;
  final Future<ShareResult> Function(ShareParams) _share;

  Future<void> card(DiscoverCard card, Rect origin) async {
    final attribution = [
      card.speaker ?? card.sourceTitle,
      if (card.location?.isNotEmpty == true) card.location!,
    ].join(', ');
    await _share(
      ShareParams(
        text: '${card.front} — $attribution',
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> export(Map<String, dynamic> data, Rect origin) async {
    await _share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: ['smartscrolling-data.json'],
        sharePositionOrigin: origin,
      ),
    );
  }
}
