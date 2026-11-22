import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_scrolling/data/repositories/app_state_repository.dart';
import 'package:smart_scrolling/data/services/local_store.dart';
import 'package:smart_scrolling/data/services/reminder_service.dart';

import 'fake_account_repository.dart';

class Reminders extends ReminderService {
  bool allowed = false, fail = false;
  int requests = 0;
  String? time;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return allowed;
  }

  @override
  Future<void> restore(String? value) async {
    if (fail && value != null) throw Exception('platform unavailable');
    time = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'a reminder reset on another phone stays off after an offline restart',
    () async {
      final account = FakeAccountRepository()
        ..device['reminder_time'] = '20:30';
      final reminders = Reminders();
      final store = LocalStore();
      final state = AppStateRepository(store, account, null, reminders);
      await state.load();
      expect(reminders.time, '20:30');
      account.device = {
        ...account.device,
        'reminder_time': null,
        'revision': 2,
      };
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await state.saving;
      expect(reminders.time, isNull);
      state.dispose();
      account.failLoad = true;
      final restarted = AppStateRepository(store, account, null, reminders);
      await restarted.load();
      expect(restarted.loadError, isNull);
      expect(reminders.time, isNull);
      restarted.dispose();
    },
  );
  test('goal and reminder saves; denied permission and failed scheduling keep reminder off', () async {
    final account = FakeAccountRepository();
    final reminders = Reminders();
    final state = AppStateRepository(LocalStore(), account, null, reminders);
    await state.load();
    expect(reminders.requests, 0);
    await state.setWeeklyGoal(3);
    expect(account.profile['weekly_goal_days'], 3);
    await expectLater(state.setReminder('20:30'), throwsStateError);
    expect(account.device['reminder_time'], isNull);
    reminders.allowed = true;
    reminders.fail = true;
    await expectLater(state.setReminder('20:30'), throwsException);
    expect(account.device['reminder_time'], isNull);
    reminders.fail = false;
    await state.setReminder('20:30');
    expect(account.device['reminder_time'], '20:30');
    expect(reminders.time, '20:30');
    await state.setReminder(null);
    expect(reminders.time, isNull);
    state.dispose();
  });
  test(
    'delete preserves login, reloads defaults and clears saved phone snapshot',
    () async {
      final account = FakeAccountRepository()..profile['weekly_goal_days'] = 7;
      final reminders = Reminders()..allowed = true;
      final store = LocalStore();
      final state = AppStateRepository(store, account, null, reminders);
      await state.load();
      await state.setReminder('20:30');
      state.change(() => state.s.tab = 3);
      await state.deleteActivity();
      expect(account.isSignedIn, true);
      expect(state.profile!['weekly_goal_days'], isNull);
      expect(state.device!['reminder_time'], isNull);
      expect(reminders.time, isNull);
      expect(state.s.tab, 0);
      expect(state.needsOnboarding, true);
      expect(await store.loadState(account.userId!), isNull);
      expect(await store.loadRows(account.userId!), isNot(contains('20:30')));
      state.dispose();
    },
  );
}
