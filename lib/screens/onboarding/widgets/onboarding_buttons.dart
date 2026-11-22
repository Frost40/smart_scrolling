import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../onboarding_provider.dart';

/// Back and Next, or Continue on the last step (needs one chosen topic).
class OnboardingButtons extends StatelessWidget {
  const OnboardingButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OnboardingProvider>();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.s,
          children: [
            if (p.isLast && p.selected.isEmpty && !p.loading)
              const Text('Choose at least one topic, or Skip.'),
            Row(
              spacing: AppSpacing.m,
              children: [
                if (p.step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: p.saving ? null : p.back,
                      child: const Text('Back'),
                    ),
                  ),
                Expanded(
                  child: p.isLast
                      ? FilledButton(
                          key: const Key('onboarding-continue'),
                          onPressed: p.canContinue ? p.finish : null,
                          child: Text(
                            p.selected.isEmpty
                                ? 'Continue'
                                : 'Continue (${p.selected.length})',
                          ),
                        )
                      : FilledButton(
                          key: const Key('onboarding-next'),
                          onPressed: p.loading ? null : p.next,
                          child: const Text('Next'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
