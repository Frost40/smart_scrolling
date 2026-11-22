import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_sizes.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/widgets/empty_art.dart';
import '../../core/widgets/enter_in.dart';
import '../../core/widgets/heading.dart';
import '../../core/widgets/page_list.dart';
import 'welcome_provider.dart';

/// Lets you in: Sign in with Google, plus Test login in debug builds.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WelcomeProvider>();
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: PageList([
          const SizedBox(height: AppSpacing.xxl),
          const EnterIn(
            child: Center(child: EmptyArt(kind: EmptyArtKind.cards)),
          ),
          Text(
            'SMARTSCROLLING',
            textAlign: TextAlign.center,
            style: text.labelLarge!.copyWith(color: context.colors.primary),
          ),
          const Heading('Turn curiosity into understanding.'),
          Text(
            'Discover one idea at a time. Keep what interests you, then practise remembering it.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.s),
          FilledButton.icon(
            onPressed: p.busy ? null : p.signInWithGoogle,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in with Google'),
          ),
          if (p.testLogin != null)
            OutlinedButton(
              onPressed: p.busy ? null : p.signInForTest,
              child: const Text('Test login'),
            ),
          if (p.busy) const LinearProgressIndicator(),
          if (p.error != null) Text(p.error!),
        ]),
      ),
    );
  }
}
