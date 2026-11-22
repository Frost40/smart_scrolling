import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  Future<void> _initialize() => _ready ??= () async {
    tz.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_reminder'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }();

  Future<bool> requestPermission() async {
    await _initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true, badge: false) ??
        false;
  }

  /// Restoring a saved reminder never asks for permission.
  Future<void> restore(String? time) async {
    await _initialize();
    if (time == null) {
      await _plugin.cancel(id: 13);
      return;
    }
    final zone = await FlutterTimezone.getLocalTimezone();
    final location = tz.getLocation(zone.identifier);
    await _plugin.zonedSchedule(
      id: 13,
      title: 'A little learning today',
      body: 'Your Practice cards are waiting.',
      scheduledDate: nextTime(time, tz.TZDateTime.now(location)),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_learning',
          'Daily learning reminder',
          channelDescription: 'Your optional daily Practice reminder',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime nextTime(String time, tz.TZDateTime now) {
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$').hasMatch(time)) {
      throw ArgumentError.value(time, 'time');
    }
    final parts = time.split(':').map(int.parse).toList();
    var date = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
      parts[0],
      parts[1],
    );
    if (!date.isAfter(now)) {
      date = tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day + 1,
        parts[0],
        parts[1],
      );
    }
    return date;
  }
}
