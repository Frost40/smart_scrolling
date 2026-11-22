import 'package:smart_scrolling/screens/settings/widgets/theme_toggle.dart';
import 'package:smart_scrolling/screens/settings/widgets/offline_settings.dart';
import 'package:smart_scrolling/data/repositories/explore_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/data/repositories/account_repository.dart';
import 'package:smart_scrolling/data/repositories/discover_repository.dart';
import 'package:smart_scrolling/data/repositories/library_repository.dart';
import 'package:smart_scrolling/data/repositories/practice_repository.dart';
import 'package:smart_scrolling/data/services/local_store.dart';

import 'test_login.dart';

// Uses the debug test login only (A3-8), never the owner's Google account.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Test login, settings saved to this phone row, theme after restart, sign out',
    (tester) async {
      final client = await startSupabase();
      final account = AccountRepository(client);
      await account.signOut();
      await tester.pumpWidget(
        App(
          offline: liveOffline,
          account: account,
          explore: ExploreRepository(client),
          discover: DiscoverRepository(client, liveOffline),
          library: LibraryRepository(
            client,
            DiscoverRepository(client, liveOffline),
            liveOffline,
          ),
          practice: PracticeRepository(
            client,
            DiscoverRepository(client, liveOffline),
            liveOffline,
          ),
        ),
      );
      await pumpUntil(tester, find.text('Test login'));
      expect(find.text('Sign in with Google'), findsOneWidget);

      Future<void> tap(Finder finder) async {
        await pumpUntil(tester, finder);
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tap(find.text('Test login'));
      await pumpUntil(tester, find.byTooltip('Settings').hitTestable());
      expect(account.email, 'agent@smartscrolling.test');

      final installation = await LocalStore().installationId();
      Future<Map<String, dynamic>> row() => client
          .from('devices')
          .select()
          .eq('installation_id', installation)
          .single();
      Future<void> serverHas(String column, Object value) async {
        for (var i = 0; i < 50; i++) {
          if ((await row())[column] == value) return;
          await tester.pump(const Duration(milliseconds: 200));
        }
        fail('The devices row never got $column = $value');
      }

      final before = await row();
      await tap(find.byTooltip('Settings'));
      final motion = find.widgetWithText(SwitchListTile, 'Reduce motion');
      await tap(motion);
      await serverHas('reduce_motion', !(before['reduce_motion'] as bool));
      await tap(motion);
      await serverHas('reduce_motion', before['reduce_motion'] as bool);
      final offlineMode = find.descendant(
        of: find.byType(OfflineSettings),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      for (final mode in ['light', before['offline_mode'] as String]) {
        await tap(offlineMode);
        await tap(
          find
              .byWidgetPredicate(
                (w) => w is DropdownMenuItem<String> && w.value == mode,
              )
              .last,
        );
        await serverHas('offline_mode', mode);
      }
      final toggle = find.byKey(const Key('theme-toggle'));
      final wasDark = tester.widget<ThemeToggle>(toggle).dark;
      await tap(toggle);
      await serverHas('theme_mode', wasDark ? 'light' : 'dark');
      expect((await row())['revision'], greaterThan(before['revision'] as int));

      // A restart: the theme comes back from the phone's row.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        App(
          offline: liveOffline,
          account: AccountRepository(client),
          explore: ExploreRepository(client),
          discover: DiscoverRepository(client, liveOffline),
          library: LibraryRepository(
            client,
            DiscoverRepository(client, liveOffline),
            liveOffline,
          ),
          practice: PracticeRepository(
            client,
            DiscoverRepository(client, liveOffline),
            liveOffline,
          ),
        ),
      );
      await pumpUntil(tester, find.byTooltip('Settings').hitTestable());
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        wasDark ? Brightness.light : Brightness.dark,
      );
      await tap(find.byTooltip('Settings'));
      await tap(find.byKey(const Key('theme-system')));
      await serverHas('theme_mode', 'system');
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 300));

      await tap(find.byTooltip('Account'));
      expect(find.text('agent@smartscrolling.test'), findsOneWidget);
      await tap(find.text('Sign out'));
      await pumpUntil(tester, find.text('Sign in with Google'));
      expect(client.auth.currentUser, isNull);
    },
  );
}
