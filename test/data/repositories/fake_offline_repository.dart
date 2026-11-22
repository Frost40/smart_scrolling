import 'package:flutter/foundation.dart';
import 'package:smart_scrolling/data/repositories/offline_repository.dart';
import 'package:smart_scrolling/domain/offline_mode.dart';

/// Stands in for the offline engine in widget tests: always online, nothing stored.
class FakeOfflineRepository extends ChangeNotifier
    implements OfflineRepository {
  @override
  bool online = true, wifi = true, mobileData = false, downloading = false;
  @override
  OfflineMode mode = OfflineMode.standard;
  @override
  int unseen = 0, liked = 0, later = 0, practice = 0, pending = 0;
  @override
  int usedBytes = 0;
  @override
  String? note;
  int refills = 0;
  @override
  bool get resetting => false;

  @override
  Future<void> use(String? userId) async {}

  @override
  void configure(String modeName, bool useMobileData) {
    mode = OfflineMode.parse(modeName);
    mobileData = useMobileData;
  }

  @override
  Future<void> refill() async => refills++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
