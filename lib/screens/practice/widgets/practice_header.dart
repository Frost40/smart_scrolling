import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';

import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/empty_art.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/format_selector.dart';
import '../../../domain/models/practice_card.dart';
import '../practice_provider.dart';

/// The top of Practice: how many tests are due, Progress and the format menu.
class PracticeHeader extends StatelessWidget {
  const PracticeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PracticeProvider>();
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  if (p.loaded)
                    Text(
                      '${p.dueCount} due · ${p.waitingCount} waiting for tests',
                      style: text.titleMedium!.copyWith(
                        color: p.dueCount > 0 ? context.colors.due : null,
                      ),
                    ),
                  if (p.early)
                    Text(
                      'Practicing ahead of schedule',
                      style: text.bodyMedium,
                    ),
                ],
              ),
            ),
            // Its own context, so Progress grows out of this button.
            Builder(
              builder: (button) => TextButton.icon(
                onPressed: () => button.pushFrom('/progress'),
                icon: const Icon(Icons.insights_rounded),
                label: const Text('Progress'),
              ),
            ),
          ],
        ),
        FormatSelector(
          label: 'Practice format',
          options: practiceFilters,
          value: p.filter,
          onChanged: p.setFilter,
        ),
      ],
    );
  }
}

class PracticeFooter extends StatelessWidget {
  const PracticeFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PracticeProvider>();
    final practiceNow = p.dueCount == 0 && !p.early
        ? FilledButton.icon(
            onPressed: p.pending ? null : p.practiceNow,
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Practice now'),
          )
        : null;
    if (p.loaded &&
        !p.loading &&
        p.error == null &&
        !p.hasMore &&
        p.entries.isEmpty) {
      return EmptyState(
        art: EmptyArtKind.practice,
        title: p.early ? 'No tests yet' : 'All caught up',
        message: p.early
            ? 'No tests available yet. Like more cards in Discover.'
            : 'Nothing due in this format. Like cards in Discover to practice them.',
        actions: [?practiceNow],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          if (p.loading)
            const Center(child: CircularProgressIndicator())
          else if (p.error != null) ...[
            Text(p.error!, textAlign: TextAlign.center),
            if (!p.pending)
              TextButton(
                onPressed: p.retryLoad,
                child: const Text('Try again'),
              ),
          ] else if (p.hasMore)
            TextButton(onPressed: p.loadMore, child: const Text('Load more'))
          else if (p.loaded)
            ?practiceNow,
        ],
      ),
    );
  }
}
