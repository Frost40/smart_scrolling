import 'package:flutter/material.dart';

/// The "Mix or one format" menu of Discover and Practice.
class FormatSelector extends StatelessWidget {
  const FormatSelector({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// Stored values, such as `mix` or `multiple_choice`; shown as "Mix", "Multiple choice".
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final f in options)
        DropdownMenuItem(
          value: f,
          child: Text(
            '${f[0].toUpperCase()}${f.substring(1).replaceAll('_', ' ')}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (v) {
      if (v != null && v != value) onChanged(v);
    },
  );
}
