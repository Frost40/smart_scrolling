import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../settings_provider.dart';

class Preferences extends StatelessWidget {
  const Preferences({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        if (p.loading) const LinearProgressIndicator(),
        if (p.error != null) ...[
          Text(p.error!),
          TextButton(onPressed: p.load, child: const Text('Try again')),
        ],
        // Only English exists for now (D38); more appear here later.
        LabeledChoice(
          key: const Key('language'),
          label: 'Language',
          value: 'en',
          options: const {'en': 'English'},
          onChanged: (_) {},
        ),
        LabeledChoice(
          key: const Key('level'),
          label: 'Preferred level',
          value: p.level,
          options: const {
            'any': 'Any level',
            'intro': 'Intro',
            'intermediate': 'Intermediate',
            'advanced': 'Advanced',
          },
          onChanged: p.busy ? null : p.setLevel,
        ),
      ],
    );
  }
}

/// A setting's name on the left and its drop-down on the right; both shrink
/// with large text instead of running off the screen.
class LabeledChoice extends StatelessWidget {
  const LabeledChoice({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    spacing: AppSpacing.m,
    children: [
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      ),
      Flexible(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          // The chosen value sits next to the arrow.
          selectedItemBuilder: (_) => [
            for (final o in options.values)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(o, overflow: TextOverflow.ellipsis),
              ),
          ],
          items: [
            for (final o in options.entries)
              DropdownMenuItem(value: o.key, child: Text(o.value)),
          ],
          onChanged: onChanged == null ? null : (v) => onChanged!(v!),
        ),
      ),
    ],
  );
}
