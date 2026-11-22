import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/page_list.dart';
import '../../../core/widgets/topic_chips.dart';
import '../settings_provider.dart';

/// What you follow in one line, and a button that opens the topic chips.
class TopicSettings extends StatelessWidget {
  const TopicSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsProvider>();
    final names = [
      for (final t in p.topics)
        if (p.followed.contains(t.id)) t.name,
    ];
    final summary = names.isEmpty
        ? 'No topics yet. Discover shows a bit of everything.'
        : names.length <= 3
        ? 'You follow ${names.join(', ')}.'
        : 'You follow ${names.take(3).join(', ')} and ${names.length - 3} more.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s,
      children: [
        if (p.loading) const LinearProgressIndicator(),
        if (p.error != null) ...[
          Text(p.error!),
          TextButton(onPressed: p.load, child: const Text('Try again')),
        ],
        Text(summary),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('edit-topics'),
            onPressed: p.loading
                ? null
                : () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => ChangeNotifierProvider.value(
                      value: p,
                      child: const TopicSheet(),
                    ),
                  ),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Edit topics'),
          ),
        ),
      ],
    );
  }
}

/// Tap a topic to follow it; tap again to stop. Saved at once.
class TopicSheet extends StatelessWidget {
  const TopicSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsProvider>();
    return DraggableScrollableSheet(
      expand: false,
      builder: (_, scroll) => PageList(controller: scroll, [
        Text('Your topics', style: Theme.of(context).textTheme.titleLarge),
        const Text('Tap a topic to follow it. Tap it again to stop.'),
        if (p.error != null) Text(p.error!),
        TopicChips(
          topics: p.topics,
          chosen: p.followed,
          onToggle: p.busy ? null : p.toggleTopic,
        ),
      ]),
    );
  }
}
