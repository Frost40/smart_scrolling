import 'package:go_router/go_router.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../core/theme/page_motion.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/discover_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/practice_repository.dart';
import '../data/repositories/explore_repository.dart';
import '../screens/onboarding/onboarding_provider.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/account/account_provider.dart';
import '../screens/account/account_screen.dart';
import '../screens/discover/discover_provider.dart';
import '../screens/discover/discover_screen.dart';
import '../screens/explore/explore_provider.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/library/library_provider.dart';
import '../screens/library/library_screen.dart';
import '../screens/practice/practice_provider.dart';
import '../screens/practice/practice_screen.dart';
import '../screens/progress/progress_provider.dart';
import '../screens/progress/progress_screen.dart';
import '../data/repositories/sharing_repository.dart';
import '../screens/settings/settings_provider.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/shell/shell_screen.dart';
import '../screens/shell/widgets/tab_fade.dart';
import '../screens/source/source_provider.dart';
import '../screens/source/source_screen.dart';
import '../screens/start/start_screen.dart';
import '../screens/welcome/welcome_provider.dart';
import '../screens/welcome/welcome_screen.dart';
import '../screens/card/card_provider.dart';
import '../screens/card/card_screen.dart';

/// The four tabs in navigation order.
const tabPaths = ['/discover', '/practice', '/explore', '/library'];

/// Every screen's address. The saved tab (`s.tab`) decides which tab shows:
/// changing it moves the app there.
GoRouter appRouter(AppStateRepository state) {
  return GoRouter(
    refreshListenable: state,
    redirect: (context, route) {
      final loc = route.matchedLocation;
      if (state.loading || state.loadError != null) {
        return loc == '/' ? null : '/';
      }
      if (!state.signedIn) return loc == '/welcome' ? null : '/welcome';
      if (state.needsOnboarding) {
        return loc == '/onboarding' ? null : '/onboarding';
      }
      // Pages opened on top keep their place until they close.
      if (loc == '/card' ||
          loc == '/progress' ||
          loc == '/settings' ||
          loc == '/account' ||
          loc.startsWith('/source/')) {
        return null;
      }
      final tab = tabPaths[state.s.tab];
      return loc == tab ? null : tab;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const StartScreen()),
      GoRoute(
        path: '/welcome',
        builder: (_, _) => ChangeNotifierProvider(
          create: (c) => WelcomeProvider(
            c.read<AccountRepository>(),
            testLogin: AppConfig.hasTestLogin
                ? (AppConfig.testLoginEmail, AppConfig.testLoginPassword)
                : null,
          ),
          child: const WelcomeScreen(),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => ChangeNotifierProvider(
          create: (c) => OnboardingProvider(
            c.read<ExploreRepository>(),
            state.finishOnboarding,
          ),
          child: const OnboardingScreen(),
        ),
      ),
      StatefulShellRoute(
        builder: (_, _, shell) => ShellScreen(shell: shell),
        navigatorContainerBuilder: (_, shell, tabs) =>
            TabFade(index: shell.currentIndex, children: tabs),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                builder: (context, _) => ChangeNotifierProvider(
                  key: ValueKey(
                    context.select<AppStateRepository, int>(
                      (s) => s.feedRevision,
                    ),
                  ),
                  create: (c) {
                    final state = c.read<AppStateRepository>();
                    return DiscoverProvider(
                      c.read<DiscoverRepository>(),
                      filter: state.discoverFilter,
                      saveFilter: state.setDiscoverFilter,
                      openExplore: () => state.change(() => state.s.tab = 2),
                    );
                  },
                  child: const DiscoverScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/practice',
                builder: (_, _) => ChangeNotifierProvider(
                  create: (c) {
                    final state = c.read<AppStateRepository>();
                    return PracticeProvider(
                      c.read<PracticeRepository>(),
                      filter: state.practiceFilter,
                      saveFilter: state.setPracticeFilter,
                      isOpen: () => state.s.tab == 1,
                      tabChanges: state,
                    );
                  },
                  child: const PracticeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (_, _) => ChangeNotifierProvider(
                  create: (c) => ExploreProvider(c.read<ExploreRepository>()),
                  child: const ExploreScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (_, _) => ChangeNotifierProvider(
                  create: (c) {
                    final state = c.read<AppStateRepository>();
                    return LibraryProvider(
                      c.read<LibraryRepository>(),
                      isOpen: () => state.s.tab == 3,
                      tabChanges: state,
                      tabTaps: () => state.tabTaps,
                    );
                  },
                  child: const LibraryScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/card',
        pageBuilder: (context, route) => _page(
          context,
          route,
          PageMotion.grow,
          ChangeNotifierProvider(
            create: (c) => CardProvider(
              c.read<DiscoverRepository>(),
              c.read<LibraryRepository>(),
              route.uri.queryParameters['id'] ?? '',
            ),
            child: CardScreen(
              editNote: route.uri.queryParameters['edit'] == 'true',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/source/:id',
        pageBuilder: (context, route) => _page(
          context,
          route,
          PageMotion.grow,
          ChangeNotifierProvider(
            create: (c) => SourceProvider(
              c.read<DiscoverRepository>(),
              route.pathParameters['id']!,
              c.read<ExploreRepository>(),
              state.personalizationChanged,
            ),
            child: const SourceScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/progress',
        pageBuilder: (context, route) => _page(
          context,
          route,
          PageMotion.grow,
          ChangeNotifierProvider(
            create: (c) => ProgressProvider(c.read<PracticeRepository>()),
            child: const ProgressScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, route) => _page(
          context,
          route,
          PageMotion.side,
          ChangeNotifierProvider(
            create: (c) => SettingsProvider(
              c.read<AppStateRepository>(),
              c.read<ExploreRepository>(),
              c.read<SharingRepository>(),
            ),
            child: const SettingsScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/account',
        pageBuilder: (context, route) => _page(
          context,
          route,
          PageMotion.side,
          ChangeNotifierProvider(
            create: (c) => AccountProvider(c.read<AccountRepository>()),
            child: const AccountScreen(),
          ),
        ),
      ),
    ],
  );
}

/// A screen with a back arrow, moving its own way ([PageMotion]); a grow
/// screen opens from the spot [BuildContextOpen.pushFrom] passed in.
AppPage<void> _page(
  BuildContext context,
  GoRouterState route,
  PageMotion motion,
  Widget child,
) => AppPage(
  key: route.pageKey,
  motion: motion,
  origin: route.extra is Rect ? route.extra! as Rect : null,
  still: MediaQuery.disableAnimationsOf(context),
  child: child,
);

extension BuildContextOpen on BuildContext {
  /// Opens [location] growing out of this widget's spot on the screen.
  Future<T?> pushFrom<T>(String location) {
    final box = findRenderObject();
    return push<T>(
      location,
      extra: box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }
}
