/// The phone's navigation and accessibility settings; learning lives online.
class AppSettings {
  int tab = 0;

  /// The first start (choose interests) was finished or skipped on this phone.
  bool onboarded = false;
  bool reducedMotion = false, highContrast = false;
  double textScale = 1;

  /// Text sizes Settings offers, today's 100% in the middle (D46).
  static const textSteps = [0.85, 0.92, 1.0, 1.1, 1.2];

  /// The offered step nearest the saved size (an older 1.8 shows as 1.2).
  double get textStep => textSteps.reduce(
    (a, b) => (a - textScale).abs() <= (b - textScale).abs() ? a : b,
  );

  /// `devices.offline_mode` and `devices.download_on_mobile_data` (A3-13).
  String offlineMode = 'standard';
  bool mobileData = false;
  Map<String, dynamic> toJson() => {'tab': tab, 'onboarded': onboarded};
  static AppSettings fromJson(Map<String, dynamic> row) => AppSettings()
    ..tab = (row['tab'] is int && row['tab'] >= 0 && row['tab'] < 4)
        ? row['tab'] as int
        : 0
    ..onboarded = row['onboarded'] == true;
}
