import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/empty_art.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/heading.dart';
import '../../core/widgets/page_list.dart';
import 'explore_provider.dart';
import 'widgets/explore_result.dart';
import 'widgets/topic_filter.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<ExploreProvider>();
    return PageList([
      const Heading('Find your next interest.'),
      TextFormField(
        key: ValueKey('explore-search'),
        decoration: const InputDecoration(
          labelText: 'Search titles, authors or topics',
          prefixIcon: Icon(Icons.search_rounded),
        ),
        onChanged: p.search,
      ),
      const TopicFilter(),
      if (p.loading) const LinearProgressIndicator(),
      if (p.error != null) ...[
        Text(p.error!),
        TextButton(onPressed: p.load, child: const Text('Try again')),
      ] else if (!p.loading && p.results.isEmpty)
        const EmptyState(
          art: EmptyArtKind.search,
          title: 'No matches',
          message: 'Try a broader search or another topic.',
        ),
      for (final source in p.results) ExploreResult(source: source),
    ]);
  }
}
