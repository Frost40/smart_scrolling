import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/heading.dart';
import '../../../domain/models/source.dart';

/// The top of a source page: cover, title, authors, kind details, date,
/// description and the link.
class SourceHeader extends StatelessWidget {
  const SourceHeader({super.key, required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final s = source;
    final text = Theme.of(context).textTheme;
    final link = s.link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.coverUrl != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.l),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.image),
                child: Image.network(
                  s.coverUrl!,
                  height: AppSizes.cardImageHeight,
                  fit: BoxFit.contain,
                  semanticLabel: 'Cover of ${s.title}',
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        Heading(s.title),
        if (s.authors.isNotEmpty)
          Text(s.authors.join(', '), style: text.titleMedium),
        const SizedBox(height: AppSpacing.s),
        Text(
          [
            '${s.kind[0].toUpperCase()}${s.kind.substring(1)}',
            ?s.publishedOn,
          ].join(' · '),
          style: text.bodyMedium,
        ),
        for (final d in s.details.entries)
          Text('${d.key}: ${d.value}', style: text.bodyMedium),
        if (s.description != null) ...[
          const SizedBox(height: AppSpacing.m),
          Text(s.description!, style: text.bodyLarge),
        ],
        if (link != null) ...[
          const SizedBox(height: AppSpacing.m),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(link),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open the link'),
          ),
        ],
      ],
    );
  }
}
