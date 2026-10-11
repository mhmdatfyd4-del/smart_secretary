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
  int _shakeCount = 0;
  int _eventCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      _accelSub = accelerometerEventStream().listen((AccelerometerEvent event) {
        _eventCount++;
        
        // 🔴 نعرض عدد الأحداث في الإشعار
        if (_eventCount % 100 == 0) {
          FlutterForegroundTask.updateService(
            notificationTitle: 'السكرتيرة جاهزة',
            notificationText: 'أحداث: $_eventCount • هزات: $_shakeCount',
          );
        }

        double gX = event.x / 9.81;
        double gY = event.y / 9.81;
        double gZ = event.z / 9.81;
        double gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

        if (gForce > 2.2) {
          final now = DateTime.now();
          if (_lastShake != null && now.difference(_lastShake!) < const Duration(seconds: 3)) return;
          _lastShake = now;
          _shakeCount++;

          FlutterForegroundTask.updateService(
            notificationTitle: 'السكرتيرة جاهزة',
            notificationText: 'هزات: $_shakeCount',
          );

          FlutterForegroundTask.sendDataToMain('SHAKE_DETECTED');
          FlutterForegroundTask.launchApp();
        }
      });

      FlutterForegroundTask.updateService(
        notificationTitle: 'السكرتيرة جاهزة',
        notificationText: 'تم تشغيل مراقبة الهز',
      );
    } catch (e) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'خطأ في المراقبة',
        notificationText: '$e',
      );
    }
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
