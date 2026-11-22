import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scrolling/core/theme/theme_provider.dart';
import 'package:smart_scrolling/domain/models/app_settings.dart';
import 'package:smart_scrolling/screens/settings/widgets/theme_toggle.dart';
import 'package:smart_scrolling/screens/settings/widgets/theme_choice.dart';

void main() {
  testWidgets('Follow phone shows the phone mode; the switch turns it off', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final saved = <ThemeMode>[];
    final theme = ThemeProvider(() async => ThemeMode.system, (m) async {
      saved.add(m);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: const MaterialApp(home: Scaffold(body: ThemeChoice())),
      ),
    );
    await tester.pumpAndSettle();
    bool dark() => tester.widget<ThemeToggle>(find.byType(ThemeToggle)).dark;
    bool follow() => tester
        .widget<SwitchListTile>(find.byKey(const Key('theme-system')))
        .value;
    expect(follow(), isTrue);
    expect(dark(), isTrue, reason: 'the phone is dark');

    await tester.tap(find.byKey(const Key('theme-toggle')));
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.light);
    expect(follow(), isFalse);
    expect(dark(), isFalse);

    await tester.tap(find.byKey(const Key('theme-system')));
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.system);
    expect(dark(), isTrue);
    expect(saved, [ThemeMode.light, ThemeMode.system]);
  });

  test('text sizes: five steps around 100%, old values snap to a step', () {
    final s = AppSettings();
    expect(AppSettings.textSteps, hasLength(5));
    expect(AppSettings.textSteps[2], 1.0);
    expect(s.textStep, 1.0);
    s.textScale = 1.8;
    expect(s.textStep, 1.2);
    s.textScale = 0.85;
    expect(s.textStep, 0.85);
  });
}
