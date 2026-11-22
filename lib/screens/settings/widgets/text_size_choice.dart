import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/app_settings.dart';
import '../settings_provider.dart';

/// Five text sizes, today's 100% in the middle, between a small and a big "A".
class TextSizeChoice extends StatelessWidget {
  const TextSizeChoice({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsProvider>();
    final text = Theme.of(context).textTheme;
    const steps = AppSettings.textSteps;
    final index = steps.indexOf(p.s.textStep);
    String percent(int i) => '${(steps[i] * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Text size · ${percent(index)}', style: text.titleMedium),
        Row(
          children: [
            ExcludeSemantics(child: Text('A', style: text.bodySmall)),
            Expanded(
              child: Slider(
                key: const Key('text-size'),
                min: 0,
                max: steps.length - 1,
                divisions: steps.length - 1,
                value: index.toDouble(),
                label: percent(index),
                semanticFormatterCallback: (v) =>
                    'Text size ${percent(v.round())}',
                onChanged: (v) => p.setTextScale(steps[v.round()]),
              ),
            ),
            ExcludeSemantics(child: Text('A', style: text.headlineSmall)),
          ],
        ),
      ],
    );
  }
}
