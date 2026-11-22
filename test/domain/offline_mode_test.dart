import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/offline_mode.dart';

void main() {
  test('each mode keeps the A3-13 sizes', () {
    expect(
      [
        for (final m in OfflineMode.values)
          (m.dbName, m.discoverCards, m.practiceWindow, m.forLater, m.capBytes),
      ],
      [
        ('online_only', 0, 0, 0, 0),
        ('light', 200, 80, 20, 256 << 20),
        ('standard', 500, 200, 50, 512 << 20),
        ('extended', 1000, 400, 100, 1 << 30),
      ],
    );
  });

  test('a refill asks only for the cards missing in each mode', () {
    expect(
      [for (final m in OfflineMode.values) m.cardsToFetch(0)],
      [0, 200, 500, 1000],
    );
    expect(
      [for (final m in OfflineMode.values) m.cardsToFetch(300)],
      [0, 0, 200, 700],
    );
    expect(OfflineMode.extended.cardsToFetch(1200), 0);
  });

  test('unknown or empty values mean Standard', () {
    expect(OfflineMode.parse('online_only'), OfflineMode.onlineOnly);
    expect(OfflineMode.parse(null), OfflineMode.standard);
    expect(OfflineMode.parse('huge'), OfflineMode.standard);
  });
}
