import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_provider.dart';
import 'theme_toggle.dart';

/// Light or Dark with the sun/moon toggle, plus Follow phone. While Follow
/// phone is on, the toggle shows the phone's mode; tapping it turns Follow
/// phone off.
class ThemeChoice extends StatelessWidget {
  const ThemeChoice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final phoneDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final follow = theme.mode == ThemeMode.system;
    final dark = follow ? phoneDark : theme.mode == ThemeMode.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Theme',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ThemeToggle(
              key: const Key('theme-toggle'),
              dark: dark,
              onChanged: (on) =>
                  theme.setMode(on ? ThemeMode.dark : ThemeMode.light),
            ),
          ],
        ),
        SwitchListTile(
          key: const Key('theme-system'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Follow phone'),
          subtitle: const Text('Use your phone’s light or dark mode.'),
          value: follow,
          onChanged: (on) => theme.setMode(
            on
                ? ThemeMode.system
                : (phoneDark ? ThemeMode.dark : ThemeMode.light),
          ),
        ),
      ],
    );
  }
}
