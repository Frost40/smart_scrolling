import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../domain/models/practice_card.dart';
import '../practice_provider.dart';

class OrderingControls extends StatelessWidget {
  const OrderingControls({super.key, required this.entry});
  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PracticeProvider>();
    final e = entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        const Text('Put the items in order. Drag a handle or use Up and Down.'),
        ReorderableListView(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) => p.move(e, from, to),
          children: [
            for (var i = 0; i < e.order.length; i++)
              Row(
                key: ValueKey(e.order[i]),
                children: [
                  ReorderableDragStartListener(
                    index: i,
                    enabled: e.answer == null,
                    child: Tooltip(
                      message: 'Drag ${e.test.correctOrder[e.order[i]]}',
                      child: const SizedBox(
                        width: AppSizes.minTap,
                        height: AppSizes.minTap,
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text('${i + 1}. ${e.test.correctOrder[e.order[i]]}'),
                  ),
                  IconButton(
                    tooltip: 'Move ${e.test.correctOrder[e.order[i]]} up',
                    onPressed: e.answer == null && i > 0
                        ? () => p.move(e, i, i - 1)
                        : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move ${e.test.correctOrder[e.order[i]]} down',
                    onPressed: e.answer == null && i < e.order.length - 1
                        ? () => p.move(e, i, i + 1)
                        : null,
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
          ],
        ),
        if (e.answer == null)
          FilledButton(onPressed: () => p.answer(e), child: const Text('Check'))
        else
          Text('Correct order:\n${e.test.correctOrder.join('\n')}'),
      ],
    );
  }
}
