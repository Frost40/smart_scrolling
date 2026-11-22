import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_scrolling/data/repositories/app_state_repository.dart';
import 'package:smart_scrolling/data/services/local_store.dart';

import 'fake_account_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppStateRepository> loaded(FakeAccountRepository account) async {
    final state = AppStateRepository(LocalStore(), account);
    await state.load();
    return state;
  }

  test('signed out: nothing loads and nothing is saved', () async {
    final account = FakeAccountRepository(signedIn: false);
    final state = await loaded(account);
    expect(state.signedIn, false);
    state.change(() => state.s.reducedMotion = true);
    await state.saving;
    expect(account.deviceSaves, isEmpty);
  });

  test(
    'the phone row is applied, then only changed settings are saved',
    () async {
      final account = FakeAccountRepository()
        ..device['high_contrast'] = true
        ..device['text_scale'] = 1.4;
      final state = await loaded(account);
      String? theme;
      state.onThemeLoaded = (name) => theme = name;
      expect(state.s.highContrast, true);
      expect(state.s.textScale, 1.4);

      state.change(() => state.s.reducedMotion = true);
      state.setThemeMode('dark');
      await state.saving;
      // Quick changes travel together in one save.
      expect(account.deviceSaves, [
        {'reduce_motion': true, 'theme_mode': 'dark'},
      ]);
      expect(account.device['revision'], 2);
      state.change(() => state.s.textScale = 1.8);
      await state.saving;
      expect(account.deviceSaves.last, {'text_scale': 1.8});
      expect(theme, isNull, reason: 'a save does not reload the theme');
    },
  );

  test('a skipped first start is not asked again', () async {
    final account = FakeAccountRepository(follows: false);
    final state = await loaded(account);
    expect(state.needsOnboarding, true);
    state.finishOnboarding();
    await state.saving;
    await state.load();
    expect(state.needsOnboarding, false);
  });

  test('a save from an old revision changes nothing and reloads', () async {
    final account = FakeAccountRepository();
    final state = await loaded(account);
    // Another save got there first.
    account.device = {...account.device, 'high_contrast': true, 'revision': 2};
    state.change(() => state.s.reducedMotion = true);
    await state.saving;
    expect(account.device['reduce_motion'], false);
    expect(state.s.highContrast, true);
    expect(state.s.reducedMotion, false);
    expect(state.device!['revision'], 2);
  });

  test('a failed load says so, and Try again recovers', () async {
    final account = FakeAccountRepository()..failLoad = true;
    final state = await loaded(account);
    expect(state.loadError, isNotNull);
    account.failLoad = false;
    await state.load();
    expect(state.loadError, isNull);
    expect(state.signedIn, true);
  });

  test('offline, the app opens with the rows loaded last time', () async {
    final account = FakeAccountRepository()..device['offline_mode'] = 'light';
    await loaded(account);
    account.failLoad = true;
    final state = await loaded(account);
    expect(state.loadError, isNull);
    expect(state.signedIn, true);
    expect(state.needsOnboarding, false);
    expect(state.s.offlineMode, 'light');
  });

  test('each person gets their own snapshot on this phone', () async {
    final account = FakeAccountRepository();
    final state = await loaded(account);
    state.change(() => state.s.tab = 2);
    await state.saving;
    expect(await LocalStore().loadState('user-1'), contains('"tab":2'));
    expect(await LocalStore().loadState('someone-else'), isNull);
  });

  test(
    'Practice filter retries revision conflicts without losing other settings',
    () async {
      final account = FakeAccountRepository();
      final state = await loaded(account);
      addTearDown(state.dispose);
      account.profile = {
        ...account.profile,
        'discover_filter': 'quote',
        'revision': 2,
      };
      await state.setPracticeFilter('flashcard');
      expect(state.practiceFilter, 'flashcard');
      expect(account.profile['practice_filter'], 'flashcard');
      expect(account.profile['discover_filter'], 'quote');
      expect(account.profile['revision'], 3);
      await state.setDiscoverFilter('concept');
      expect(account.profile['practice_filter'], 'flashcard');
      expect(account.profile['discover_filter'], 'concept');
      await state.setPreferredLevel('advanced');
      expect(account.profile['preferred_level'], 'advanced');
      expect(account.profile['discover_filter'], 'concept');
      expect(account.profile['practice_filter'], 'flashcard');
      await state.setPreferredLevel(null);
      expect(account.profile['preferred_level'], isNull);
    },
  );
}
