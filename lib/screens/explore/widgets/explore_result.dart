import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../domain/models/source.dart';

/// One source in the results: cover, title, authors, kind and card count.
class ExploreResult extends StatelessWidget {
  const ExploreResult({super.key, required this.source});
  final Source source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final placeholder = Container(
      width: AppSizes.minTap,
      height: AppSizes.minTap,
      decoration: BoxDecoration(
        color: colors.tint(colors.primary),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Icon(Icons.menu_book_rounded, color: colors.primary),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.l,
          vertical: AppSpacing.s,
        ),
        leading: source.coverUrl == null
            ? placeholder
            : ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.field),
                child: Image.network(
                  source.coverUrl!,
                  width: AppSizes.minTap,
                  height: AppSizes.minTap,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => placeholder,
                ),
              ),
        title: Text(
          source.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          '${source.authors.join(', ')} · ${source.kind} · ${source.cardCount} cards',
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: colors.textMuted),
        onTap: () => context.pushFrom('/source/${source.id}'),
      ),
    );
  }
}
