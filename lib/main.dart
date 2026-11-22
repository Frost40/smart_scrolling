import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'data/repositories/account_repository.dart';
import 'data/repositories/discover_repository.dart';
import 'data/repositories/explore_repository.dart';
import 'data/repositories/library_repository.dart';
import 'data/repositories/offline_repository.dart';
import 'data/repositories/practice_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.hasSupabase) {
    throw StateError('Run with --dart-define-from-file=.env.mobile.json');
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  final client = Supabase.instance.client;
  final offline = OfflineRepository(client);
  final discover = DiscoverRepository(client, offline);
  runApp(
    App(
      account: AccountRepository(client),
      explore: ExploreRepository(client),
      offline: offline,
      discover: discover,
      library: LibraryRepository(client, discover, offline),
      practice: PracticeRepository(client, discover, offline),
    ),
  );
}
