import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../settings_provider.dart';

class LearningSettings extends StatelessWidget {
  const LearningSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsProvider>();
    final value = p.reminder;
    final parts = (value ?? '20:00').split(':');
    final time = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
    Future<void> choose() async {
      final chosen = await showTimePicker(context: context, initialTime: time);
      if (chosen != null) {
        await p.setReminder(
          '${chosen.hour.toString().padLeft(2, '0')}:${chosen.minute.toString().padLeft(2, '0')}',
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s,
      children: [
        DropdownButtonFormField<int>(
          isExpanded: true,
          key: ValueKey(p.weeklyGoal),
          initialValue: p.weeklyGoal ?? 0,
          decoration: const InputDecoration(labelText: 'Weekly goal'),
          items: [
            const DropdownMenuItem(value: 0, child: Text('No weekly goal')),
            for (var days = 1; days <= 7; days++)
              DropdownMenuItem(
                value: days,
                child: Text('$days ${days == 1 ? 'day' : 'days'} a week'),
              ),
          ],
          onChanged: p.busy || p.dataBusy
              ? null
              : (days) => p.setWeeklyGoal(days == 0 ? null : days),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Daily reminder'),
          subtitle: const Text('Optional · uses this phone’s local time'),
          value: value != null,
          onChanged: p.dataBusy
              ? null
              : (on) => on ? choose() : p.setReminder(null),
        ),
        if (value != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reminder time'),
            subtitle: Text(time.format(context)),
            trailing: TextButton(
              onPressed: p.dataBusy ? null : choose,
              child: const Text('Change time'),
            ),
          ),
        const Text(
          'Android may deliver reminders a little later to save battery.',
        ),
        if (p.dataError != null) Text(p.dataError!),
      ],
    );
  }
}
