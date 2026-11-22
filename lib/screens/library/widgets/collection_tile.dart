import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/edit_text_dialog.dart';
import '../../../domain/models/library_card.dart';
import '../library_provider.dart';

/// "3 cards" in collection [id].
String cardCount(LibraryProvider p, String id) {
  final n = p.liked.where((c) => c.collectionIds.contains(id)).length;
  return '$n card${n == 1 ? '' : 's'}';
}

/// New collection, or rename collection [id].
Future<void> editCollection(BuildContext context, {String? id}) {
  final p = context.read<LibraryProvider>();
  return showDialog<void>(
    context: context,
    builder: (_) => EditTextDialog(
      title: id == null ? 'New collection' : 'Rename collection',
      label: 'Collection name',
      initialValue: p.collections[id] ?? '',
      collectionName: true,
      onSave: (name) async =>
          await (id == null
              ? p.createCollection(name)
              : p.renameCollection(id, name))
          ? null
          : p.actionError ?? p.loadError,
    ),
  );
}

/// One collection: tap to open it, tap again to leave it. A liked card
/// dragged onto it goes in.
class CollectionTile extends StatelessWidget {
  const CollectionTile({super.key, required this.id, required this.name});
  final String id, name;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LibraryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    Future<void> drop(LibraryCard entry) async {
      if (entry.collectionIds.contains(id)) return say('Already in $name');
      say(
        await p.setMembership(entry, id, true)
            ? 'Added to $name'
            : p.actionError ?? p.loadError ?? 'That did not save. Try again.',
      );
    }

    final open = p.collectionId == id;
    return DragTarget<LibraryCard>(
      onWillAcceptWithDetails: (_) => !p.busy,
      onAcceptWithDetails: (d) => drop(d.data),
      builder: (context, hovering, _) => ListTile(
        key: Key('collection-$id'),
        leading: Icon(
          hovering.isEmpty ? Icons.folder_outlined : Icons.folder_open_rounded,
        ),
        title: Text(name),
        subtitle: Text(cardCount(p, id)),
        selected: open || hovering.isNotEmpty,
        onTap: () => p.openCollection(open ? null : id),
        trailing: PopupMenuButton<String>(
          key: Key('collection-menu-$id'),
          tooltip: 'Manage $name',
          enabled: !p.busy,
          onSelected: (action) async {
            if (action == 'rename') return editCollection(context, id: id);
            if (!await p.deleteCollection(id)) {
              say(p.actionError ?? p.loadError!);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete collection')),
          ],
        ),
      ),
    );
  }
}
