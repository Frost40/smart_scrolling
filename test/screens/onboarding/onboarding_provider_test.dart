import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/topic.dart';
import 'package:smart_scrolling/domain/topic_groups.dart';
import 'package:smart_scrolling/screens/onboarding/onboarding_provider.dart';

import '../../data/repositories/fake_explore_repository.dart';

class FailingExplore extends FakeExploreRepository {
  bool fail = true;
  @override
  Future<void> followTopic(String id) async {
    if (fail) throw Exception('offline');
    await super.followTopic(id);
  }
}

class StarterExplore extends FakeExploreRepository {
  @override
  Future<List<Topic>> topicTree() async => const [
    Topic('physics', 'Physics'),
    Topic('psychology', 'Psychology'),
    Topic('economics', 'Economics'),
    Topic('personal-finance', 'Personal finance', 'economics'),
    Topic('markets', 'Markets', 'economics'),
    Topic('cooking', 'Cooking'),
  ];
}

void main() {
  test('Continue needs a choice; a failed save can retry', () async {
    final repo = FailingExplore()..fail = false;
    var finished = 0;
    final p = OnboardingProvider(repo, () => finished++);
    await Future<void>.delayed(Duration.zero);
    expect(p.canContinue, isFalse);
    await p.finish();
    expect(finished, 0);
    p.toggle('memory');
    repo.fail = true;
    await p.finish();
    expect(p.error, isNotNull);
    expect(finished, 0);
    repo.fail = false;
    await p.finish();
    expect(repo.choices, {'memory': 'follow'});
    expect(finished, 1);
    p.dispose();
  });

  test('Skip on step 2 forgets choices and saves nothing', () async {
    final repo = StarterExplore();
    var finished = 0;
    final p = OnboardingProvider(repo, () => finished++);
    await Future<void>.delayed(Duration.zero);
    expect(p.steps, hasLength(3));
    p.toggle('physics');
    p.next();
    p.toggle('psychology');
    expect(p.step, 1);
    p.skip();
    expect(finished, 1);
    expect(p.selected, isEmpty);
    expect(repo.choices, isEmpty);
    p.dispose();
  });

  test('steps keep macro areas together; new areas join the last step', () {
    final steps = stepsFor(const [
      Topic('economics', 'Economics'),
      Topic('personal-finance', 'Personal finance', 'economics'),
      Topic('markets', 'Markets', 'economics'),
      Topic('physics', 'Physics'),
      Topic('cooking', 'Cooking'),
    ]);
    expect(
      [for (final s in steps) s.areas],
      [
        ['physics'],
        ['economics', 'cooking'],
      ],
    );
  });
}
