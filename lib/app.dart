import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_sizes.dart';
import 'core/theme/dark_mode.dart';
import 'core/theme/light_mode.dart';
import 'core/theme/theme_provider.dart';
import 'core/widgets/card_media.dart';
import 'data/repositories/account_repository.dart';
import 'data/repositories/app_state_repository.dart';
import 'data/repositories/discover_repository.dart';
import 'data/repositories/explore_repository.dart';
import 'data/repositories/library_repository.dart';
import 'data/repositories/offline_repository.dart';
import 'data/repositories/practice_repository.dart';
import 'data/repositories/theme_repository.dart';
import 'data/services/local_store.dart';
import 'data/services/reminder_service.dart';
import 'data/repositories/sharing_repository.dart';
import 'routing/app_router.dart';

/// Plugs everything together: repositories, theme and router.
class App extends StatelessWidget {
  const App({
    super.key,
    required this.account,
    required this.discover,
    required this.library,
    required this.practice,
    required this.explore,
    required this.offline,
  });

  final AccountRepository account;
  final DiscoverRepository discover;
  final LibraryRepository library;
  final PracticeRepository practice;
  final ExploreRepository explore;
  final OfflineRepository offline;

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      Provider<AccountRepository>.value(value: account),
      Provider<DiscoverRepository>.value(value: discover),
      Provider<LibraryRepository>.value(value: library),
      Provider<PracticeRepository>.value(value: practice),
      Provider<ExploreRepository>.value(value: explore),
      Provider(create: (_) => SharingRepository()),
      ChangeNotifierProvider<OfflineRepository>.value(value: offline),
      ChangeNotifierProvider(
        create: (_) => AppStateRepository(
          LocalStore(),
          account,
          offline,
          ReminderService(),
        )..load(),
      ),
      ChangeNotifierProvider(
        create: (c) {
          final state = c.read<AppStateRepository>();
          final themes = ThemeRepository(LocalStore());
          final theme = ThemeProvider(themes.load, (mode) async {
            state.setThemeMode(mode.name);
            await themes.save(mode);
          });
          // The phone's saved row wins over the local copy once it loads.
          void show(String name) =>
              theme.setMode(ThemeMode.values.byName(name));
          state.onThemeLoaded = show;
          if (state.device != null) show(state.device!['theme_mode'] as String);
          return theme;
        },
      ),
      Provider<GoRouter>(
        create: (c) {
          final router = appRouter(c.read<AppStateRepository>());
          router.routerDelegate.addListener(() => mediaPlaybackChanges.value++);
          return router;
        },
        dispose: (_, router) => router.dispose(),
      ),
    ],
    child: Consumer<AppStateRepository>(
      builder: (context, state, _) => MaterialApp.router(
        title: 'SmartScrolling',
        restorationScopeId: 'smart-scrolling',
        key: ValueKey(state.profile?['user_id']),
        debugShowCheckedModeBanner: false,
        theme: lightMode(highContrast: state.s.highContrast),
        darkTheme: darkMode(highContrast: state.s.highContrast),
        themeMode: context.watch<ThemeProvider>().mode,
        themeAnimationDuration: state.s.reducedMotion
            ? Duration.zero
            : AppDurations.theme,
        routerConfig: context.read<GoRouter>(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            // The chosen size multiplies the phone's own accessibility size.
            textScaler: TextScaler.linear(
              MediaQuery.textScalerOf(context).scale(1) * state.s.textStep,
            ),
            disableAnimations:
                state.s.reducedMotion ||
                MediaQuery.of(context).disableAnimations,
          ),
          child: child!,
        ),
      ),
    ),
  );
}
