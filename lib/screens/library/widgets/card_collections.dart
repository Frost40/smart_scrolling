import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/edit_text_dialog.dart';
import '../../../domain/models/library_card.dart';
import '../library_provider.dart';

Future<void> editLibraryNote(BuildContext context, LibraryCard entry) {
  final p = context.read<LibraryProvider>();
  return showDialog<void>(
    context: context,
    builder: (_) => EditTextDialog(
      title: 'Private note',
      label: 'Your note',
      initialValue: entry.note ?? '',
      onSave: (note) async =>
          await p.saveNote(entry, note) ? null : p.actionError ?? p.loadError,
    ),
  );
}

/// Opens a liked card's collections; says how many it is in.
class AddToCollection extends StatelessWidget {
  const AddToCollection({super.key, required this.entry});
  final LibraryCard entry;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LibraryProvider>();
    final n = entry.collectionIds.length;
    return CompactAction(
      key: Key('card-menu-${entry.card.id}'),
      tooltip: n == 0 ? 'Add to collection' : 'Collections of this card',
      onPressed: p.busy
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => ChangeNotifierProvider.value(
                value: p,
                child: CollectionSheet(cardId: entry.card.id),
              ),
            ),
      icon: n == 0 ? Icons.create_new_folder_outlined : Icons.folder_rounded,
      label: n == 0 ? 'Collect' : 'In $n',
    );
  }
}

/// A short icon-and-word button for the row under a Library card; the
/// tooltip has the full words, which TalkBack reads too.
class CompactAction extends StatelessWidget {
  const CompactAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final String tooltip, label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}

/// A tick per collection; tapping one adds or removes the card at once.
class CollectionSheet extends StatelessWidget {
  const CollectionSheet({super.key, required this.cardId});
  final String cardId;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LibraryProvider>();
    // Read the card again after each change, so the ticks stay current.
    final entry = p.liked.where((c) => c.card.id == cardId).firstOrNull;
    Future<void> newCollection() => showDialog<void>(
      context: context,
      builder: (_) => EditTextDialog(
        title: 'New collection',
        label: 'Collection name',
        initialValue: '',
        collectionName: true,
        onSave: (name) async => await p.createCollection(name)
            ? null
            : p.actionError ?? p.loadError,
      ),
    );
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              'Add to collection',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            trailing: TextButton(
              key: const Key('collection-sheet-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
          if (p.collections.isEmpty)
            const ListTile(title: Text('No collections yet. Make one below.')),
          if (entry != null)
            for (final c in p.collections.entries)
              CheckboxListTile(
                key: Key('membership-${c.key}'),
                title: Text(c.value),
                value: entry.collectionIds.contains(c.key),
                onChanged: p.busy
                    ? null
                    : (on) async {
                        final messenger = ScaffoldMessenger.of(context);
                        if (!await p.setMembership(entry, c.key, on!)) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(p.actionError ?? p.loadError!),
                            ),
                          );
                        }
                      },
              ),
          ListTile(
            key: const Key('sheet-new-collection'),
            leading: const Icon(Icons.add_rounded),
            title: const Text('New collection'),
            onTap: p.busy ? null : newCollection,
          ),
        ],
      ),
    );
  }
}
