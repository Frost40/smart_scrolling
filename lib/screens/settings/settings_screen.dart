import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/heading.dart';
import '../../core/widgets/page_list.dart';
import '../../core/widgets/section_card.dart';
import 'widgets/offline_settings.dart';
import 'widgets/preferences.dart';
import 'settings_provider.dart';
import 'widgets/text_size_choice.dart';
import 'widgets/theme_choice.dart';
import 'widgets/topic_settings.dart';
import 'widgets/learning_settings.dart';
import 'widgets/your_data.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsProvider>();
    final s = p.s;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageList([
        const Heading('Make room for your interests.'),
        const SectionCard(
          title: 'Topics',
          icon: Icons.interests_rounded,
          children: [TopicSettings()],
        ),
        const SectionCard(
          title: 'Language and level',
          icon: Icons.translate_rounded,
          children: [Preferences()],
        ),
        const SectionCard(
          title: 'Your learning rhythm',
          icon: Icons.event_repeat_rounded,
          children: [LearningSettings()],
        ),
        SectionCard(
          title: 'Appearance',
          icon: Icons.palette_outlined,
          children: [
            const ThemeChoice(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduce motion'),
              subtitle: const Text(
                'Use immediate transitions instead of card animations.',
              ),
              value: s.reducedMotion,
              onChanged: p.setReducedMotion,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Higher contrast'),
              value: s.highContrast,
              onChanged: p.setHighContrast,
            ),
            const TextSizeChoice(),
          ],
        ),
        const SectionCard(
          title: 'Offline',
          icon: Icons.cloud_download_outlined,
          children: [OfflineSettings()],
        ),
        const SectionCard(
          title: 'Your data',
          icon: Icons.shield_outlined,
          children: [YourData()],
        ),
        Text(
          'Theme, motion, contrast, text size and offline choices are saved online for this phone.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ]),
    );
  }
}
