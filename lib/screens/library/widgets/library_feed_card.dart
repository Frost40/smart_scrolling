import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';

import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/discover_card_view.dart';
import '../../../domain/models/library_card.dart';
import '../../../data/repositories/discover_repository.dart';
import '../../../data/repositories/sharing_repository.dart';
import '../library_provider.dart';
import 'card_collections.dart';
import 'drag_auto_scroll.dart';

/// One card in the Library feed with what you can do to it: Remove (with Undo)
/// and, for a liked card, its next test and Pause / Resume reviews.
class LibraryFeedCard extends StatelessWidget {
  const LibraryFeedCard({super.key, required this.entry, required this.liked});

  final LibraryCard entry;

  /// True in the Liked tab, false in For later.
  final bool liked;

  @override
  Widget build(BuildContext context) {
    final p = context.read<LibraryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final id = entry.card.id;

    void say(String text, {SnackBarAction? action}) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));

    Future<void> remove() async {
      final done = await (liked ? p.removeLiked(entry) : p.removeLater(entry));
      if (!done) return say(p.actionError!);
      say(
        liked ? 'Removed from Liked' : 'Removed from For later',
        action: SnackBarAction(label: 'Undo', onPressed: p.undo),
      );
    }

    Future<void> togglePause() async {
      final done = await p.setPaused(entry, !entry.reviewsPaused);
      if (!done && p.actionError != null) say(p.actionError!);
    }

    final view = DiscoverCardView(
      card: entry.card,
      onShare: (origin) =>
          context.read<SharingRepository>().card(entry.card, origin),
      loadMedia: () => context.read<DiscoverRepository>().loadMedia(entry.card),
      onSourcePage: () => context
          .pushFrom('/source/${entry.card.sourceId}')
          .then((_) => p.refresh()),
      onOpenCard: (id) => context
          .pushFrom('/card?id=${Uri.encodeComponent(id)}')
          .then((_) => p.refresh()),
      note: entry.note,
      onEditNote: liked ? () => editLibraryNote(context, entry) : null,
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hold a liked card to drag it onto a collection.
          if (liked)
            LongPressDraggable<LibraryCard>(
              data: entry,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              onDragStarted: DragAutoScroll.of(context)?.start,
              feedback: DragPreview(title: entry.card.title),
              child: view,
            )
          else
            view,
          if (liked)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s),
              child: Row(
                children: [
                  Icon(
                    entry.reviewsPaused
                        ? Icons.pause_circle_outline
                        : Icons.event_repeat_rounded,
                    color: entry.reviewsPaused
                        ? context.colors.textMuted
                        : context.colors.due,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      entry.reviewStatus(DateTime.now()),
                      key: Key('status-$id'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              if (liked) AddToCollection(entry: entry),
              if (liked)
                CompactAction(
                  key: Key('pause-$id'),
                  tooltip: entry.reviewsPaused
                      ? 'Resume reviews'
                      : 'Pause reviews',
                  icon: entry.reviewsPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  label: entry.reviewsPaused ? 'Resume' : 'Pause',
                  onPressed: togglePause,
                ),
              CompactAction(
                key: Key('remove-$id'),
                tooltip: liked ? 'Remove from Liked' : 'Remove from For later',
                icon: Icons.delete_outline_rounded,
                label: 'Remove',
                onPressed: remove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The card's title under your finger while you drag it.
class DragPreview extends StatelessWidget {
  const DragPreview({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AppSizes.dragPreview,
    child: Card(
      child: ListTile(
        leading: const Icon(Icons.drive_file_move_outlined),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    ),
  );
}
