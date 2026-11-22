import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/offline_repository.dart';

/// The frame around the four tabs: title, Settings, banners and the tab bar.
class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateRepository>();
    final s = state.s;
    final offline = context.watch<OfflineRepository>();
    return Scaffold(
      appBar: AppBar(
        title: Text(['Discover', 'Practice', 'Explore', 'Library'][s.tab]),
        actions: [
          IconButton(
            tooltip: 'Account',
            onPressed: () => context.push('/account'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () {
              context.push('/settings');
            },
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!offline.online)
            MaterialBanner(
              leading: const Icon(Icons.cloud_off_rounded),
              content: Text(
                offline.pending == 0
                    ? 'You are offline. The cards on this phone still work.'
                    : 'You are offline. ${offline.pending} '
                          '${offline.pending == 1 ? 'action' : 'actions'} '
                          'will be sent when you are back online.',
              ),
              actions: [
                TextButton(
                  onPressed: () => context.push('/settings'),
                  child: const Text('Offline settings'),
                ),
              ],
            ),
          if (state.saveError != null)
            MaterialBanner(
              leading: const Icon(Icons.sync_problem_rounded),
              content: Text(state.saveError!),
              actions: [
                TextButton(
                  onPressed: state.persist,
                  child: const Text('Retry save'),
                ),
              ],
            ),
          Expanded(child: shell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: s.tab,
        onDestinationSelected: (i) => state.change(() {
          s.tab = i;
          state.tabTaps++;
        }),
        destinations: const [
          NavigationDestination(
            key: Key('nav-0'),
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            key: Key('nav-1'),
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Practice',
          ),
          NavigationDestination(
            key: Key('nav-2'),
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.manage_search_rounded),
            label: 'Explore',
          ),
          NavigationDestination(
            key: Key('nav-3'),
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}
