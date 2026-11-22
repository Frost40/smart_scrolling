import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';

/// A saved text field; errors keep the draft open instead of losing it.
class EditTextDialog extends StatefulWidget {
  const EditTextDialog({
    super.key,
    required this.title,
    required this.label,
    required this.initialValue,
    required this.onSave,
    this.collectionName = false,
  });
  final String title, label, initialValue;
  final bool collectionName;
  final Future<String?> Function(String) onSave;

  @override
  State<EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<EditTextDialog> {
  late final _text = TextEditingController(text: widget.initialValue);
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSave(_text.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _text,
                autofocus: true,
                enabled: !_busy,
                maxLines: widget.collectionName ? 1 : null,
                decoration: InputDecoration(labelText: widget.label),
                validator: (value) =>
                    widget.collectionName &&
                        (value!.trim().isEmpty ||
                            value.trim().runes.length > 60)
                    ? 'Use 1–60 characters.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.s),
                Semantics(liveRegion: true, child: Text(_error!)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }
}
