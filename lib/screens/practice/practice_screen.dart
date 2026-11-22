import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_sizes.dart';
import '../../core/widgets/enter_in.dart';
import '../../core/widgets/hold_to_refresh.dart';
import 'practice_provider.dart';
import 'widgets/practice_card_view.dart';
import 'widgets/practice_header.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PracticeProvider>();
    return HoldToRefresh(
      onRefresh: p.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event.metrics.extentAfter < event.metrics.viewportDimension) {
            p.loadMore();
          }
          return false;
        },
        child: ListView.builder(
          key: PageStorageKey('practice-${p.filter}-${p.early}'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.s,
            AppSpacing.l,
            AppSpacing.xl,
          ),
          itemCount: p.entries.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) return const PracticeHeader();
            if (i <= p.entries.length) {
              return EnterIn(
                key: ValueKey(p.entries[i - 1]),
                child: PracticeCardView(entry: p.entries[i - 1]),
              );
            }
            return const PracticeFooter();
          },
        ),
      ),
    );
  }
}
