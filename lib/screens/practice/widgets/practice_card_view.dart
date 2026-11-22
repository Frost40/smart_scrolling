import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';

import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/discover_card_view.dart';
import '../../../domain/models/practice_card.dart';
import '../../../data/repositories/discover_repository.dart';
import '../../../data/repositories/sharing_repository.dart';
import '../practice_provider.dart';
import 'practice_controls.dart';
import 'ordering_controls.dart';
import 'matching_controls.dart';
import 'practice_result.dart';

class PracticeCardView extends StatelessWidget {
  const PracticeCardView({super.key, required this.entry});
  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PracticeProvider>();
    final e = entry;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
        child: Card(
          margin: const EdgeInsets.only(top: AppSpacing.l),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.l,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.style_rounded),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => Dialog(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DiscoverCardView(
                                card: e.card,
                                onShare: (origin) => context
                                    .read<SharingRepository>()
                                    .card(e.card, origin),
                                loadMedia: () => context
                                    .read<DiscoverRepository>()
                                    .loadMedia(e.card),
                                onOpenCard: (id) {
                                  Navigator.pop(dialogContext);
                                  context
                                      .pushFrom(
                                        '/card?id=${Uri.encodeComponent(id)}',
                                      )
                                      .then((_) => p.reloadCard(e));
                                },
                                onEditNote: () {
                                  Navigator.pop(dialogContext);
                                  context
                                      .pushFrom(
                                        '/card?id=${Uri.encodeComponent(e.card.id)}&edit=true',
                                      )
                                      .then((_) => p.reloadCard(e));
                                },
                                onSourcePage: () {
                                  Navigator.pop(dialogContext);
                                  context
                                      .pushFrom('/source/${e.card.sourceId}')
                                      .then((_) => p.reloadCard(e));
                                },
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    label: Text('Testing: ${e.card.title}'),
                  ),
                ),
                Text(
                  e.test.prompt,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (e.test.type == 'flashcard')
                  FlashcardControls(entry: e)
                else if (e.test.type == 'ordering')
                  OrderingControls(entry: e)
                else if (e.test.type == 'matching')
                  MatchingControls(entry: e)
                else
                  ChoiceControls(entry: e),
                if (e.answer != null) PracticeResult(entry: e),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
