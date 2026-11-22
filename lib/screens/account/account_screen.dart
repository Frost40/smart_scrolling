import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_sizes.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/widgets/page_list.dart';
import '../../core/widgets/section_card.dart';
import 'account_provider.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AccountProvider>();
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: PageList([
        SectionCard(
          children: [
            Center(
              child: CircleAvatar(
                radius: AppSizes.badge,
                backgroundColor: colors.tint(colors.primary),
                foregroundColor: colors.primary,
                child: ExcludeSemantics(
                  child: Text(
                    p.email.isEmpty ? '?' : p.email[0].toUpperCase(),
                    style: text.headlineMedium!.copyWith(color: colors.primary),
                  ),
                ),
              ),
            ),
            Text(
              'Signed in as',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            Text(p.email, textAlign: TextAlign.center, style: text.titleMedium),
            OutlinedButton.icon(
              onPressed: p.busy ? null : p.signOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
            if (p.busy) const LinearProgressIndicator(),
            if (p.error != null) Text(p.error!),
          ],
        ),
      ]),
    );
  }
}
