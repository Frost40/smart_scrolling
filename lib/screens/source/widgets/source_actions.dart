import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/report_dialog.dart';
import '../source_provider.dart';

class SourceActions extends StatelessWidget {
  const SourceActions({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<SourceProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s,
      children: [
        FilledButton.icon(
          onPressed: p.busy
              ? null
              : () => p.choose(p.choice == 'follow' ? null : 'follow'),
          icon: Icon(
            p.choice == 'follow'
                ? Icons.check_circle_rounded
                : Icons.add_circle_outline_rounded,
          ),
          label: Text(
            p.choice == 'follow' ? 'Remove from my feed' : 'Add to my feed',
          ),
        ),
        OutlinedButton(
          onPressed: p.busy
              ? null
              : () => p.choose(p.choice == 'hide' ? null : 'hide'),
          child: Text(p.choice == 'hide' ? 'Unhide' : 'Hide'),
        ),
        TextButton(
          onPressed: p.busy
              ? null
              : () async {
                  final message = await showReportDialog(
                    context,
                    title: 'Ask for more cards',
                    label: 'Message (optional)',
                  );
                  if (message != null) await p.ask(message);
                },
          child: const Text('Ask for more cards'),
        ),
        if (p.actionMessage != null) Text(p.actionMessage!),
      ],
    );
  }
}
