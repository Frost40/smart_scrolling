import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';

import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/discover_card_view.dart';
import '../../../core/widgets/report_dialog.dart';
import '../../../domain/models/discover_card.dart';
import '../../../data/repositories/discover_repository.dart';
import '../../../data/repositories/sharing_repository.dart';
import '../discover_provider.dart';
import 'card_actions.dart';
import 'swipe_card.dart';

/// One card in the feed: swipeable, flippable, with Like and For later inside it.
/// Half of it on screen counts as seen (A3-4).
class FeedCard extends StatelessWidget {
  const FeedCard({super.key, required this.card});

  final DiscoverCard card;

  @override
  Widget build(BuildContext context) {
    final p = context.read<DiscoverProvider>();
    final messenger = ScaffoldMessenger.of(context);
    Future<void> report() async {
      final message = await showReportDialog(context);
      if (message == null) return;
      final sent = await p.reportProblem(card.id, message);
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

    return VisibilityDetector(
      key: Key('seen-${card.id}'),
      onVisibilityChanged: (info) => p.visible(card.id, info.visibleFraction),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.l),
        child: SwipeCard(
          onSwipe: (right) => p.swipe(card.id, right: right),
          child: DiscoverCardView(
            card: card,
            onShare: (origin) =>
                context.read<SharingRepository>().card(card, origin),
            loadMedia: () => context.read<DiscoverRepository>().loadMedia(card),
            onSourcePage: () => context
                .pushFrom('/source/${card.sourceId}')
                .then((_) => p.reloadCard(card.id)),
            onReport: report,
            onOpenCard: (id) => context
                .pushFrom('/card?id=${Uri.encodeComponent(id)}')
                .then((_) => p.reloadCard(card.id)),
            onEditNote: card.liked || p.liked.contains(card.id)
                ? () => context
                      .pushFrom(
                        '/card?id=${Uri.encodeComponent(card.id)}&edit=true',
                      )
                      .then((_) => p.reloadCard(card.id))
                : null,
            footer: CardActions(cardId: card.id),
          ),
        ),
      ),
    );
  }
}
