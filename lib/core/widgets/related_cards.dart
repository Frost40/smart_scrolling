import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';

/// Published related cards; the caller owns navigation.
class RelatedCards extends StatelessWidget {
  const RelatedCards({super.key, required this.cards, required this.onOpen});
  final Map<String, String> cards;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => cards.isEmpty
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.m),
            Text('See also', style: Theme.of(context).textTheme.titleMedium),
            for (final c in cards.entries)
              TextButton.icon(
                key: Key('related-${c.key}'),
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => onOpen(c.key),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(c.value),
              ),
          ],
        );
}
