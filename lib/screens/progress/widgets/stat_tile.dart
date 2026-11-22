import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';

/// One number of the week: the value large, its label and an optional note.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.note,
  });

  final IconData icon;
  final String label;

  /// The number, keyed by the caller so tests can read it.
  final Widget value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.xs,
          children: [
            Icon(icon, color: colors.primary),
            DefaultTextStyle.merge(style: text.headlineMedium, child: value),
            Text(label, style: text.titleSmall),
            if (note != null) Text(note!, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
