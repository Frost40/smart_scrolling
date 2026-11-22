import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:smart_scrolling/data/services/reminder_service.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var allowed = false;
  var zone = 'Europe/Rome';
  setUp(() {
    zone = 'Europe/Rome';
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    allowed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            calls.add(call);
            if (call.method == 'requestNotificationsPermission') return allowed;
            return true;
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => zone,
        );
  });
  test('Android GMT timezone aliases can schedule reminders', () async {
    zone = 'GMT';
    await ReminderService().restore('20:30');
    expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
  });
  test(
    'initialization does not request permission; denial never schedules',
    () async {
      final service = ReminderService();
      await service.restore(null);
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        isEmpty,
      );
      expect(await service.requestPermission(), false);
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      allowed = true;
      expect(await service.requestPermission(), true);
      await service.restore('20:30:00');
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
      await service.restore(null);
      expect(calls.last.method, 'cancel');
    },
  );
  test('next reminder uses local calendar days across DST', () {
    tz.initializeTimeZones();
    final rome = tz.getLocation('Europe/Rome');
    final next = ReminderService.nextTime(
      '20:30:00',
      tz.TZDateTime(rome, 2026, 10, 24, 21),
    );
    expect(next, tz.TZDateTime(rome, 2026, 10, 25, 20, 30));
    expect(() => ReminderService.nextTime('25:00', next), throwsArgumentError);
  });
}
