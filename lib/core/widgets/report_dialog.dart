import 'package:flutter/material.dart';

/// Asks what is wrong with a card. Returns the message, or null when cancelled.
Future<String?> showReportDialog(
  BuildContext context, {
  String title = 'Report a problem',
  String label = 'What is wrong? (optional)',
}) => showDialog<String>(
  context: context,
  builder: (_) => ReportDialog(title: title, label: label),
);

/// The "Report a problem" form: one optional message and Send.
class ReportDialog extends StatefulWidget {
  const ReportDialog({
    super.key,
    this.title = 'Report a problem',
    this.label = 'What is wrong? (optional)',
  });
  final String title, label;

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('report-message'),
      controller: _message,
      autofocus: true,
      maxLines: null,
      decoration: InputDecoration(labelText: widget.label),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('report-send'),
        onPressed: () => Navigator.pop(context, _message.text),
        child: const Text('Send'),
      ),
    ],
  );
}
