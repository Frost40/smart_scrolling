import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';

/// "Step 2 of 3", a thin progress bar, the step's title and what it covers.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.step,
    required this.count,
    required this.title,
    required this.blurb,
  });

  final int step, count;
  final String title, blurb;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.s,
      children: [
        Text('Step ${step + 1} of $count', style: text.labelLarge),
        LinearProgressIndicator(
          value: (step + 1) / count,
          semanticsLabel: 'Step ${step + 1} of $count',
        ),
        const SizedBox(height: AppSpacing.s),
        Text(title, style: text.headlineSmall),
        Text(blurb, style: text.bodyLarge),
      ],
    );
  }
}
