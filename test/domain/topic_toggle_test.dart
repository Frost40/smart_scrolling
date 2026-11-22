import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/topic.dart';
import 'package:smart_scrolling/domain/topic_groups.dart';

const topics = [
  Topic('cs', 'Computer science'),
  Topic('ai', 'AI', 'cs'),
  Topic('code', 'Programming', 'cs'),
  Topic('graphics', 'Graphics', 'cs'),
];

void main() {
  test('dropping one sub-topic of a chosen area keeps the others', () {
    expect(toggleTopic(topics, {'cs'}, 'ai'), {'code', 'graphics'});
  });

  test('choosing or dropping an area clears its sub-topics', () {
    expect(toggleTopic(topics, {'code', 'graphics'}, 'cs'), {'cs'});
    final dropped = toggleTopic(topics, {'cs'}, 'ai');
    expect(
      toggleTopic(topics, toggleTopic(topics, dropped, 'cs'), 'cs'),
      <String>{},
    );
  });

  test('choosing every sub-topic chooses the area', () {
    expect(toggleTopic(topics, {'code', 'graphics'}, 'ai'), {'cs'});
    expect(toggleTopic(topics, toggleTopic(topics, {'cs'}, 'ai'), 'ai'), {
      'cs',
    });
  });

  test('areas and sub-topics otherwise switch on and off', () {
    expect(toggleTopic(topics, {}, 'cs'), {'cs'});
    expect(toggleTopic(topics, {'cs'}, 'cs'), <String>{});
    expect(toggleTopic(topics, {}, 'ai'), {'ai'});
    expect(toggleTopic(topics, {'ai'}, 'ai'), <String>{});
  });
}
