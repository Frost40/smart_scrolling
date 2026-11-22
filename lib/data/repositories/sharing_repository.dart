import 'dart:ui';

import '../../domain/models/discover_card.dart';
import '../services/sharing_service.dart';

class SharingRepository {
  SharingRepository() : _service = SharingService();
  final SharingService _service;
  Future<void> card(DiscoverCard card, Rect origin) =>
      _service.card(card, origin);
  Future<void> export(Map<String, dynamic> data, Rect origin) =>
      _service.export(data, origin);
}
