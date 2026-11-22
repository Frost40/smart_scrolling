import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';
import '../theme/theme_extensions.dart';

/// A card format's icon in a soft circle of its color, with an optional label.
class FormatBadge extends StatelessWidget {
  const FormatBadge({super.key, required this.format, this.label});

  final String format;

  /// Shown beside the icon, in the format's color.
  final String? label;

  static IconData iconFor(String format) => switch (format.toLowerCase()) {
    'concept' || 'idea' => Icons.lightbulb_outline_rounded,
    'quote' => Icons.format_quote_rounded,
    'news' => Icons.newspaper_rounded,
    'research' => Icons.science_outlined,
    'myth' => Icons.psychology_alt_outlined,
    'image' => Icons.image_outlined,
    'video' => Icons.play_circle_outline_rounded,
    'audio' => Icons.headphones_rounded,
    _ => Icons.auto_awesome_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = colors.format(format);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppSizes.badge,
          height: AppSizes.badge,
          decoration: BoxDecoration(
            color: colors.tint(color),
            shape: BoxShape.circle,
          ),
          child: ExcludeSemantics(
            child: Icon(
              iconFor(format),
              color: color,
              size: AppSizes.iconSmall,
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: AppSpacing.s),
          Flexible(
            child: Text(
              label!,
              style: Theme.of(context).textTheme.labelLarge!
                  .copyWith(color: color),
            ),
          ),
        ],
      ],
    );
  }
}
