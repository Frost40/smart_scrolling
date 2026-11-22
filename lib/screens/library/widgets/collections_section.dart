import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../domain/models/library_card.dart';
import '../library_provider.dart';
import 'collection_tile.dart';

/// "Collections (N)" folds and unfolds. Holding a dragged card over it for a
/// moment unfolds it, so the card can be dropped on a collection.
class CollectionsSection extends StatefulWidget {
  const CollectionsSection({super.key});

  @override
  State<CollectionsSection> createState() => _CollectionsSectionState();
}

class _CollectionsSectionState extends State<CollectionsSection> {
  Timer? _unfold;

  void _stop() {
    _unfold?.cancel();
    _unfold = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LibraryProvider>();
    final shown = p.collectionsShown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.m),
        Row(
          children: [
            Expanded(
              child: DragTarget<LibraryCard>(
                onWillAcceptWithDetails: (_) {
                  if (!p.collectionsShown) {
                    _unfold ??= Timer(
                      AppDurations.dragUnfold,
                      () => p.showCollections(true),
                    );
                  }
                  return false;
                },
                onLeave: (_) => _stop(),
                builder: (context, _, _) => Semantics(
                  expanded: shown,
                  child: InkWell(
                    key: const Key('collections-toggle'),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    onTap: () => p.showCollections(!shown),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.m,
                      ),
                      child: Row(
                        spacing: AppSpacing.xs,
                        children: [
                          Flexible(
                            child: Text(
                              'Collections (${p.collections.length})',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Icon(
                            shown
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('new-collection'),
              onPressed: p.busy ? null : () => editCollection(context),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('New'),
            ),
          ],
        ),
        AnimatedSize(
          duration: AppDurations.of(context, AppDurations.quick),
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shown && p.collections.isEmpty)
                const Text(
                  'Make a folder for your liked cards, then hold a card and drag it onto the folder.',
                ),
              // A folded list still shows the open collection, so you can leave it.
              for (final c in p.collections.entries)
                if (shown || c.key == p.collectionId)
                  CollectionTile(id: c.key, name: c.value),
            ],
          ),
        ),
      ],
    );
  }
}
