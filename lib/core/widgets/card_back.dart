import 'package:flutter/material.dart';

import '../../domain/models/discover_card.dart';
import '../theme/app_sizes.dart';
import '../theme/app_theme.dart';
import '../theme/theme_extensions.dart';
import 'related_cards.dart';

/// The compact back of a Discover card (D13, P04): a little more, where it is from,
/// and the Source page and Report a problem buttons.
class CardBack extends StatelessWidget {
  const CardBack({
    super.key,
    required this.card,
    this.onSourcePage,
    this.onReport,
    this.onShare,
    this.onOpenCard,
    this.onEditNote,
    this.note,
  });

  final DiscoverCard card;
  final VoidCallback? onSourcePage, onReport;
  final VoidCallback? onEditNote;
  final Future<void> Function(Rect origin)? onShare;
  final ValueChanged<String>? onOpenCard;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final c = card;
    final reading = text.reading;
    final facts = [
      ?c.location,
      [c.sourceTitle, c.sourceKind].where((s) => s.isNotEmpty).join(' · '),
      if (c.level != null) 'Level: ${c.level}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c.format == 'myth' ? 'Fact' : c.title, style: text.headlineSmall),
        const SizedBox(height: AppSpacing.m),
        if (c.back != null) Text(c.back!, style: reading),
        if (c.transcript case final transcript?) ...[
          const SizedBox(height: AppSpacing.m),
          Text('Transcript', style: text.titleMedium),
          Text(transcript, style: reading),
        ],
        const SizedBox(height: AppSpacing.l),
        // Where it comes from, in one quiet block.
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.cardMuted,
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.menu_book_rounded, color: colors.textMuted),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: AppSpacing.xs,
                    children: [
                      for (final f in facts) Text(f, style: text.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if ((note ?? c.note) case final value?) ...[
          const SizedBox(height: AppSpacing.m),
          Text('Your private note', style: text.titleMedium),
          Text(value, style: reading.copyWith(fontStyle: FontStyle.italic)),
        ],
        if (onEditNote != null)
          TextButton(onPressed: onEditNote, child: const Text('Edit note')),
        if (onOpenCard != null)
          RelatedCards(cards: c.related, onOpen: onOpenCard!),
        const SizedBox(height: AppSpacing.l),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            if (onShare != null)
              OutlinedButton.icon(
                onPressed: () async {
                  final box = context.findRenderObject() as RenderBox;
                  try {
                    await onShare!(box.localToGlobal(Offset.zero) & box.size);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'The share sheet could not open. Try again.',
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Share card'),
              ),
            if (onSourcePage != null)
              OutlinedButton.icon(
                key: Key('source-${c.id}'),
                onPressed: onSourcePage,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Source page'),
              ),
            if (onReport != null)
              TextButton.icon(
                key: Key('report-${c.id}'),
                onPressed: onReport,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Report a problem'),
              ),
          ],
        ),
      ],
    );
  }
}
