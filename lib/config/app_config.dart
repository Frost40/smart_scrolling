import 'package:flutter/foundation.dart';

/// Values read at start from --dart-define (see .env.mobile.json and .env.test.json).
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Release builds never contain the test login, even if the values are passed.
  static const testLoginEmail = kDebugMode
      ? String.fromEnvironment('TEST_LOGIN_EMAIL')
      : '';
  static const testLoginPassword = kDebugMode
      ? String.fromEnvironment('TEST_LOGIN_PASSWORD')
      : '';

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// The debug-only Test login button shows only when both values are present (A3-8).
  static bool get hasTestLogin =>
      testLoginEmail.isNotEmpty && testLoginPassword.isNotEmpty;
}
