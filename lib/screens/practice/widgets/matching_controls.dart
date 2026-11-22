import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../domain/models/practice_card.dart';
import '../practice_provider.dart';

class MatchingControls extends StatelessWidget {
  const MatchingControls({super.key, required this.entry});
  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PracticeProvider>();
    final e = entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        const Text(
          'Tap a left item, then its right item. Tap again to change a pair.',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.m,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.s,
                children: [
                  for (var i = 0; i < e.test.matchLeft.length; i++)
                    Semantics(
                      selected: e.selectedLeft == i,
                      child: OutlinedButton(
                        key: Key('match-left-${e.card.id}-$i'),
                        onPressed: e.answer == null
                            ? () => p.selectLeft(e, i)
                            : null,
                        child: Column(
                          children: [
                            if (e.selectedLeft == i)
                              const Icon(Icons.touch_app),
                            Text(e.test.matchLeft[i]),
                            if (e.matches[i] != null)
                              Text('→ ${e.test.matchRight[e.matches[i]!]}'),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.s,
                children: [
                  for (final i in e.order)
                    Semantics(
                      selected: e.matches.contains(i),
                      child: OutlinedButton(
                        key: Key('match-right-${e.card.id}-$i'),
                        onPressed: e.answer == null && e.selectedLeft != null
                            ? () => p.pair(e, i)
                            : null,
                        child: Text(e.test.matchRight[i]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (e.answer == null)
          FilledButton(
            onPressed: e.matches.contains(null) ? null : () => p.answer(e),
            child: const Text('Check'),
          )
        else ...[
          const Text('Correct pairs:'),
          for (var i = 0; i < e.test.matchLeft.length; i++)
            Text('${e.test.matchLeft[i]} → ${e.test.matchRight[i]}'),
        ],
      ],
    );
  }
}
