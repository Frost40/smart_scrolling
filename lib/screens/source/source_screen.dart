import 'package:flutter/material.dart';

import '../../routing/app_router.dart';

import 'package:provider/provider.dart';

import '../../core/widgets/discover_card_view.dart';
import '../../data/repositories/discover_repository.dart';
import '../../data/repositories/sharing_repository.dart';
import '../../core/widgets/heading.dart';
import '../../core/widgets/page_list.dart';
import '../../core/widgets/report_dialog.dart';
import '../../core/widgets/related_cards.dart';
import 'source_provider.dart';
import 'widgets/source_header.dart';
import 'widgets/source_actions.dart';

/// How many cards the source page shows.
const previewCards = 3;

/// Everything about one source (D13): cover, facts, link and its first cards.
class SourceScreen extends StatelessWidget {
  const SourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SourceProvider>();
    final source = p.source;
    final messenger = ScaffoldMessenger.of(context);
    Future<void> report(String cardId) async {
      final message = await showReportDialog(context);
      if (message == null) return;
      final sent = await p.reportProblem(cardId, message);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Thanks. The problem is on the owner’s to-do list.'
                : 'The report could not be sent. Check your connection.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Source')),
      body: source == null
          ? p.error == null
                ? const Center(child: CircularProgressIndicator())
                : PageList([
                    Text(p.error!),
                    FilledButton(
                      onPressed: p.load,
                      child: const Text('Try again'),
                    ),
                  ])
          : PageList([
              SourceHeader(source: source),
              const SourceActions(),
              RelatedCards(
                cards: {for (final c in source.cards) ...c.related},
                onOpen: (id) => context
                    .pushFrom('/card?id=${Uri.encodeComponent(id)}')
                    .then((_) => p.load()),
              ),
              Heading(
                source.cards.isEmpty ? 'No cards yet' : 'A few of its cards',
              ),
              if (source.cards.length > previewCards)
                Text(
                  '${source.cards.length} cards in this source. '
                  'Follow it to see them all in Discover.',
                ),
              // A taste of the source, not all of it (D46).
              for (final card in source.cards.take(previewCards))
                DiscoverCardView(
                  card: card,
                  onShare: (origin) =>
                      context.read<SharingRepository>().card(card, origin),
                  loadMedia: () =>
                      context.read<DiscoverRepository>().loadMedia(card),
                  onReport: () => report(card.id),
                  onOpenCard: (id) => context
                      .pushFrom('/card?id=${Uri.encodeComponent(id)}')
                      .then((_) => p.load()),
                  onEditNote: card.liked
                      ? () => context
                            .pushFrom(
                              '/card?id=${Uri.encodeComponent(card.id)}&edit=true',
                            )
                            .then((_) => p.load())
                      : null,
                ),
            ]),
    );
  }
}
