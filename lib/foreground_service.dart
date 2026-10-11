import 'dart:async';
import 'dart:math';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:sensors_plus/sensors_plus.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SecretaryTaskHandler());
}

class SecretaryTaskHandler extends TaskHandler {
  StreamSubscription? _accelSub;
  DateTime? _lastShake;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 🔴 كود الهز - شغال حتى لو التطبيق مقفول
    _accelSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      double gX = event.x / 9.81;
      double gY = event.y / 9.81;
      double gZ = event.z / 9.81;
      double gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

      if (gForce > 2.2) {
        final now = DateTime.now();
        if (_lastShake != null && now.difference(_lastShake!) < const Duration(seconds: 3)) return;
        _lastShake = now;

        // نبعت إشارة للـ main isolate
        FlutterForegroundTask.sendDataToMain('SHAKE_DETECTED');

        // نفتح التطبيق
        FlutterForegroundTask.launchApp();
      }
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _accelSub?.cancel();
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}

Future<void> initForegroundService() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'secretary_foreground',
      channelName: 'السكرتيرة الذكية',
      channelDescription: 'الخدمة في الخلفية',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

Future<void> startForegroundService() async {
  if (await FlutterForegroundTask.isRunningService) {
    return;
  }
  await FlutterForegroundTask.startService(
    notificationTitle: 'السكرتيرة جاهزة',
    notificationText: 'التطبيق شغال في الخلفية',
    callback: startCallback,
  );
}

Future<void> stopForegroundService() async {
  await FlutterForegroundTask.stopService();
}
