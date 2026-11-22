import 'package:flutter/material.dart';

import '../../routing/app_router.dart';

import 'package:provider/provider.dart';

import '../../core/widgets/discover_card_view.dart';
import '../../data/repositories/discover_repository.dart';
import '../../data/repositories/sharing_repository.dart';
import '../../core/widgets/edit_text_dialog.dart';
import '../../core/widgets/page_list.dart';
import 'card_provider.dart';

class CardScreen extends StatefulWidget {
  const CardScreen({super.key, this.editNote = false});
  final bool editNote;

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  bool _openedEditor = false;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CardProvider>();
    final card = p.card;
    Future<void> edit() => showDialog<void>(
      context: context,
      builder: (_) => EditTextDialog(
        title: 'Private note',
        label: 'Your note',
        initialValue: p.entry?.note ?? '',
        onSave: p.saveNote,
      ),
    );
    if (widget.editNote && !_openedEditor && p.entry != null) {
      _openedEditor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) edit();
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Card')),
      body: p.error != null
          ? PageList([
              Text(p.error!),
              TextButton(onPressed: p.load, child: const Text('Try again')),
            ])
          : card == null
          ? const Center(child: CircularProgressIndicator())
          : PageList([
              DiscoverCardView(
                card: card,
                onShare: (origin) =>
                    context.read<SharingRepository>().card(card, origin),
                loadMedia: () =>
                    context.read<DiscoverRepository>().loadMedia(card),
                note: p.entry?.note,
                onSourcePage: () => context
                    .pushFrom('/source/${card.sourceId}')
                    .then((_) => p.load()),
                onOpenCard: (id) => context
                    .pushFrom('/card?id=${Uri.encodeComponent(id)}')
                    .then((_) => p.load()),
                onEditNote: p.entry == null ? null : edit,
              ),
              if (p.entry != null)
                TextButton(onPressed: edit, child: const Text('Edit note')),
            ]),
    );
  }
}
