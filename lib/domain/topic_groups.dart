import 'models/topic.dart';

/// One first-start step: main areas that belong to the same macro area.
class TopicStep {
  const TopicStep(this.title, this.blurb, this.areas);
  final String title, blurb;
  final List<String> areas;
}

/// Main areas grouped by meaning, never split (D46). Edit when topics.json
/// gains a main area; until then a new area lands in the last step.
const topicSteps = [
  TopicStep('Science and nature', 'How the world works, from atoms to cells.', [
    'physics',
    'biology',
    'mathematics',
  ]),
  TopicStep('Mind and technology', 'How we think, and the machines we build.', [
    'psychology',
    'computer-science',
  ]),
  TopicStep('People and society', 'Money, the past, stories and the news.', [
    'economics',
    'history',
    'literature',
    'society',
  ]),
];

/// [chosen] after a tap on [id]. A chosen area already holds all its
/// sub-topics, so dropping one of them keeps the others instead; choosing
/// every sub-topic chooses the area; choosing or dropping an area clears its
/// separate sub-topic choices (v2).
Set<String> toggleTopic(List<Topic> topics, Set<String> chosen, String id) {
  final next = {...chosen};
  final area = topics.where((t) => t.id == id).firstOrNull?.parentId;
  if (area != null && next.remove(area)) {
    return next..addAll([
      for (final t in topics)
        if (t.parentId == area && t.id != id) t.id,
    ]);
  }
  next.removeAll([
    for (final t in topics)
      if (t.parentId == id) t.id,
  ]);
  if (!next.remove(id)) next.add(id);
  final subs = [
    for (final t in topics)
      if (area != null && t.parentId == area) t.id,
  ];
  if (subs.isNotEmpty && subs.every(next.contains)) {
    next
      ..removeAll(subs)
      ..add(area!);
  }
  return next;
}

/// The steps for these topics: unknown main areas join the last step, and
/// steps with no area left are dropped.
List<TopicStep> stepsFor(List<Topic> topics) {
  final mains = [
    for (final t in topics)
      if (t.parentId == null) t.id,
  ];
  final known = {for (final s in topicSteps) ...s.areas};
  final steps = [
    for (final (i, s) in topicSteps.indexed)
      TopicStep(s.title, s.blurb, [
        ...s.areas.where(mains.contains),
        if (i == topicSteps.length - 1)
          ...mains.where((m) => !known.contains(m)),
      ]),
  ];
  return steps.where((s) => s.areas.isNotEmpty).toList();
}
