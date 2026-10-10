import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ─── مهمة الخدمة في الخلفية ───
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SecretaryTaskHandler());
}

class SecretaryTaskHandler extends TaskHandler {
  int _seconds = 0;
  Timer? _timer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _seconds++;
      FlutterForegroundTask.updateService(
        notificationTitle: 'السكرتيرة جاهزة',
        notificationText: 'التطبيق شغال في الخلفية',
      );
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // تكرار كل فترة - مش محتاجينه دلوقتي
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _timer?.cancel();
  }

  @override
  void onNotificationButtonPressed(String id) {
    // زرار الإشعار
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}

// ─── تشغيل الخدمة ───
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
