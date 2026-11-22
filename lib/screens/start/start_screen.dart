import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_sizes.dart';
import '../../core/widgets/empty_art.dart';
import '../../core/widgets/page_list.dart';
import '../../data/repositories/app_state_repository.dart';

/// Shows while your settings load, or why they could not load.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateRepository>();
    if (state.loadError == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const EmptyArt(kind: EmptyArtKind.cards),
              const SizedBox(height: AppSpacing.l),
              const SizedBox(
                width: AppSizes.emptyArt,
                child: LinearProgressIndicator(),
              ),
              const SizedBox(height: AppSpacing.l),
              Text('Loading', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings unavailable')),
      body: PageList([
        Text(state.loadError!),
        FilledButton(onPressed: state.load, child: const Text('Try again')),
        OutlinedButton(onPressed: state.signOut, child: const Text('Sign out')),
      ]),
    );
  }
}
