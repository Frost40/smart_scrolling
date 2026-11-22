import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_sizes.dart';
import '../../core/widgets/page_list.dart';
import '../../core/widgets/topic_chips.dart';
import 'onboarding_provider.dart';
import 'widgets/onboarding_buttons.dart';
import 'widgets/step_header.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<OnboardingProvider>();
    final step = p.steps.isEmpty ? null : p.steps[p.step];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your interests'),
        actions: [
          TextButton(
            key: const Key('onboarding-skip'),
            onPressed: p.saving ? null : p.skip,
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: AppDurations.of(context, AppDurations.enter),
              child: PageList(key: ValueKey(p.step), [
                if (p.loading) const LinearProgressIndicator(),
                if (p.error != null) ...[
                  Text(p.error!),
                  if (step == null)
                    TextButton(
                      onPressed: p.load,
                      child: const Text('Try again'),
                    ),
                ],
                if (step != null) ...[
                  StepHeader(
                    step: p.step,
                    count: p.steps.length,
                    title: step.title,
                    blurb: step.blurb,
                  ),
                  TopicChips(
                    topics: p.topics,
                    chosen: p.selected,
                    areas: step.areas,
                    onToggle: p.saving ? null : p.toggle,
                  ),
                ],
              ]),
            ),
          ),
          const OnboardingButtons(),
        ],
      ),
    );
  }
}
