import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_scrolling/core/theme/theme_provider.dart';
import 'package:smart_scrolling/data/repositories/theme_repository.dart';
import 'package:smart_scrolling/data/services/local_store.dart';

ThemeProvider provider() {
  final repo = ThemeRepository(LocalStore());
  return ThemeProvider(repo.load, repo.save);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'starts on Follow phone and remembers the choice after a restart',
    () async {
      final first = provider();
      await Future<void>.delayed(Duration.zero);
      expect(first.mode, ThemeMode.system);
      first.setMode(ThemeMode.dark);
      await Future<void>.delayed(Duration.zero);

      final restarted = provider();
      await Future<void>.delayed(Duration.zero);
      expect(restarted.mode, ThemeMode.dark);
    },
  );
}
