import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_sizes.dart';
import '../../core/widgets/format_selector.dart';
import '../../core/widgets/enter_in.dart';
import '../../core/widgets/hold_to_refresh.dart';
import 'discover_provider.dart';
import 'widgets/discover_empty.dart';
import 'widgets/feed_card.dart';

/// Discover formats for the selector (D28), Mix first.
const discoverFormats = [
  'mix',
  'concept',
  'quote',
  'news',
  'research',
  'myth',
  'image',
  'video',
  'audio',
];

/// A vertical feed of full cards (D09), with hold-to-refresh on the top card (D10).
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DiscoverProvider>();
    final cards = p.cards;
    final end = !p.loading && p.exhausted && p.error == null;
    return HoldToRefresh(
      onRefresh: p.refresh,
      child: ListView.builder(
        key: const PageStorageKey('discover-feed'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.l,
          AppSpacing.l,
          AppSpacing.l,
          AppSpacing.xl,
        ),
        itemCount: cards.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return FormatSelector(
              label: 'Discover format',
              options: discoverFormats,
              value: p.filter,
              onChanged: p.setFilter,
            );
          }
          if (i <= cards.length) {
            return EnterIn(child: FeedCard(card: cards[i - 1]));
          }
          if (p.error != null) {
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.l),
              child: Column(
                children: [
                  Text(p.error!),
                  TextButton(
                    onPressed: cards.isEmpty ? p.refresh : p.loadMore,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          if (end) return const DiscoverEmpty();
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}
