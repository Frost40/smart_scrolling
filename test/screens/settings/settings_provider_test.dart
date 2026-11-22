import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_scrolling/data/repositories/app_state_repository.dart';
import 'package:smart_scrolling/data/services/local_store.dart';
import 'package:smart_scrolling/screens/settings/settings_provider.dart';

import '../../data/repositories/fake_account_repository.dart';
import '../../data/repositories/fake_explore_repository.dart';

class ReadFailingExplore extends FakeExploreRepository {
  bool failReads = false;
  @override
  Future<Map<String, String>> topicChoices() async {
    if (failReads) throw Exception('offline');
    return super.topicChoices();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'successful preference writes update the feed without a second read',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppStateRepository(LocalStore(), FakeAccountRepository());
      await state.load();
      final repo = ReadFailingExplore();
      final p = SettingsProvider(state, repo);
      await Future<void>.delayed(Duration.zero);
      repo.failReads = true;
      var revision = state.feedRevision;
      await p.toggleTopic('learning');
      expect(repo.choices['learning'], 'follow');
      expect(p.followed, {'learning'});
      expect(state.feedRevision, ++revision);
      expect(p.error, isNull);
      await p.toggleTopic('learning');
      expect(p.choices, isEmpty);
      expect(p.followed, isEmpty);
      expect(state.feedRevision, ++revision);
      expect(p.error, isNull);
      p.dispose();
      state.dispose();
    },
  );
}
