import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';
import '../theme/theme_extensions.dart';

/// A rounded card that groups one section of a page, with an optional icon,
/// title and a [trailing] piece at the title's end.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    required this.children,
  });

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          if (title != null)
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: context.colors.primary),
                  const SizedBox(width: AppSpacing.m),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ?trailing,
              ],
            ),
          ...children,
        ],
      ),
    ),
  );
}
