import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/empty_art.dart';
import '../../../core/widgets/empty_state.dart';
import '../discover_provider.dart';

/// The end of the feed: nothing new left here.
class DiscoverEmpty extends StatelessWidget {
  const DiscoverEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.read<DiscoverProvider>();
    return EmptyState(
      art: EmptyArtKind.cards,
      title: 'You’ve seen everything here',
      message: 'Fresh cards arrive as sources grow. Find new ones in Explore.',
      actions: [
        FilledButton.icon(
          key: const Key('discover-refresh'),
          onPressed: p.refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
        OutlinedButton.icon(
          onPressed: p.openExplore,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Explore sources'),
        ),
      ],
    );
  }
}
