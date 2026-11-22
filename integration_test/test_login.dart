import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/config/app_config.dart';
import 'package:smart_scrolling/data/repositories/account_repository.dart';
import 'package:smart_scrolling/data/repositories/offline_repository.dart';
import 'package:smart_scrolling/data/services/local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Starts Supabase for an emulator walkthrough. Never uses the owner's account.
Future<SupabaseClient> startSupabase() async {
  expect(AppConfig.testLoginEmail, 'agent@smartscrolling.test');
  expect(
    AppConfig.hasTestLogin,
    true,
    reason: 'Run with --dart-define-from-file=.env.test.json too.',
  );
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(localStorage: EmptyLocalStorage()),
  );
  return Supabase.instance.client;
}

/// Signs in with the debug test login (A3-8) and returns the account.
Future<AccountRepository> testLogin() async {
  final account = AccountRepository(await startSupabase());
  if (account.email != AppConfig.testLoginEmail) {
    await account.signOut();
    await account.signInWithPassword(
      AppConfig.testLoginEmail,
      AppConfig.testLoginPassword,
    );
  }
  // Repositories used directly by a walkthrough need this person's phone database.
  await liveOffline.use(account.userId);
  // Each scenario starts on Discover, independent of the previous saved tab.
  final store = LocalStore();
  final saved = jsonDecode(
    await store.loadState(account.userId!) ?? '{}',
  ) as Map<String, dynamic>;
  await store.saveState(account.userId!, jsonEncode({...saved, 'tab': 0}));
  return account;
}

/// Pumps frames until [finder] shows (network calls do not settle on their own).
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    final skip = find.text('Skip');
    if (skip.evaluate().isNotEmpty) await tester.tap(skip);
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsWidgets);
}

OfflineRepository? _offline;

/// One offline engine per walkthrough run, as in the app.
OfflineRepository get liveOffline =>
    _offline ??= OfflineRepository(Supabase.instance.client);
