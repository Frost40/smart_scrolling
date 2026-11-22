import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_sizes.dart';
import '../../core/widgets/format_badge.dart';
import '../../core/widgets/heading.dart';
import '../../core/widgets/page_list.dart';
import '../../core/widgets/section_card.dart';
import 'progress_provider.dart';
import 'widgets/goal_ring.dart';
import 'widgets/stat_tile.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProgressProvider>();
    final s = p.summary;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: PageList([
        const Heading('Your learning this week'),
        Text('Monday to Sunday · your local time', style: text.bodyMedium),
        if (p.loading) const LinearProgressIndicator(),
        if (p.error != null) Text(p.error!),
        if (s != null && p.error == null) ...[
          SectionCard(
            children: [
              Center(
                child: GoalRing(days: s.days, goal: s.goal),
              ),
              Text(
                'Days practised this week',
                textAlign: TextAlign.center,
                style: text.titleMedium,
              ),
              Text(
                s.goal == null
                    ? 'No weekly goal set'
                    : 'Weekly goal: ${s.goal} days',
                textAlign: TextAlign.center,
                style: text.bodyMedium,
              ),
              TextButton(
                onPressed: () => context.push('/settings'),
                child: const Text('Set weekly goal'),
              ),
            ],
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.m,
              children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.favorite_rounded,
                    label: 'Liked cards',
                    value: Text('${s.liked}', key: const Key('progress-liked')),
                  ),
                ),
                Expanded(
                  child: StatTile(
                    icon: Icons.event_available_rounded,
                    label: 'Due today',
                    note: 'Includes overdue · paused reviews excluded',
                    value: Text('${s.due}', key: const Key('progress-due')),
                  ),
                ),
              ],
            ),
          ),
          StatTile(
            icon: Icons.task_alt_rounded,
            label: 'Tests answered this week',
            value: Text('${s.answered}', key: const Key('progress-answered')),
          ),
          SectionCard(
            title: 'Liked cards by format',
            children: [
              if (s.formats.isEmpty)
                const Text('Like a card in Discover to begin.'),
              for (final format in s.formats.entries)
                Row(
                  children: [
                    Expanded(
                      child: FormatBadge(
                        format: format.key,
                        label: format.key == 'unavailable'
                            ? 'Unavailable content'
                            : format.key,
                      ),
                    ),
                    Text('${format.value}', style: text.titleMedium),
                  ],
                ),
            ],
          ),
        ],
        if (p.error != null || !p.loading)
          TextButton(onPressed: p.load, child: const Text('Refresh progress')),
      ]),
    );
  }
}
