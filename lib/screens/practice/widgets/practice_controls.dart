import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../domain/models/practice_card.dart';
import '../practice_provider.dart';

class FlashcardControls extends StatelessWidget {
  const FlashcardControls({super.key, required this.entry});
  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PracticeProvider>();
    final e = entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.l,
      children: [
        if (!e.revealed)
          FilledButton(
            onPressed: () => p.reveal(e),
            child: const Text('Reveal'),
          )
        else ...[
          Text(e.test.answer!, style: Theme.of(context).textTheme.reading),
          if (e.answer == null)
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                for (final rating in ['Again', 'Hard', 'Good', 'Easy'])
                  OutlinedButton(
                    onPressed: () => p.answer(e, rating.toLowerCase()),
                    child: Text(rating),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

class ChoiceControls extends StatelessWidget {
  const ChoiceControls({super.key, required this.entry});
  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PracticeProvider>();
    final e = entry;
    final choices = e.test.type == 'true_false'
        ? const ['True', 'False']
        : e.test.choices;
    final correct = e.test.type == 'true_false'
        ? (e.test.isTrue! ? 0 : 1)
        : e.test.correctChoice!;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        for (var i = 0; i < choices.length; i++)
          Semantics(
            selected: e.choice == i,
            child: OutlinedButton(
              key: Key('choice-${e.card.id}-$i'),
              style: e.choice == i
                  ? OutlinedButton.styleFrom(
                      backgroundColor: colors.tint(colors.primary),
                      side: BorderSide(color: colors.primary),
                    )
                  : null,
              onPressed: e.answer == null ? () => p.choose(e, i) : null,
              child: Row(
                children: [
                  Icon(
                    e.answer != null && i == correct
                        ? Icons.check_circle
                        : e.answer != null && e.choice == i
                        ? Icons.cancel
                        : e.choice == i
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: e.answer != null && i == correct
                        ? colors.correct
                        : e.answer != null && e.choice == i
                        ? colors.wrong
                        : e.choice == i
                        ? colors.primary
                        : colors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(child: Text(choices[i])),
                ],
              ),
            ),
          ),
        if (e.answer == null)
          FilledButton(
            onPressed: e.choice == null ? null : () => p.answer(e),
            child: const Text('Check'),
          ),
        if (e.answer != null) Text('Correct answer: ${choices[correct]}'),
      ],
    );
  }
}
