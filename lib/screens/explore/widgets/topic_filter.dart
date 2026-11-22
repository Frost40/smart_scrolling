import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../domain/models/topic.dart';
import '../explore_provider.dart';
import 'topic_cloud.dart';

/// Main areas in one sideways row. An area with sub-topics opens them under
/// the row on the first tap; the area and its sub-topics then sit on one
/// soft shape of the main color's tint. Choosing works as in Settings (see
/// `ExploreProvider.tapTopic`).
class TopicFilter extends StatefulWidget {
  const TopicFilter({super.key});

  @override
  State<TopicFilter> createState() => _TopicFilterState();
}

class _TopicFilterState extends State<TopicFilter> {
  final _row = ScrollController();
  final _box = GlobalKey(), _chip = GlobalKey(), _strip = GlobalKey();

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ExploreProvider>();
    final subs = p.topics.where((t) => t.parentId == p.open).toList();
    final open = p.open != null && subs.isNotEmpty;
    return CustomPaint(
      key: _box,
      painter: open
          ? TopicCloudPainter(
              box: _box,
              chip: _chip,
              strip: _strip,
              color: context.colors.tint(context.colors.primary),
              repaint: _row,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TopicRow(
            topics: p.topics.where((t) => t.parentId == null).toList(),
            controller: _row,
            openKey: _chip,
          ),
          if (open) SubTopicStrip(key: _strip, subs: subs),
        ],
      ),
    );
  }
}

/// The open area's sub-topics, on the shape the filter paints behind them.
class SubTopicStrip extends StatelessWidget {
  const SubTopicStrip({super.key, required this.subs});
  final List<Topic> subs;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.s),
    child: TopicRow(topics: subs, inCloud: true),
  );
}

/// One sideways row of topic chips. The open area's chip gets [openKey], so
/// the shape behind it can find it.
class TopicRow extends StatelessWidget {
  const TopicRow({
    super.key,
    required this.topics,
    this.controller,
    this.openKey,
    this.inCloud = false,
  });
  final List<Topic> topics;
  final ScrollController? controller;
  final GlobalKey? openKey;
  final bool inCloud;

  @override
  Widget build(BuildContext context) {
    final open = context.watch<ExploreProvider>().open;
    return SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: AppSpacing.s,
        children: [
          for (final t in topics)
            KeyedSubtree(
              key: t.id == open ? openKey : null,
              child: FilterTopicChip(
                key: Key('explore-topic-${t.id}'),
                topic: t,
                inCloud: inCloud || t.id == open,
              ),
            ),
        ],
      ),
    );
  }
}

/// One Explore topic chip. Chosen shows ✓: an area also while one of its
/// sub-topics is, a sub-topic also while its whole area is (as in Settings).
/// An area with sub-topics otherwise shows an arrow, so it reads as "opens";
/// any other topic shows +. Icons swap in place, so the chip keeps its size.
/// On the shape ([inCloud]) chips are plain card color and chosen ones
/// fill with the main color, so they stand out on its tint.
class FilterTopicChip extends StatelessWidget {
  const FilterTopicChip({super.key, required this.topic, this.inCloud = false});
  final Topic topic;
  final bool inCloud;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ExploreProvider>();
    final on =
        p.chosen.contains(topic.id) ||
        p.chosen.contains(topic.parentId) ||
        p.topics.any((t) => t.parentId == topic.id && p.chosen.contains(t.id));
    final opens = p.topics.any((t) => t.parentId == topic.id);
    final colors = context.colors;
    final filled = inCloud && on;
    return ChoiceChip(
      backgroundColor: inCloud ? colors.card : null,
      selectedColor: inCloud ? colors.primary : null,
      labelStyle: filled
          ? Theme.of(context).chipTheme.labelStyle
                ?.copyWith(color: colors.onPrimary)
          : null,
      label: Text(topic.name),
      avatar: Icon(
        color: filled ? colors.onPrimary : null,
        on
            ? Icons.check_rounded
            : !opens
            ? Icons.add_rounded
            : p.open == topic.id
            ? Icons.expand_less_rounded
            : Icons.expand_more_rounded,
      ),
      showCheckmark: false,
      selected: on,
      onSelected: (_) => p.tapTopic(topic.id),
    );
  }
}
