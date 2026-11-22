import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:smart_scrolling/domain/models/topic.dart';
import 'package:smart_scrolling/domain/models/source.dart';

class FakeExploreRepository implements ExploreRepository {
  final choices = <String, String>{}, sources = <String, String>{};
  final requests = <(String, String)>[];
  @override
  Future<List<Topic>> topicTree() async => [
    const Topic('learning', 'Learning'),
    const Topic('memory', 'Memory', 'learning'),
    const Topic('focus', 'Focus', 'learning'),
  ];
  @override
  Future<List<Source>> searchSources(String text) async => [
    const Source(
      id: 'sample-a',
      kind: 'book',
      title: 'Sample source',
      cardCount: 3,
    ),
  ];
  @override
  Future<List<Source>> sourcesByTopic(String id) => searchSources('');
  @override
  Future<Map<String, String>> topicChoices() async => Map.of(choices);
  @override
  Future<String?> sourceChoice(String id) async => sources[id];
  @override
  Future<void> followSource(String id) async {
    sources[id] = 'follow';
  }

  @override
  Future<void> hideSource(String id) async {
    sources[id] = 'hide';
  }

  @override
  Future<void> forgetSource(String id) async {
    sources.remove(id);
  }

  @override
  Future<void> followTopic(String id) async {
    choices[id] = 'follow';
  }

  @override
  Future<void> hideTopic(String id) async {
    choices[id] = 'hide';
  }

  @override
  Future<void> forgetTopic(String id) async {
    choices.remove(id);
  }

  @override
  Future<void> askForMoreCards(String id, String message) async {
    requests.add((id, message));
  }
}
