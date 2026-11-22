import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../settings_provider.dart';

class YourData extends StatelessWidget {
  const YourData({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsProvider>();
    Future<void> remove() async {
      final first = await showDialog<bool>(
        context: context,
        builder: (_) => const DeleteActivityDialog(finalStep: false),
      );
      if (first != true || !context.mounted) return;
      final second = await showDialog<bool>(
        context: context,
        builder: (_) => const DeleteActivityDialog(finalStep: true),
      );
      if (second == true) await p.deleteActivity();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s,
      children: [
        const Text(
          'Export all your saved data as JSON, or start again. A connection is required.',
        ),
        OutlinedButton.icon(
          onPressed: p.dataBusy
              ? null
              : () {
                  final box = context.findRenderObject() as RenderBox;
                  p.exportData(box.localToGlobal(Offset.zero) & box.size);
                },
          icon: const Icon(Icons.ios_share),
          label: const Text('Export my data'),
        ),
        TextButton(
          onPressed: p.dataBusy ? null : remove,
          child: const Text('Delete all my activity'),
        ),
        if (p.dataBusy) const LinearProgressIndicator(),
        if (p.dataError != null) Text(p.dataError!),
      ],
    );
  }
}

class DeleteActivityDialog extends StatelessWidget {
  const DeleteActivityDialog({super.key, required this.finalStep});
  final bool finalStep;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      finalStep
          ? 'Permanently delete your activity?'
          : 'Delete all your activity?',
    ),
    content: Text(
      finalStep
          ? 'This cannot be undone. Your activity will be deleted and settings reset on every device. Export first if you want a copy.'
          : 'This removes your Likes, notes, collections, saved cards, history, answers and requests. Settings return to defaults. Your account and the learning content stay.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Keep my activity'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(
          finalStep ? 'Delete permanently' : 'Continue to final confirmation',
        ),
      ),
    ],
  );
}
