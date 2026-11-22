import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../data/repositories/offline_repository.dart';
import '../../../domain/offline_mode.dart';
import '../settings_provider.dart';

/// Offline: the mode (A3-13), mobile data, what is on this phone and Download now.
class OfflineSettings extends StatelessWidget {
  const OfflineSettings({super.key});

  static const _mb = 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsProvider>();
    final o = context.watch<OfflineRepository>();
    final mode = OfflineMode.parse(p.s.offlineMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s,
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey(mode),
          initialValue: mode.dbName,
          decoration: const InputDecoration(labelText: 'Offline mode'),
          items: [
            for (final m in OfflineMode.values)
              DropdownMenuItem(
                value: m.dbName,
                child: Text(switch (m) {
                  OfflineMode.onlineOnly => 'Online only · nothing kept',
                  _ =>
                    '${m.name[0].toUpperCase()}${m.name.substring(1)} · '
                        '${m.discoverCards} cards · ${m.capBytes ~/ _mb} MB',
                }),
              ),
          ],
          onChanged: (v) => p.setOfflineMode(v!),
        ),
        SwitchListTile(
          title: const Text('Use mobile data for downloads'),
          subtitle: const Text('Off: downloads wait for Wi-Fi.'),
          value: p.s.mobileData,
          onChanged: p.setMobileData,
        ),
        ListTile(
          title: const Text('On this phone'),
          subtitle: Text(
            '${o.unseen} unread cards · ${o.liked} Liked · ${o.later} For later · '
            '${o.practice} to practice\n'
            '${o.usedBytes < _mb ? '${(o.usedBytes / 1024).ceil()} KB' : '${(o.usedBytes / _mb).toStringAsFixed(1)} MB'} of '
            '${mode.capBytes ~/ _mb} MB used · '
            '${o.pending} waiting to send',
          ),
        ),
        if (o.note != null) Text(o.note!),
        FilledButton(
          onPressed: o.downloading || mode == OfflineMode.onlineOnly
              ? null
              : o.refill,
          child: Text(o.downloading ? 'Downloading…' : 'Download now'),
        ),
      ],
    );
  }
}
