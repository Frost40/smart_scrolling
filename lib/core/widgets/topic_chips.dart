import 'package:flutter/material.dart';

import '../../domain/models/topic.dart';
import '../theme/app_sizes.dart';
import 'section_card.dart';
import 'auto_scroll_row.dart';

/// Topics as one card per main area (D26): the area's name is the card's
/// title, its "All" chip means the whole area and its sub-topics are one
/// gliding row of chips inside; rows glide opposite ways card by card. A chosen area shows its sub-topics as chosen, because following an
/// area includes them (D34); tapping one of them then drops just that one
/// (see `toggleTopic`).
class TopicChips extends StatelessWidget {
  const TopicChips({
    super.key,
    required this.topics,
    required this.chosen,
    required this.onToggle,
    this.areas,
  });

  final List<Topic> topics;
  final Set<String> chosen;

  /// Null while saving, which disables every chip.
  final void Function(String id)? onToggle;

  /// Main-area ids to show, in this order; null shows every main area.
  final List<String>? areas;

  @override
  Widget build(BuildContext context) {
    final mains = topics.where((t) => t.parentId == null).toList();
    final shown = areas == null
        ? mains
        : [for (final id in areas!) ...mains.where((t) => t.id == id)];
    bool hasSubs(Topic main) => topics.any((t) => t.parentId == main.id);
    final solo = shown.where((t) => !hasSubs(t)).toList();
    final cards = shown.where(hasSubs).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        for (final (i, main) in cards.indexed)
          TopicArea(
            fromEnd: i.isOdd,
            area: main,
            subs: topics.where((t) => t.parentId == main.id).toList(),
            chosen: chosen,
            onToggle: onToggle,
          ),
        // Areas without sub-topics share one card, so the list stays short.
        if (solo.isNotEmpty)
          SectionCard(
            title: cards.isEmpty ? null : 'Other areas',
            children: [
              AutoScrollRow(
                fromEnd: cards.length.isOdd,
                children: [
                  for (final main in solo)
                    TopicChip(
                      topic: main,
                      chosen: chosen.contains(main.id),
                      onToggle: onToggle,
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

/// One main area: a card with the area's name, an "All" chip for the whole
/// area, and its sub-topics as one gliding row of chips.
class TopicArea extends StatelessWidget {
  const TopicArea({
    super.key,
    required this.area,
    required this.subs,
    required this.chosen,
    required this.onToggle,
    this.fromEnd = false,
  });

  final Topic area;
  final List<Topic> subs;
  final Set<String> chosen;
  final void Function(String id)? onToggle;

  /// Starts the sub-topic row at its far end (see [AutoScrollRow]).
  final bool fromEnd;

  @override
  Widget build(BuildContext context) {
    final whole = chosen.contains(area.id);
    return SectionCard(
      title: area.name,
      trailing: TopicChip(
        topic: area,
        label: 'All',
        chosen: whole,
        onToggle: onToggle,
      ),
      children: [
        AutoScrollRow(
          fromEnd: fromEnd,
          children: [
            for (final sub in subs)
              TopicChip(
                topic: sub,
                chosen: whole || chosen.contains(sub.id),
                onToggle: onToggle,
              ),
          ],
        ),
      ],
    );
  }
}

/// One topic: + when not chosen, ✓ when chosen (color is never the only
/// signal). The icon swaps in place, so the chip never changes size. A short
/// [label] such as "All" is read aloud as `All of <topic>`.
class TopicChip extends StatelessWidget {
  const TopicChip({
    super.key,
    required this.topic,
    required this.chosen,
    required this.onToggle,
    this.label,
  });

  final Topic topic;
  final bool chosen;
  final void Function(String id)? onToggle;
  final String? label;

  @override
  Widget build(BuildContext context) => FilterChip(
    key: Key('topic-${topic.id}'),
    label: Text(
      label ?? topic.name,
      semanticsLabel: label == null ? null : '$label of ${topic.name}',
    ),
    avatar: Icon(chosen ? Icons.check_rounded : Icons.add_rounded),
    selected: chosen,
    showCheckmark: false,
    onSelected: onToggle == null ? null : (_) => onToggle!(topic.id),
  );
}
