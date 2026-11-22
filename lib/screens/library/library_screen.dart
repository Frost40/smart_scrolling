import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_sizes.dart';
import '../../core/widgets/enter_in.dart';
import '../../core/widgets/hold_to_refresh.dart';
import 'library_provider.dart';
import 'widgets/drag_auto_scroll.dart';
import 'widgets/library_feed_card.dart';
import 'widgets/library_footer.dart';
import 'widgets/library_header.dart';

/// Two feeds of full cards, Liked and For later (D09), with hold-to-refresh on the top card (D10).
/// Dragging a card to the top or bottom edge scrolls the list.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LibraryProvider>();
    final cards = p.visible;
    return DragAutoScroll(
      child: HoldToRefresh(
        onRefresh: p.refresh,
        child: ListView.builder(
          // Each tab has its own scroll place.
          key: PageStorageKey('library-${p.laterTab}'),
          primary: true,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.l),
          itemCount: cards.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) return const LibraryHeader();
            if (i <= cards.length) {
              return EnterIn(
                key: ValueKey('${p.laterTab}-${cards[i - 1].card.id}'),
                child: LibraryFeedCard(entry: cards[i - 1], liked: !p.laterTab),
              );
            }
            return const LibraryFooter();
          },
        ),
      ),
    );
  }
}
