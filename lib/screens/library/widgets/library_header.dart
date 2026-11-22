import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../library_provider.dart';
import 'filter_menu.dart';
import 'collections_section.dart';

/// The top of the Library feed: the two tabs, the search box and the filters.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LibraryProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.s,
          children: [
            ChoiceChip(
              key: const Key('library-tab-liked'),
              avatar: const Icon(Icons.favorite_rounded),
              label: const Text('Liked'),
              selected: !p.laterTab && p.collectionId == null,
              onSelected: (_) => p.showLater(false),
            ),
            ChoiceChip(
              key: const Key('library-tab-later'),
              avatar: const Icon(Icons.watch_later_rounded),
              label: const Text('For later'),
              selected: p.laterTab,
              onSelected: (_) => p.showLater(true),
            ),
          ],
        ),
        const CollectionsSection(),
        const SizedBox(height: AppSpacing.m),
        TextFormField(
          key: const Key('library-search'),
          initialValue: p.query,
          decoration: const InputDecoration(
            labelText: 'Search title, text or source',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: p.search,
        ),
        const SizedBox(height: AppSpacing.m),
        Row(
          children: [
            Expanded(
              child: FilterMenu(
                label: 'Format',
                options: {
                  for (final f in p.formats)
                    f: '${f[0].toUpperCase()}${f.substring(1)}',
                },
                value: p.format,
                onChanged: p.filterFormat,
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: FilterMenu(
                label: 'Topic',
                options: p.topics,
                value: p.topic,
                onChanged: p.filterTopic,
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: FilterMenu(
                label: 'Source',
                options: p.sources,
                value: p.source,
                onChanged: p.filterSource,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
