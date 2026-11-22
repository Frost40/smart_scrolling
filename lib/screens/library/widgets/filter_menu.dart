import 'package:flutter/material.dart';

/// A small drop-down for a Library filter: "All" or one of [options] (value → label).
class FilterMenu extends StatelessWidget {
  const FilterMenu({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label-$value-${options.length}'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      const DropdownMenuItem(value: 'all', child: Text('All')),
      for (final o in options.entries)
        DropdownMenuItem(
          value: o.key,
          child: Text(o.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) {
      if (v != null && v != value) onChanged(v);
    },
  );
}
