import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/empty_art.dart';
import '../../../core/widgets/empty_state.dart';
import '../library_provider.dart';

/// The end of the Library feed: loading, a load error, or why the feed is empty.
class LibraryFooter extends StatelessWidget {
  const LibraryFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LibraryProvider>();
    final String message;
    if (p.loadError != null) {
      message = p.loadError!;
    } else if (!p.loaded) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (p.visible.isNotEmpty) {
      return const SizedBox(height: AppSpacing.xl);
    } else if (p.tabCards.isNotEmpty) {
      message = 'Nothing matches. Try other words or filters.';
    } else if (p.collectionId != null) {
      message =
          'This collection is empty. Hold a liked card and drag it onto the '
          'collection, or tap Collect under the card.';
    } else if (p.laterTab) {
      message =
          'Nothing saved for later yet. Tap For later on a Discover card.';
    } else {
      message = 'Nothing liked yet. Tap Like on a Discover card.';
    }
    if (p.loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            TextButton(onPressed: p.refresh, child: const Text('Try again')),
          ],
        ),
      );
    }
    return EmptyState(
      art: p.tabCards.isNotEmpty ? EmptyArtKind.search : EmptyArtKind.library,
      title: p.tabCards.isNotEmpty
          ? 'No matches'
          : p.laterTab
          ? 'Nothing for later'
          : 'Your shelf is waiting',
      message: message,
    );
  }
}
