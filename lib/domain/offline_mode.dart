/// How much the phone keeps for offline use (A3-13). The names match `devices.offline_mode`.
enum OfflineMode {
  onlineOnly(0, 0, 0, 0),
  light(200, 80, 20, 256),
  standard(500, 200, 50, 512),
  extended(1000, 400, 100, 1024);

  const OfflineMode(
    this.discoverCards,
    this.practiceWindow,
    this.forLater,
    int capMegabytes,
  ) : capBytes = capMegabytes * 1024 * 1024;

  final int discoverCards, practiceWindow, forLater, capBytes;

  /// The `devices.offline_mode` value.
  String get dbName => switch (this) {
    onlineOnly => 'online_only',
    _ => name,
  };

  /// Unknown values fall back to Standard, the default.
  static OfflineMode parse(String? value) => values.firstWhere(
    (m) => m.dbName == value,
    orElse: () => OfflineMode.standard,
  );

  /// How many new Discover cards a refill asks for when [unseen] are already on the phone.
  int cardsToFetch(int unseen) =>
      unseen >= discoverCards ? 0 : discoverCards - unseen;
}
