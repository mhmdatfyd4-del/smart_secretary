// ══════════════════════════════════════════════════════
// PART 1 / 8
// Imports + Globals + Helpers + main() + AppSettings
// ══════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:adhan/adhan.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:device_info_plus/device_info_plus.dart';

final StreamController<Map<String, dynamic>> _diaryVoiceStream = StreamController.broadcast();

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
final FlutterTts _appTts = FlutterTts();
final StreamController<String> _notificationActionController = StreamController<String>.broadcast();

const List<String> _weekDays = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];

const MethodChannel _lockScreenChannel = MethodChannel('com.m7md.secretary_app/lock_screen');
const MethodChannel _settingsChannel = MethodChannel('com.m7md.secretary_app/settings');
const MethodChannel _nativeAlarmChannel = MethodChannel('com.m7md.secretary_app/native_alarm');
const MethodChannel _soundChannel = MethodChannel('com.m7md.secretary_app/sounds');
const MethodChannel _wakeWordChannel = MethodChannel('com.m7md.secretary_app/wake_word');
const MethodChannel _shakeChannel = MethodChannel('com.m7md.secretary_app/shake');

const Map<String, String> _maleNamesMap = {
  'محمد': 'assets/mohamed.png',
  'أحمد': 'assets/ahmed.png',
  'علي': 'assets/ali.png',
  'عمر': 'assets/omar.png',
  'يوسف': 'assets/youssef.png',
};

const Map<String, String> _femaleNamesMap = {
  'سارة': 'assets/secretary.png',
  'مريم': 'assets/maryam.png',
  'ندى': 'assets/nada.png',
  'نور': 'assets/noor.png',
  'ياسمين': 'assets/yasmine.png',
};

const String _defaultMaleImage = 'assets/mohamed.png';
const String _defaultFemaleImage = 'assets/secretary.png';

String _getSecretaryImage(String name, String voiceGender, {String? customImagePath}) {
  if (customImagePath != null && customImagePath.isNotEmpty) return customImagePath;
  if (_maleNamesMap.containsKey(name)) return _maleNamesMap[name]!;
  if (_femaleNamesMap.containsKey(name)) return _femaleNamesMap[name]!;
  return voiceGender == 'ذكر' ? _defaultMaleImage : _defaultFemaleImage;
}

List<String> _getNamesForGender(String voiceGender) {
  return voiceGender == 'ذكر' ? _maleNamesMap.keys.toList() : _femaleNamesMap.keys.toList();
}

AndroidNotificationSound? _getNotificationSound(String? soundUri) {
  if (soundUri == null || soundUri.isEmpty || soundUri == 'default') return null;
  if (soundUri.startsWith('raw://')) {
    final fileName = soundUri.replaceFirst('raw://', '');
    return RawResourceAndroidNotificationSound(fileName);
  }
  return UriAndroidNotificationSound(soundUri);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting('ar');
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
  HijriCalendar.setLocal('ar');
  await _initNotifications();

  final prefs = await SharedPreferences.getInstance();
  bool isFirstTime = prefs.getBool('is_first_time') ?? true;
  String? secretaryName = prefs.getString('secretary_name');
  bool? isUserMale = prefs.getBool('is_user_male');
  bool showAboveLockScreen = prefs.getBool('show_above_lock_screen') ?? false;

  try {
    if (showAboveLockScreen) {
      await _lockScreenChannel.invokeMethod('enableShowWhenLocked');
    } else {
      await _lockScreenChannel.invokeMethod('disableShowWhenLocked');
    }
  } catch (_) {}

  runApp(SecretaryApp(
    isFirstTime: isFirstTime,
    savedName: secretaryName,
    savedIsUserMale: isUserMale,
  ));
}

Future<void> _initNotifications() async {
  const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: androidInit);
  await _notifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (response) {
      if (response.actionId == 'cancel_alarm') {
        _notificationActionController.add('cancel');
      }
      if (response.actionId == 'stop_recording') {
        _notificationActionController.add('stop_recording');
      }
    },
  );
}

String _norm(String s) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  var out = s.toLowerCase().replaceAll(RegExp(r'[\u064B-\u0652]'), '');
  for (var i = 0; i < arabicDigits.length; i++) {
    out = out.replaceAll(arabicDigits[i], i.toString());
  }
  return out.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي');
}

bool _hasAny(String normalizedText, List<String> keys) {
  return keys.any((k) => normalizedText.contains(_norm(k)));
}

const Map<String, int> _hourWords = {
  'واحده': 1, 'الواحده': 1, 'اتنين': 2, 'اثنين': 2, 'الثانيه': 2,
  'تلاته': 3, 'ثلاثه': 3, 'الثالثه': 3, 'اربعه': 4, 'الرابعه': 4,
  'خمسه': 5, 'الخامسه': 5, 'الخمسه': 5, 'سته': 6, 'السادسه': 6,
  'سبعه': 7, 'السابعه': 7, 'تمانيه': 8, 'ثمانيه': 8, 'الثامنه': 8,
  'تسعه': 9, 'التاسعه': 9, 'عشره': 10, 'العاشره': 10,
  'احداشر': 11, 'حداشر': 11, 'اتناشر': 12, 'اثناعشر': 12,
};

int? _parseHour(String cmd) {
  if (cmd.contains('الحاديه عشره')) return 11;
  if (cmd.contains('الثانيه عشره')) return 12;
  final m = RegExp(r'\d{1,2}').firstMatch(cmd);
  if (m != null) {
    final v = int.parse(m.group(0)!);
    if (v <= 23) return v;
  }
  for (final token in cmd.split(RegExp(r'\s+'))) {
    final h = _hourWords[token];
    if (h != null) return h;
  }
  return null;
}

int _parseMinute(String cmd) {
  final colon = RegExp(r':(\d{2})').firstMatch(cmd);
  if (colon != null) return min(59, int.parse(colon.group(1)!));
  if (cmd.contains('ونص')) return 30;
  if (cmd.contains('وربع')) return 15;
  if (cmd.contains('وثلث')) return 20;
  return 0;
}

String _formatRemaining(DateTime target) {
  final now = DateTime.now();
  final diff = target.difference(now);
  if (diff.isNegative) return 'انتهى';
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  if (days > 0) {
    if (hours > 0) return 'فاضل $days يوم و $hours ساعة';
    return 'فاضل $days يوم';
  } else if (hours > 0) {
    if (minutes > 0) return 'فاضل $hours ساعة و $minutes دقيقة';
    return 'فاضل $hours ساعة';
  } else if (minutes > 0) {
    return 'فاضل $minutes دقيقة';
  } else {
    return 'فاضل أقل من دقيقة';
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes.toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

DateTime _sortTime(Map<String, dynamic> item) {
  try {
    final s = item['scheduled']?.toString() ?? item['eventDate']?.toString() ?? '';
    if (s.isNotEmpty) {
      final dt = DateTime.tryParse(s);
      if (dt != null) return dt;
    }
  } catch (_) {}
  return DateTime(9999, 12, 31);
}

void _sortByTime(List<Map<String, dynamic>> list) {
  list.sort((a, b) => _sortTime(a).compareTo(_sortTime(b)));
}

String _getHijriDate(DateTime date) {
  final hijri = HijriCalendar.fromDate(date);
  return '${hijri.hDay} ${hijri.longMonthName} ${hijri.hYear} هـ';
}

class AppSettings {
  int defaultReminderHour;
  int defaultReminderMinute;
  String voiceLevel;
  bool greetingEnabled;
  bool adhanAlertEnabled;
  bool showAboveLockScreen;
  String shakeMode;
  bool muteBeep;
  String voiceGender;
  String defaultInterval;
  String customWakeWord;
  String wakeWordMode;
  String wakeWordTrigger;
  bool useOverlayAlarm;
  bool isKidsMode;
  String customGreeting;
  bool tahajjudAlertEnabled;
  bool isDarkMode;
  String? customImagePath;
  bool salatAlaNabiEnabled;
  String salatAlaNabiInterval;
  String customUserTitle;
  String customSecTitle;
  String stopRecordMode;
  int snoozeMinutes;
  bool diaryLockEnabled;
  String diaryPin;
  String diarySecurityQuestion;
  String diarySecurityAnswer;
  bool isProUser; // 👈 التعديل

  AppSettings({
    this.defaultReminderHour = 18,
    this.defaultReminderMinute = 0,
    this.voiceLevel = 'متوسط',
    this.greetingEnabled = true,
    this.adhanAlertEnabled = true,
    this.showAboveLockScreen = false,
    this.shakeMode = 'app_open',
    this.muteBeep = true,
    this.voiceGender = 'ذكر',
    this.defaultInterval = 'كل 10 ثواني',
    this.customWakeWord = 'يا سكرتير',
    this.wakeWordMode = 'off',
    this.wakeWordTrigger = 'both',
    this.useOverlayAlarm = false,
    this.isKidsMode = false,
    this.customGreeting = 'أَهْلاً بِكَ {user}. أَنَا {sec} {name}، هُزَّ الهَاتِفَ فِي أَيِّ وَقْتٍ لِأَكُونَ فِي خِدْمَتِكَ.',
    this.tahajjudAlertEnabled = false,
    this.isDarkMode = false,
    this.customImagePath,
    this.salatAlaNabiEnabled = false,
    this.salatAlaNabiInterval = 'كل ساعة',
    this.customUserTitle = '',
    this.customSecTitle = '',
    this.stopRecordMode = 'manual_only',
    this.snoozeMinutes = 5,
    this.diaryLockEnabled = false,
    this.diaryPin = '',
    this.diarySecurityQuestion = '',
    this.diarySecurityAnswer = '',
    this.isProUser = false, // 👈 التعديل
  });

  double get speechRate {
    switch (voiceLevel) {
      case 'بطيء': return 0.35;
      case 'متوسط': return 0.5;
      default: return 0.7;
    }
  }

  double get speechVolume {
    switch (voiceLevel) {
      case 'بطيء': return 0.6;
      case 'متوسط': return 0.8;
      default: return 1.0;
    }
  }
}

// ══════════════════════════════════════════════════════
// نهاية PART 1 / 8
// ══════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════
// PART 2 / 8
// SettingsScreen + SecretaryApp + Splash + AnimatedDots
// + TermsAndPermissionsScreen + SetupSecretaryScreen
// ══════════════════════════════════════════════════════

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final double ttsVolume;
  final String currentSecretaryName;
  final bool currentIsUserMale;
  final bool isProUser; // 👈
  final VoidCallback onUpgrade;
  final VoidCallback onAuthChanged;

  final Future<void> Function(
    int hour, int minute, String voiceLevel,
    bool greeting, bool adhan, double ttsVol,
    bool showLock, String shakeMode, String voiceGender,
    String defaultInterval, String customWakeWord,
    String wakeWordMode, String wakeWordTrigger,
    bool muteBeep, bool useOverlayAlarm,
    bool isKidsMode, String customGreeting, bool tahajjudAlertEnabled, bool isDarkMode, String? customImagePath,
    String stopRecordMode,
    int snoozeMinutes, bool diaryLockEnabled, String diaryPin, String diarySecurityQuestion, String diarySecurityAnswer,
  ) onSave;
  final Future<void> Function(String name, String voiceGender) onSaveSecretary;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.ttsVolume,
    required this.currentSecretaryName,
    required this.currentIsUserMale,
    required this.isProUser, // 👈
    required this.onUpgrade,
    required this.onAuthChanged,
    required this.onSave,
    required this.onSaveSecretary,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _defaultReminderHour;
  late int _defaultReminderMinute;
  late String _voiceLevel;
  late bool _greetingEnabled;
  late bool _adhanAlertEnabled;
  late double _ttsVolume;
  late bool _showAboveLockScreen;
  late String _shakeMode;
  late bool _muteBeep;
  late String _voiceGender;
  late String _defaultInterval;
  late String _secretaryName;
  late String _wakeWordMode;
  late String _wakeWordTrigger;
  late bool _useOverlayAlarm;
  late bool _isKidsMode;
  late bool _tahajjudAlertEnabled;
  late bool _isDarkMode;
  String? _customImagePath;
  late bool _salatAlaNabiEnabled;
  late String _salatAlaNabiInterval;
  late bool _origSalatAlaNabiEnabled;
  late String _origSalatAlaNabiInterval;
  late String _stopRecordMode;
  late String _origStopRecordMode;

  late int _snoozeMinutes;
  late bool _diaryLockEnabled;
  late String _diaryPin;
  late String _diarySecurityQuestion;
  late String _diarySecurityAnswer;

  int _restoreClickCount = 0;
  Timer? _restoreTimer;

  final TextEditingController _userTitleController = TextEditingController();
  final TextEditingController _secTitleController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _wakeWordController = TextEditingController();
  final TextEditingController _customGreetingController = TextEditingController();

  late int _origDefaultReminderHour;
  late int _origDefaultReminderMinute;
  late String _origVoiceLevel;
  late bool _origGreetingEnabled;
  late bool _origAdhanAlertEnabled;
  late double _origTtsVolume;
  late bool _origShowAboveLockScreen;
  late String _origShakeMode;
  late bool _origMuteBeep;
  late String _origVoiceGender;
  late String _origDefaultInterval;
  late String _origSecretaryName;
  late String _origWakeWordMode;
  late String _origWakeWordTrigger;
  late bool _origUseOverlayAlarm;
  late bool _origIsKidsMode;
  late String _origCustomGreeting;
  late bool _origTahajjudAlertEnabled;
  late bool _origIsDarkMode;
  String? _origCustomImagePath;
  late int _origSnoozeMinutes;
  late bool _origDiaryLockEnabled;
  late String _origDiaryPin;
  late String _origDiarySecurityQuestion;
  late String _origDiarySecurityAnswer;

  String? _defaultAlarmSound;
  String? _defaultWeeklySound;
  String? _defaultEventSound;
  String? _origDefaultAlarmSound;
  String? _origDefaultWeeklySound;
  String? _origDefaultEventSound;

  @override
  void initState() {
    super.initState();
    _defaultReminderHour = widget.settings.defaultReminderHour;
    _defaultReminderMinute = widget.settings.defaultReminderMinute;
    _voiceLevel = widget.settings.voiceLevel;
    _greetingEnabled = widget.settings.greetingEnabled;
    _adhanAlertEnabled = widget.settings.adhanAlertEnabled;
    _ttsVolume = widget.ttsVolume;
    _showAboveLockScreen = widget.settings.showAboveLockScreen;
    _shakeMode = widget.settings.shakeMode;
    _muteBeep = widget.settings.muteBeep;
    _voiceGender = widget.settings.voiceGender;
    _defaultInterval = widget.settings.defaultInterval;
    _secretaryName = widget.currentSecretaryName;
    _nameController.text = _secretaryName;
    _wakeWordMode = widget.settings.wakeWordMode;
    _wakeWordTrigger = widget.settings.wakeWordTrigger;
    _wakeWordController.text = widget.settings.customWakeWord;
    _useOverlayAlarm = widget.settings.useOverlayAlarm;
    _isKidsMode = widget.settings.isKidsMode;
    _tahajjudAlertEnabled = widget.settings.tahajjudAlertEnabled;
    _isDarkMode = widget.settings.isDarkMode;
    _customGreetingController.text = widget.settings.customGreeting;
    _customImagePath = widget.settings.customImagePath;
    _salatAlaNabiEnabled = widget.settings.salatAlaNabiEnabled;
    _salatAlaNabiInterval = widget.settings.salatAlaNabiInterval;
    _origSalatAlaNabiEnabled = _salatAlaNabiEnabled;
    _origSalatAlaNabiInterval = _salatAlaNabiInterval;
    _userTitleController.text = widget.settings.customUserTitle;
    _secTitleController.text = widget.settings.customSecTitle;
    _stopRecordMode = widget.settings.stopRecordMode;
    _origStopRecordMode = _stopRecordMode;

    _snoozeMinutes = widget.settings.snoozeMinutes;
    _diaryLockEnabled = widget.settings.diaryLockEnabled;
    _diaryPin = widget.settings.diaryPin;
    _diarySecurityQuestion = widget.settings.diarySecurityQuestion;
    _diarySecurityAnswer = widget.settings.diarySecurityAnswer;

    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        _customImagePath = prefs.getString('custom_img_${_nameController.text}');
      });
    });

    _origDefaultReminderHour = _defaultReminderHour;
    _origDefaultReminderMinute = _defaultReminderMinute;
    _origVoiceLevel = _voiceLevel;
    _origGreetingEnabled = _greetingEnabled;
    _origAdhanAlertEnabled = _adhanAlertEnabled;
    _origTtsVolume = _ttsVolume;
    _origShowAboveLockScreen = _showAboveLockScreen;
    _origShakeMode = _shakeMode;
    _origMuteBeep = _muteBeep;
    _origVoiceGender = _voiceGender;
    _origDefaultInterval = _defaultInterval;
    _origSecretaryName = _secretaryName;
    _origWakeWordMode = _wakeWordMode;
    _origWakeWordTrigger = _wakeWordTrigger;
    _origUseOverlayAlarm = _useOverlayAlarm;
    _origIsKidsMode = _isKidsMode;
    _origCustomGreeting = _customGreetingController.text;
    _origTahajjudAlertEnabled = _tahajjudAlertEnabled;
    _origIsDarkMode = _isDarkMode;
    _origCustomImagePath = _customImagePath;

    _origSnoozeMinutes = _snoozeMinutes;
    _origDiaryLockEnabled = _diaryLockEnabled;
    _origDiaryPin = _diaryPin;
    _origDiarySecurityQuestion = _diarySecurityQuestion;
    _origDiarySecurityAnswer = _diarySecurityAnswer;

    _loadSavedSounds();
  }

  Future<void> _loadSavedSounds() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _defaultAlarmSound = prefs.getString('default_alarm_sound');
      _origDefaultAlarmSound = _defaultAlarmSound;

      _defaultWeeklySound = prefs.getString('default_weekly_sound');
      _origDefaultWeeklySound = _defaultWeeklySound;

      _defaultEventSound = prefs.getString('default_event_sound');
      _origDefaultEventSound = _defaultEventSound;
    });
  }

  Future<void> _pickDefaultSound(String type) async {
    final current = type == 'alarm' ? _defaultAlarmSound : (type == 'weekly' ? _defaultWeeklySound : _defaultEventSound);
    final result = await showDialog<String>(
      context: context,
      // 👇 ضفنا isProUser هنا
      builder: (_) => SoundPickerDialog(currentUri: current, voiceGender: widget.settings.voiceGender, isProUser: widget.isProUser),
    );
    if (result != null) {
      if (!mounted) return;
      setState(() {
        if (type == 'alarm') _defaultAlarmSound = result == 'default' ? null : result;
        else if (type == 'weekly') _defaultWeeklySound = result == 'default' ? null : result;
        else _defaultEventSound = result == 'default' ? null : result;
      });
    }
  }

  Future<void> _pickCustomImage() async {
    final ImagePicker picker = ImagePicker();
    showModalBottomSheet(context: context, builder: (ctx) {
      return SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('التقاط صورة'),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? image = await picker.pickImage(source: ImageSource.camera);
                if (image != null) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('custom_img_${_nameController.text}', image.path);
                  setState(() => _customImagePath = image.path);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('اختيار من المعرض'),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('custom_img_${_nameController.text}', image.path);
                  setState(() => _customImagePath = image.path);
                }
              },
            ),
          ],
        ),
      );
    });
  }

  Future<void> _showChangePasswordDialog() async {
    final oldPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final newQCtrl = TextEditingController(text: _diarySecurityQuestion);
    final newACtrl = TextEditingController(text: _diarySecurityAnswer);
    bool showForgot = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('تغيير كلمة السر'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!showForgot) ...[
                  TextField(controller: oldPinCtrl, keyboardType: TextInputType.number, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة السر القديمة', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => setStateDialog(() => showForgot = true),
                    child: const Text('نسيت كلمة السر القديمة؟', style: TextStyle(color: Colors.red)),
                  ),
                ],
                TextField(controller: newPinCtrl, keyboardType: TextInputType.number, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة السر الجديدة', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: newQCtrl, decoration: const InputDecoration(labelText: 'سؤال الأمان الجديد (اختياري)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: newACtrl, decoration: const InputDecoration(labelText: 'إجابة سؤال الأمان الجديد (اختياري)', border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (showForgot) {
                  if (_norm(newACtrl.text.trim()) == _norm(_diarySecurityAnswer.trim()) && _diarySecurityAnswer.isNotEmpty) {
                    setState(() {
                      _diaryPin = newPinCtrl.text;
                      if (newQCtrl.text.isNotEmpty) _diarySecurityQuestion = newQCtrl.text;
                      if (newACtrl.text.isNotEmpty) _diarySecurityAnswer = newACtrl.text;
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التغيير بنجاح'), backgroundColor: Colors.green));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('إجابة سؤال الأمان خاطئة!'), backgroundColor: Colors.red));
                  }
                } else {
                  if (oldPinCtrl.text == _diaryPin) {
                    setState(() {
                      _diaryPin = newPinCtrl.text;
                      if (newQCtrl.text.isNotEmpty) _diarySecurityQuestion = newQCtrl.text;
                      if (newACtrl.text.isNotEmpty) _diarySecurityAnswer = newACtrl.text;
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التغيير بنجاح'), backgroundColor: Colors.green));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة السر القديمة خاطئة!'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('حفظ'),
            )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _wakeWordController.dispose();
    _customGreetingController.dispose();
    _userTitleController.dispose();
    _secTitleController.dispose();
    _restoreTimer?.cancel();
    super.dispose();
  }

  bool get _hasChanges {
    return _defaultReminderHour != _origDefaultReminderHour ||
        _defaultReminderMinute != _origDefaultReminderMinute ||
        _voiceLevel != _origVoiceLevel ||
        _greetingEnabled != _origGreetingEnabled ||
        _adhanAlertEnabled != _origAdhanAlertEnabled ||
        _ttsVolume != _origTtsVolume ||
        _showAboveLockScreen != _origShowAboveLockScreen ||
        _shakeMode != _origShakeMode ||
        _muteBeep != _origMuteBeep ||
        _voiceGender != _origVoiceGender ||
        _defaultInterval != _origDefaultInterval ||
        _nameController.text != _origSecretaryName ||
        _wakeWordMode != _origWakeWordMode ||
        _wakeWordTrigger != _origWakeWordTrigger ||
        _wakeWordController.text != widget.settings.customWakeWord ||
        _useOverlayAlarm != _origUseOverlayAlarm ||
        _isKidsMode != _origIsKidsMode ||
        _customGreetingController.text != _origCustomGreeting ||
        _tahajjudAlertEnabled != _origTahajjudAlertEnabled ||
        _isDarkMode != _origIsDarkMode ||
        _defaultAlarmSound != _origDefaultAlarmSound ||
        _defaultWeeklySound != _origDefaultWeeklySound ||
        _defaultEventSound != _origDefaultEventSound ||
        _salatAlaNabiEnabled != _origSalatAlaNabiEnabled ||
        _salatAlaNabiInterval != _origSalatAlaNabiInterval ||
        _stopRecordMode != _origStopRecordMode ||
        _userTitleController.text != widget.settings.customUserTitle ||
        _secTitleController.text != widget.settings.customSecTitle ||
        _customImagePath != _origCustomImagePath ||
        _snoozeMinutes != _origSnoozeMinutes ||
        _diaryLockEnabled != _origDiaryLockEnabled ||
        _diaryPin != _origDiaryPin ||
        _diarySecurityQuestion != _origDiarySecurityQuestion ||
        _diarySecurityAnswer != _origDiarySecurityAnswer;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_defaultAlarmSound == null) await prefs.remove('default_alarm_sound'); else await prefs.setString('default_alarm_sound', _defaultAlarmSound!);
    if (_defaultWeeklySound == null) await prefs.remove('default_weekly_sound'); else await prefs.setString('default_weekly_sound', _defaultWeeklySound!);
    if (_defaultEventSound == null) await prefs.remove('default_event_sound'); else await prefs.setString('default_event_sound', _defaultEventSound!);
    await prefs.setBool('salat_ala_nabi_enabled', _salatAlaNabiEnabled);
    await prefs.setString('salat_ala_nabi_interval', _salatAlaNabiInterval);
    await prefs.setString('custom_user_title', _userTitleController.text.trim());
    await prefs.setString('custom_sec_title', _secTitleController.text.trim());

    final newName = _nameController.text.trim().isEmpty
        ? (_voiceGender == 'ذكر' ? 'محمد' : 'سارة')
        : _nameController.text.trim();

    await widget.onSave(
      _defaultReminderHour, _defaultReminderMinute, _voiceLevel,
      _greetingEnabled, _adhanAlertEnabled, _ttsVolume,
      _showAboveLockScreen, _shakeMode, _voiceGender,
      _defaultInterval, _wakeWordController.text.trim(), _wakeWordMode, _wakeWordTrigger,
      _muteBeep, _useOverlayAlarm,
      _isKidsMode, _customGreetingController.text.trim(), _tahajjudAlertEnabled, _isDarkMode, _customImagePath,
      _stopRecordMode,
      _snoozeMinutes, _diaryLockEnabled, _diaryPin, _diarySecurityQuestion, _diarySecurityAnswer,
    );
    await widget.onSaveSecretary(newName, _voiceGender);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = _getNamesForGender(_voiceGender);
    final defaultSecTitle = _voiceGender == 'ذكر' ? 'السكرتير' : 'السكرتيرة';
    final secTitle = _secTitleController.text.trim().isNotEmpty ? _secTitleController.text.trim() : defaultSecTitle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B2A4A),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 👇 كارت الحساب الشخصي
Card(
  elevation: 2,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        if (FirebaseAuth.instance.currentUser != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle, color: Color(0xFF1B2A4A), size: 40),
            title: Text(
              FirebaseAuth.instance.currentUser?.displayName ?? 'مستخدم',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              FirebaseAuth.instance.currentUser?.email ?? '',
              style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password, color: Colors.blue),
            title: const Text('تغيير كلمة المرور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null && user.email != null) {
                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم إرسال رابط تغيير كلمة المرور إلى بريدك'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red));
                  }
                }
              }
            },
          ),
          // 👇 زرار الأجهزة المتصلة (بيظهر بس لو فيه أكتر من جهاز)
StreamBuilder<DocumentSnapshot>(
  stream: FirebaseAuth.instance.currentUser != null
      ? FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots()
      : const Stream.empty(),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
      final devices = data['devices'] as Map<String, dynamic>? ?? {};
      if (devices.length > 1) { // بيظهر بس لو 2 أو أكتر
        return Column(
          children: [
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.devices, color: Colors.green),
              title: const Text('الأجهزة المتصلة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => _showManageDevicesDialog(),
            ),
          ],
        );
      }
    }
    return const SizedBox.shrink();
  },
),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red)),
            onTap: () async {
              bool? confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تسجيل الخروج'),
                  content: const Text('هل أنت متأكد أنك تريد تسجيل الخروج؟'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('خروج', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await FirebaseAuth.instance.signOut();
                const storage = FlutterSecureStorage();
                await storage.delete(key: 'is_pro_user');
                widget.onAuthChanged();
                if (mounted) setState(() {});
              }
            },
          ),
        ] else ...[
          const Row(
            children: [
              Icon(Icons.account_circle, color: Colors.grey, size: 40),
              SizedBox(width: 12),
              Text('حسابك الشخصي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 15),
          const Text('سجل دخولك أو أنشئ حساباً جديداً للاستفادة من النسخة البرو وإدارة الأجهزة.', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 15),
         Row(
  children: [
    Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        onPressed: () async {
          // 👇 زرار تسجيل الدخول بيفتح الشاشة عادي
          await Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen()));
          widget.onAuthChanged();
          if (mounted) setState(() {});
        },
        child: const Text('تسجيل الدخول', style: TextStyle(color: Colors.white, fontSize: 13)),
      ),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC5A059), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        onPressed: () async {
          // 👇 زرار إنشاء حساب بيفتح الشاشة على وضع التسجيل مباشرة
          await Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(startInRegisterMode: true)));
          widget.onAuthChanged();
          if (mounted) setState(() {});
        },
        child: const Text('إنشاء حساب', style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    ),
  ],
)
        ]
      ],
    ),
  ),
),
const SizedBox(height: 12),
          // 👇 بانر الترقية للبرو
          if (!widget.isProUser) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF2C3E50)], begin: Alignment.topRight, end: Alignment.bottomLeft),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.onUpgrade,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.workspace_premium, color: Color(0xFFC5A059), size: 40),
                        const SizedBox(width: 15),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ترقية للنسخة البرو 👑', style: TextStyle(color: Color(0xFFC5A059), fontSize: 18, fontWeight: FontWeight.bold)),
                              SizedBox(height: 4),
                              Text('افتح الأوامر الصوتية، النداء الدائم، والمزيد...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFFC5A059), borderRadius: BorderRadius.circular(20)),
                          child: const Text('50 ج.م', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.record_voice_over, color: Color(0xFF1B2A4A), size: 26),
                    SizedBox(width: 10),
                    Text('تحديد نوع السكرتير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _voiceGender,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: ['ذكر', 'أنثى'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _voiceGender = val;
                        final newNames = _getNamesForGender(val);
                        if (!newNames.contains(_nameController.text)) {
                          _nameController.text = val == 'ذكر' ? 'محمد' : 'سارة';
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // 👇 كروت النغمات (مفتوحة للكل دلوقتي)
          Card(
            elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _pickDefaultSound('alarm'),
              child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                const Icon(Icons.notifications_active, color: Color(0xFF1B2A4A), size: 26), const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('🎵 صوت منبه المهام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(_defaultAlarmSound == null ? 'الافتراضي' : 'مخصص', style: TextStyle(fontSize: 12, color: _defaultAlarmSound != null ? const Color(0xFFC5A059) : Colors.grey)),
                ])),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF1B2A4A)),
              ])),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _pickDefaultSound('weekly'),
              child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                const Icon(Icons.calendar_month, color: Color(0xFF1B2A4A), size: 26), const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('🎵 صوت منبه الجدول الإسبوعي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(_defaultWeeklySound == null ? 'الافتراضي' : 'مخصص', style: TextStyle(fontSize: 12, color: _defaultWeeklySound != null ? const Color(0xFFC5A059) : Colors.grey)),
                ])),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF1B2A4A)),
              ])),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _pickDefaultSound('event'),
              child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                const Icon(Icons.celebration, color: Color(0xFF1B2A4A), size: 26), const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('🎵 صوت المناسبات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(_defaultEventSound == null ? 'الافتراضي' : 'مخصص', style: TextStyle(fontSize: 12, color: _defaultEventSound != null ? const Color(0xFFC5A059) : Colors.grey)),
                ])),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF1B2A4A)),
              ])),
            ),
          ),
          const SizedBox(height: 12),
          
          // 👇 كارت السكرتير (مقفول للبرو)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isProUser) ...[
                    Row(children: [ Text(secTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)) ]),
                    const SizedBox(height: 10),
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          GestureDetector(
                            onTap: _pickCustomImage,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 100, height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFC5A059), width: 3),
                                image: DecorationImage(
                                  image: _customImagePath != null ? FileImage(File(_customImagePath!)) as ImageProvider : AssetImage(_getSecretaryImage(_nameController.text, _voiceGender)),
                                  fit: BoxFit.cover, alignment: Alignment.topCenter,
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Color(0xFF1B2A4A), shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ),
                          if (_customImagePath != null)
                            Positioned(
                              top: 0, left: 0,
                              child: GestureDetector(
                                onTap: () async {
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.remove('custom_img_${_nameController.text}');
                                  setState(() => _customImagePath = null);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text('اختر أو أضف اسماً:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0, runSpacing: 8.0,
                      children: names.map((name) {
                        final isSelected = _nameController.text == name;
                        return ActionChip(
                          label: Text(name),
                          backgroundColor: isSelected ? const Color(0xFFC5A059) : Colors.grey.shade200,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onPressed: () async {
                            setState(() => _nameController.text = name);
                            final prefs = await SharedPreferences.getInstance();
                            setState(() {
                              _customImagePath = prefs.getString('custom_img_$name');
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameController,
                      onChanged: (v) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'اسم $secTitle',
                        prefixIcon: const Icon(Icons.badge, color: Color(0xFF1B2A4A)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ] else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.face, color: Colors.grey, size: 30),
                      title: const Text('تخصيص السكرتير (الاسم والصورة)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                      subtitle: const Text('متاح في النسخة البرو 👑', style: TextStyle(color: Color(0xFFC5A059), fontSize: 12)),
                      trailing: const Icon(Icons.lock, color: Color(0xFFC5A059)),
                      onTap: widget.onUpgrade,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // 👇 كارت وقت التذكير
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.access_time, color: Color(0xFF1B2A4A), size: 30),
              title: const Text('وقت التذكير الافتراضي للمناسبات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DateFormat('hh:mm a', 'en').format(DateTime(2024, 1, 1, _defaultReminderHour, _defaultReminderMinute)).replaceAll('PM', 'م').replaceAll('AM', 'ص'),
                  style: const TextStyle(fontSize: 20, color: Color(0xFFC5A059), fontWeight: FontWeight.bold),
                ),
              ),
              trailing: const Icon(Icons.edit, color: Color(0xFF1B2A4A)),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: _defaultReminderHour, minute: _defaultReminderMinute),
                );
                if (t != null) setState(() { _defaultReminderHour = t.hour; _defaultReminderMinute = t.minute; });
              },
            ),
          ),
          const SizedBox(height: 12),
          
          // 👇 كارت التنبيه المستمر
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.notifications_active, color: Color(0xFF1B2A4A), size: 26),
                    SizedBox(width: 10),
                    Text('التنبيه المستمر الافتراضي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _defaultInterval,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: ['بدون تنبيه', 'مرة واحدة', 'كل 10 ثواني', 'كل 20 ثانية', 'كل 30 ثانية', 'كل دقيقة', 'كل دقيقتين', 'كل 3 دقايق', 'كل 5 دقايق', 'كل 10 دقايق']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (val) => setState(() => _defaultInterval = val ?? 'كل 10 ثواني'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // 👇 كارت التأجيل
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.snooze, color: Color(0xFF1B2A4A), size: 26),
                    SizedBox(width: 10),
                    Text('مدة تأجيل المنبه (Snooze)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _snoozeMinutes,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [5, 10, 15, 20].map((v) => DropdownMenuItem(value: v, child: Text('$v دقائق'))).toList(),
                    onChanged: (val) => setState(() => _snoozeMinutes = val ?? 5),
                  ),
                ],
              ),
            ),
          ),
          
          // 👇 قفل اليوميات (مقفول للبرو)
          const SizedBox(height: 12),
          if (widget.isProUser)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.lock, color: Color(0xFF1B2A4A), size: 26),
                      title: const Text('تفعيل قفل اليوميات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      value: _diaryLockEnabled,
                      activeColor: const Color(0xFF1B2A4A),
                      onChanged: (val) => setState(() => _diaryLockEnabled = val),
                    ),
                    if (_diaryLockEnabled) ...[
                      const Divider(),
                      if (_diaryPin.isEmpty) ...[
                        TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'كلمة السر الجديدة (أرقام)', border: OutlineInputBorder()),
                          onChanged: (val) => _diaryPin = val,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          decoration: const InputDecoration(labelText: 'سؤال الأمان (مثال: اسم معلمك)', border: OutlineInputBorder()),
                          onChanged: (val) => _diarySecurityQuestion = val,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          decoration: const InputDecoration(labelText: 'إجابة سؤال الأمان', border: OutlineInputBorder()),
                          onChanged: (val) => _diarySecurityAnswer = val,
                        ),
                      ] else ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                          icon: const Icon(Icons.lock_reset, color: Colors.white),
                          label: const Text('تغيير كلمة السر أو سؤال الأمان', style: TextStyle(color: Colors.white)),
                          onPressed: _showChangePasswordDialog,
                        ),
                      ]
                    ]
                  ],
                ),
              ),
            )
          else
            Card(
              elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.lock, color: Colors.grey, size: 26),
                title: const Text('قفل اليوميات بكلمة سر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                subtitle: const Text('متاح في النسخة البرو 👑', style: TextStyle(color: Color(0xFFC5A059), fontSize: 12)),
                trailing: const Icon(Icons.lock, color: Color(0xFFC5A059)),
                onTap: widget.onUpgrade,
              ),
            ),
          
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.speed, color: Color(0xFF1B2A4A), size: 26),
                    SizedBox(width: 10),
                    Text('سرعة الصوت', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _voiceLevel,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: ['سريع', 'متوسط', 'بطيء'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (val) => setState(() => _voiceLevel = val ?? 'متوسط'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.record_voice_over, color: Color(0xFF1B2A4A), size: 26),
                    const SizedBox(width: 10),
                    Text('صوت $secTitle', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  Row(children: [
                    Expanded(
                      child: Slider(
                        value: _ttsVolume, min: 0.0, max: 1.0,
                        activeColor: const Color(0xFFC5A059),
                        onChanged: (val) => setState(() => _ttsVolume = val),
                      ),
                    ),
                    Text('${(_ttsVolume * 100).toInt()}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SwitchListTile(
              secondary: const Icon(Icons.volume_off, color: Color(0xFF1B2A4A), size: 26),
              title: const Text('كتم صوت تنبيه المايك', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('بيمنع الصوت المزعج لما المايك يفتح', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              value: _muteBeep,
              activeColor: const Color(0xFF1B2A4A),
              onChanged: (v) => setState(() => _muteBeep = v),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SwitchListTile(
              secondary: const Icon(Icons.waving_hand, color: Color(0xFF1B2A4A), size: 26),
              title: const Text('الجملة الترحيبية عند البدء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              value: _greetingEnabled,
              activeColor: const Color(0xFF1B2A4A),
              onChanged: (v) => setState(() => _greetingEnabled = v),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SwitchListTile(
              secondary: const Icon(Icons.mosque, color: Color(0xFF1B2A4A), size: 26),
              title: const Text('تنبيه الأذان', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              value: _adhanAlertEnabled,
              activeColor: const Color(0xFF1B2A4A),
              onChanged: (v) => setState(() => _adhanAlertEnabled = v),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.favorite, color: Color(0xFFC5A059), size: 26),
                    SizedBox(width: 10),
                    Text('تذكير الصلاة على النبي ﷺ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تشغيل التذكير الصوتي', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    value: _salatAlaNabiEnabled,
                    activeColor: const Color(0xFF1B2A4A),
                    onChanged: (v) => setState(() => _salatAlaNabiEnabled = v),
                  ),
                  if (_salatAlaNabiEnabled) ...[
                    const Divider(),
                    const Text('التكرار:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _salatAlaNabiInterval,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: ['كل ساعة', 'كل ساعتين', 'كل 3 ساعات', 'كل 4 ساعات', 'كل 6 ساعات'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (val) => setState(() => _salatAlaNabiInterval = val ?? 'كل ساعة'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _showAboveLockScreen ? const Color(0xFFC5A059) : Colors.transparent, width: 2),
            ),
            child: SwitchListTile(
              secondary: Icon(Icons.lock_open, color: _showAboveLockScreen ? const Color(0xFFC5A059) : const Color(0xFF1B2A4A), size: 26),
              title: const Text('إظهار التطبيق فوق شاشة القفل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _showAboveLockScreen ? 'التطبيق هيظهر تلقائياً عند التنبيه' : 'التطبيق مش هيظهر والتابلت مقفول',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              value: _showAboveLockScreen,
              activeColor: const Color(0xFFC5A059),
              onChanged: (v) => setState(() => _showAboveLockScreen = v),
            ),
          ),
          // 👇 تشغيل الهز (برو)
const SizedBox(height: 12),
if (widget.isProUser)
  Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.vibration, color: _shakeMode != 'off' ? const Color(0xFFC5A059) : const Color(0xFF1B2A4A), size: 26),
            const SizedBox(width: 10),
            const Text('تشغيل الهز', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _shakeMode,
            decoration: const InputDecoration(labelText: 'حالة الهز', border: OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: 'off', child: Text('متوقف')),
              DropdownMenuItem(value: 'app_open', child: Text('التطبيق مفتوح فقط')),
              DropdownMenuItem(value: 'background', child: Text('التطبيق مفتوح + الخلفية')),
              DropdownMenuItem(value: 'always', child: Text('دائماً (حتى لو التطبيق مقفول)')),
            ],
            onChanged: (val) => setState(() => _shakeMode = val ?? 'off'),
          ),
        ],
      ),
    ),
  )
else
  Card(
    elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      leading: const Icon(Icons.vibration, color: Colors.grey, size: 26),
      title: const Text('تشغيل الهز', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
      subtitle: const Text('متاح في النسخة البرو 👑', style: TextStyle(color: Color(0xFFC5A059), fontSize: 12)),
      trailing: const Icon(Icons.lock, color: Color(0xFFC5A059)),
      onTap: widget.onUpgrade,
    ),
  ),
          
          // 👇 إيقاف التسجيل بالهز (مقفول للبرو)
          const SizedBox(height: 12),
          if (widget.isProUser)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.stop_circle, color: Color(0xFF1B2A4A), size: 26),
                      SizedBox(width: 10),
                      Text('طريقة إيقاف التسجيل الصوتي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _stopRecordMode,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: 'shake_only', child: Text('بمجرد الهز فقط')),
                        DropdownMenuItem(value: 'manual_only', child: Text('باستخدام الأزرار فقط')),
                      ],
                      onChanged: (val) => setState(() => _stopRecordMode = val ?? 'manual_only'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.stop_circle, color: Colors.grey, size: 26),
                title: const Text('إيقاف التسجيل بالهز', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                subtitle: const Text('متاح في النسخة البرو 👑', style: TextStyle(color: Color(0xFFC5A059), fontSize: 12)),
                trailing: const Icon(Icons.lock, color: Color(0xFFC5A059)),
                onTap: widget.onUpgrade,
              ),
            ),
            
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode, color: Color(0xFF1B2A4A), size: 26),
              title: const Text('الوضع الليلي (Dark Mode)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              value: _isDarkMode,
              activeColor: const Color(0xFF1B2A4A),
              onChanged: (v) => setState(() => _isDarkMode = v),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('لقبك (الافتراضي: يا فندم):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: _userTitleController,
                    onChanged: (v) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'يا فندم، يا كابتن...', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  const Text('لقب السكرتير (الافتراضي: السكرتير):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: _secTitleController,
                    onChanged: (v) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'السكرتير، مساعدي...', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          
          // 👇 كارت الترحيب مع المعاينة الحية
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.waving_hand, color: Color(0xFF1B2A4A), size: 26),
                    SizedBox(width: 10),
                    Text('الترحيب المخصص', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 5),
                  const Text('استخدم {user} للقبك، {sec} للسكرتير، {name} للاسم', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customGreetingController,
                    maxLines: 3,
                    onChanged: (v) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'أَهْلاً بِكَ {user}. أَنَا {sec} {name}...', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC5A059).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFC5A059), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('معاينة الترحيب (كما سيسمعه المستخدم):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
                        const SizedBox(height: 5),
                        Text(
                          () {
                            final userTitle = _userTitleController.text.trim().isNotEmpty ? _userTitleController.text.trim() : (widget.currentIsUserMale ? 'يا فندم' : 'يا أستاذة');
                            final secTitle = _secTitleController.text.trim().isNotEmpty ? _secTitleController.text.trim() : (_voiceGender == 'ذكر' ? 'السكرتير' : 'السكرتيرة');
                            final name = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : (_voiceGender == 'ذكر' ? 'محمد' : 'سارة');
                            return _customGreetingController.text.replaceAll('{user}', userTitle).replaceAll('{sec}', secTitle).replaceAll('{name}', name);
                          }(),
                          style: const TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 👇 وضع النداء الدائم (مقفول للبرو)
          const SizedBox(height: 12),
          if (widget.isProUser)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.mic_external_on, color: Color(0xFF1B2A4A), size: 26),
                      SizedBox(width: 10),
                      Text('وضع النداء الدائم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _wakeWordMode,
                      decoration: const InputDecoration(labelText: 'حالة النداء', border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: 'off', child: Text('متوقف')),
                        DropdownMenuItem(value: 'app_open', child: Text('التطبيق مفتوح فقط')),
                        DropdownMenuItem(value: 'background', child: Text('التطبيق مفتوح + الخلفية')),
                        DropdownMenuItem(value: 'always', child: Text('دائماً (حتى لو التطبيق مقفول)')),
                      ],
                      onChanged: (val) => setState(() => _wakeWordMode = val ?? 'off'),
                    ),
                    if (_wakeWordMode != 'off') ...[
                      const Divider(height: 30),
                      const Text('إيه اللي يخلي السكرتير يستمع؟', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _wakeWordTrigger,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        items: [
                          DropdownMenuItem(value: 'both', child: Text('الاسم + كلمة السر')),
                          DropdownMenuItem(value: 'name_only', child: Text('اسم السكرتير فقط')),
                          DropdownMenuItem(value: 'custom_only', child: Text('كلمة السر فقط')),
                        ],
                        onChanged: (val) => setState(() => _wakeWordTrigger = val ?? 'both'),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _wakeWordController,
                        enabled: _wakeWordTrigger != 'name_only',
                        decoration: InputDecoration(
                          labelText: 'كلمة السر',
                          hintText: 'مثال: يا بطل، يا سكرتير',
                          border: const OutlineInputBorder(),
                          fillColor: _wakeWordTrigger == 'name_only' ? Colors.grey.shade200 : null,
                          filled: _wakeWordTrigger == 'name_only',
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            )
          else
            Card(
              elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.mic_external_on, color: Colors.grey, size: 26),
                title: const Text('النداء الدائم (يا سكرتير)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                subtitle: const Text('متاح في النسخة البرو 👑', style: TextStyle(color: Color(0xFFC5A059), fontSize: 12)),
                trailing: const Icon(Icons.lock, color: Color(0xFFC5A059)),
                onTap: widget.onUpgrade,
              ),
            ),
            
          const SizedBox(height: 30),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasChanges ? const Color(0xFF1B2A4A) : Colors.grey,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(Icons.save, color: _hasChanges ? const Color(0xFFC5A059) : Colors.white70),
            label: Text(
              _hasChanges ? 'حفظ الإعدادات' : 'لا توجد تغييرات',
              style: TextStyle(color: _hasChanges ? Colors.white : Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: _hasChanges ? _save : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.undo, color: Colors.white, size: 18),
                  label: const Text('تراجع', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    setState(() {
                      _defaultReminderHour = _origDefaultReminderHour;
                      _defaultReminderMinute = _origDefaultReminderMinute;
                      _voiceLevel = _origVoiceLevel;
                      _greetingEnabled = _origGreetingEnabled;
                      _adhanAlertEnabled = _origAdhanAlertEnabled;
                      _ttsVolume = _origTtsVolume;
                      _showAboveLockScreen = _origShowAboveLockScreen;
                      _shakeMode = _origShakeMode;
                      _muteBeep = _origMuteBeep;
                      _voiceGender = _origVoiceGender;
                      _defaultInterval = _origDefaultInterval;
                      _secretaryName = _origSecretaryName;
                      _nameController.text = _origSecretaryName;
                      _wakeWordMode = _origWakeWordMode;
                      _wakeWordTrigger = _origWakeWordTrigger;
                      _wakeWordController.text = widget.settings.customWakeWord;
                      _useOverlayAlarm = _origUseOverlayAlarm;
                      _isKidsMode = _origIsKidsMode;
                      _customGreetingController.text = _origCustomGreeting;
                      _tahajjudAlertEnabled = _origTahajjudAlertEnabled;
                      _isDarkMode = _origIsDarkMode;
                      _customImagePath = _origCustomImagePath;
                      _defaultAlarmSound = _origDefaultAlarmSound;
                      _defaultWeeklySound = _origDefaultWeeklySound;
                      _defaultEventSound = _origDefaultEventSound;
                      _stopRecordMode = _origStopRecordMode;
                      _userTitleController.text = widget.settings.customUserTitle;
                      _secTitleController.text = widget.settings.customSecTitle;
                      _snoozeMinutes = _origSnoozeMinutes;
                      _diaryLockEnabled = _origDiaryLockEnabled;
                      _diaryPin = _origDiaryPin;
                      _diarySecurityQuestion = _origDiarySecurityQuestion;
                      _diarySecurityAnswer = _origDiarySecurityAnswer;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.restore, color: Colors.white, size: 18),
                  label: const Text('استعادة الافتراضي', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    _restoreClickCount++;
                    _restoreTimer?.cancel();

                    if (_restoreClickCount >= 5) {
                      _restoreClickCount = 0;
                      setState(() {
                        _diaryLockEnabled = false;
                        _diaryPin = '';
                        _diarySecurityQuestion = '';
                        _diarySecurityAnswer = '';
                      });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('diary_lock_enabled', false);
                      await prefs.setString('diary_pin', '');
                      await prefs.setString('diary_sec_q', '');
                      await prefs.setString('diary_sec_a', '');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم إلغاء قفل اليوميات فقط (الإعدادات الأخرى لم تتأثر)'), backgroundColor: Colors.orange),
                        );
                      }
                      return;
                    }

                    _restoreTimer = Timer(const Duration(seconds: 2), () async {
                      if (_restoreClickCount == 1) {
                        final bool keepLock = _diaryLockEnabled;
                        final String keepPin = _diaryPin;
                        final String keepQ = _diarySecurityQuestion;
                        final String keepA = _diarySecurityAnswer;

                        setState(() {
                          _defaultReminderHour = 18;
                          _defaultReminderMinute = 0;
                          _voiceLevel = 'متوسط';
                          _greetingEnabled = true;
                          _adhanAlertEnabled = true;
                          _showAboveLockScreen = false;
                          _shakeMode = 'app_open';
                          _muteBeep = true;
                          _voiceGender = 'ذكر';
                          _defaultInterval = 'كل 10 ثواني';
                          _secretaryName = 'محمد';
                          _nameController.text = 'محمد';
                          _wakeWordMode = 'off';
                          _wakeWordTrigger = 'both';
                          _wakeWordController.text = 'يا سكرتير';
                          _isKidsMode = false;
                          _tahajjudAlertEnabled = false;
                          _isDarkMode = false;
                          _useOverlayAlarm = false;
                          _ttsVolume = 1.0;
                          _customImagePath = null;
                          _defaultAlarmSound = null;
                          _defaultWeeklySound = null;
                          _defaultEventSound = null;
                          _customGreetingController.text = 'أَهْلاً بِكَ {user}. أَنَا {sec} {name}، هُزَّ الهَاتِفَ فِي أَيِّ وَقْتٍ لِأَكُونَ فِي خِدْمَتِكَ.';
                          _userTitleController.clear();
                          _secTitleController.clear();
                          _stopRecordMode = 'manual_only';
                          _snoozeMinutes = 5;
                          
                          _diaryLockEnabled = keepLock;
                          _diaryPin = keepPin;
                          _diarySecurityQuestion = keepQ;
                          _diarySecurityAnswer = keepA;
                        });

                        await widget.onSave(
                          18, 0, 'متوسط',
                          true, true, 1.0,
                          false, 'app_open', 'ذكر',
                          'كل 10 ثواني', 'يا سكرتير', 'off', 'both',
                          true, false,
                          false, 'أَهْلاً بِكَ {user}. أَنَا {sec} {name}، هُزَّ الهَاتِفَ فِي أَيِّ وَقْتٍ لِأَكُونَ فِي خِدْمَتِكَ.', false, false, null,
                          'manual_only',
                          5, keepLock, keepPin, keepQ, keepA,
                        );

                        await widget.onSaveSecretary('محمد', 'ذكر');

                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('default_alarm_sound');
                        await prefs.remove('default_weekly_sound');
                        await prefs.remove('default_event_sound');
                        await prefs.remove('custom_user_title');
                        await prefs.remove('custom_sec_title');
                        await prefs.setInt('snooze_minutes', 5);

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تمت استعادة الإعدادات الافتراضية بنجاح (ماعدا قفل اليوميات)'), backgroundColor: Colors.green),
                          );
                        }
                      }
                      _restoreClickCount = 0;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Future<Map<String, String>> _getDeviceInfo() async {
  final deviceInfo = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return {'id': androidInfo.id, 'name': '${androidInfo.manufacturer} ${androidInfo.model}'};
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return {'id': iosInfo.identifierForVendor ?? 'unknown', 'name': iosInfo.name};
    }
  } catch (_) {}
  return {'id': 'unknown_${DateTime.now().millisecondsSinceEpoch}', 'name': 'جهاز غير معروف'};
}

Future<void> _showManageDevicesDialog() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  
  final device = await _getDeviceInfo();
  final currentDeviceId = device['id']!;

  if (!mounted) return;
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('الأجهزة المتصلة'),
        content: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const CircularProgressIndicator();
            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final devices = Map<String, dynamic>.from(data['devices'] ?? {});
            
            if (devices.isEmpty) return const Text('لا توجد أجهزة مسجلة.');

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: devices.entries.map((e) {
                final isCurrent = e.key == currentDeviceId;
                return ListTile(
                  leading: Icon(Icons.smartphone, color: isCurrent ? Colors.green : Colors.grey),
                  title: Text(e.value.toString(), style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  subtitle: isCurrent ? const Text('هذا الجهاز', style: TextStyle(color: Colors.green, fontSize: 12)) : null,
                  trailing: isCurrent ? null : IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                        'devices.${e.key}': FieldValue.delete()
                      });
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      );
    },
  );
}
}

// ══════════════════════════════════════════════════════
// SecretaryApp + Splash + AnimatedDots
// ══════════════════════════════════════════════════════

class SecretaryApp extends StatefulWidget {
  final bool isFirstTime;
  final String? savedName;
  final bool? savedIsUserMale;

  const SecretaryApp({super.key, required this.isFirstTime, this.savedName, this.savedIsUserMale});

  @override
  State<SecretaryApp> createState() => _SecretaryAppState();
}

class _SecretaryAppState extends State<SecretaryApp> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
        });
      }
    });
  }

  void _toggleDarkMode(bool value) {
    setState(() {
      _isDarkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget homeScreen;
    if (widget.isFirstTime) {
      homeScreen = const TermsAndPermissionsScreen();
    } else {
      homeScreen = MainDashboard(
        secretaryName: widget.savedName ?? 'محمد',
        isUserMale: widget.savedIsUserMale ?? true,
        onThemeChanged: _toggleDarkMode,
      );
    }
    return MaterialApp(
      title: 'سكرتيري',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'SA')],
      locale: const Locale('ar', 'SA'),
      theme: ThemeData(
        primaryColor: const Color(0xFF1B2A4A),
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        fontFamily: 'Roboto',
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primaryColor: const Color(0xFF1B2A4A),
        scaffoldBackgroundColor: const Color(0xFF121212),
        fontFamily: 'Roboto',
        useMaterial3: true,
        brightness: Brightness.dark,
        cardColor: const Color(0xFF1E1E1E),
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: SplashScreen(nextScreen: homeScreen),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;
  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => widget.nextScreen),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B2A4A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/splash.png',
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => const SizedBox.shrink(),
          ),
          const Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(child: AnimatedDots()),
          ),
        ],
      ),
    );
  }
}

class AnimatedDots extends StatefulWidget {
  const AnimatedDots({super.key});

  @override
  State<AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<AnimatedDots> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) controller.repeat(reverse: true);
      });
      return controller;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _controllers[i],
          builder: (context, child) {
            final size = 10.0 + (_controllers[i].value * 8);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: size,
              height: size,
              decoration: const BoxDecoration(
                color: Color(0xFFC5A059),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}

class TermsAndPermissionsScreen extends StatefulWidget {
  const TermsAndPermissionsScreen({super.key});
  @override
  State<TermsAndPermissionsScreen> createState() => _TermsAndPermissionsScreenState();
}

class _TermsAndPermissionsScreenState extends State<TermsAndPermissionsScreen> {
  bool _agreed = false;
  bool _isRequesting = false;

  Future<void> _requestPermissions() async {
    setState(() => _isRequesting = true);

    await Permission.microphone.request();
    await Future.delayed(const Duration(milliseconds: 500));

    await Permission.notification.request();
    await Future.delayed(const Duration(milliseconds: 500));

    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
      await Future.delayed(const Duration(seconds: 1));
    }

    if (await Permission.systemAlertWindow.isDenied) {
      await Permission.systemAlertWindow.request();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    final micGranted = await Permission.microphone.isGranted;
    final batteryGranted = await Permission.ignoreBatteryOptimizations.isGranted;
    final overlayGranted = await Permission.systemAlertWindow.isGranted;

    if (mounted) setState(() => _isRequesting = false);

    if (!micGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ محتاج إذن المايكروفون'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (!batteryGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ محتاج تسمح للتطبيق يشتغل في الخلفية'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (!overlayGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ محتاج تفعّل "العرض فوق التطبيقات" عشان المنبه يشتغل صح'), backgroundColor: Colors.orange),
        );
      }
    }

    await _askFullScreenIntent();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SetupSecretaryScreen()),
      );
    }
  }

  Future<void> _askFullScreenIntent() async {
    try {
      final isAllowed = await _settingsChannel.invokeMethod('isFullScreenIntentAllowed');
      if (isAllowed == true) return;

      if (!mounted) return;
      final userAgreed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(children: [
            Icon(Icons.fullscreen, color: Color(0xFF1B2A4A), size: 28),
            SizedBox(width: 10),
            Text('إشعارات ملء الشاشة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          content: const Text(
            'عشان المنبه يشتغل والتابلت مقفول، محتاج تفعّل "إشعارات ملء الشاشة".\n\n'
            'اضغط "الإعدادات" وبعدين فعّل الخيار.',
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('الإعدادات', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (userAgreed == true) {
        await _settingsChannel.invokeMethod('openFullScreenIntentSettings');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اتفاقية الاستخدام والأذونات', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B2A4A),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Icon(Icons.verified_user_sharp, size: 80, color: Color(0xFF1B2A4A)),
            const SizedBox(height: 15),
            const Text('مرحباً بك في نظام سكرتيري',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
            const SizedBox(height: 15),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                ),
                child: const SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('يتطلب تشغيل سكرتيري الأذونات التالية:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      Text('• المايكروفون: للاستجابة عند الهز أو المناداة باسم السكرتير.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 5),
                      Text('• التنبيهات والإشعارات: لإطلاق المنبه الصوتي والتذكير المسبق بالمناسبات.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 5),
                      Text('• مستشعرات الحركة: للتعرف على هز الجهاز وتفعيل المساعد مباشرة.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 5),
                      Text('• المنبهات الدقيقة: لضبط مواقيت الأذان بدقة.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 5),
                      Text('• تجاهل تحسين البطارية: ليعمل التطبيق في الخلفية بدون توقف.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 5),
                      Text('• العرض فوق التطبيقات: لضمان عمل المنبهات بكفاءة.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 5),
                      Text('• إشعارات ملء الشاشة: لظهور التنبيهات والتابلت مقفول.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 15),
                      Text('جميع البيانات محفوظة بأمان محلياً على جهازك.',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(value: _agreed, activeColor: const Color(0xFF1B2A4A), onChanged: (v) => setState(() => _agreed = v ?? false)),
                const Expanded(child: Text('أوافق على الشروط والأذونات المطلوبة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B2A4A),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_agreed && !_isRequesting) ? _requestPermissions : null,
              child: _isRequesting
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : const Text('متابعة وإعطاء الأذونات', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}

class SetupSecretaryScreen extends StatefulWidget {
  const SetupSecretaryScreen({super.key});
  @override
  State<SetupSecretaryScreen> createState() => _SetupSecretaryScreenState();
}

class _SetupSecretaryScreenState extends State<SetupSecretaryScreen> {
  String _userGender = 'male';
  String _voiceGender = 'ذكر';
  final TextEditingController _nameController = TextEditingController(text: 'محمد');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim().isEmpty
        ? (_voiceGender == 'ذكر' ? 'محمد' : 'سارة')
        : _nameController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_time', false);
    await prefs.setString('secretary_name', name);
    await prefs.setBool('is_user_male', _userGender == 'male');
    await prefs.setString('voice_gender', _voiceGender);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainDashboard(secretaryName: name, isUserMale: _userGender == 'male', onThemeChanged: (v) {}),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = _getNamesForGender(_voiceGender);
    final secTitle = _voiceGender == 'ذكر' ? 'السكرتير' : 'السكرتيرة';

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعداد السكرتير الشخصي'),
        backgroundColor: const Color(0xFF1B2A4A),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 150, height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFC5A059), width: 4),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
                  image: DecorationImage(
                    image: AssetImage(_getSecretaryImage(_nameController.text, _voiceGender)),
                    fit: BoxFit.cover, alignment: Alignment.topCenter,
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Text('صوت $secTitle ($_voiceGender)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('تحديد نوع السكرتير:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('ذكر', style: TextStyle(fontSize: 14)),
                      value: 'ذكر',
                      groupValue: _voiceGender,
                      onChanged: (v) {
                        setState(() {
                          _voiceGender = v ?? 'ذكر';
                          final newNames = _getNamesForGender(_voiceGender);
                          if (!newNames.contains(_nameController.text)) {
                            _nameController.text = _voiceGender == 'ذكر' ? 'محمد' : 'سارة';
                          }
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('أنثى', style: TextStyle(fontSize: 14)),
                      value: 'أنثى',
                      groupValue: _voiceGender,
                      onChanged: (v) {
                        setState(() {
                          _voiceGender = v ?? 'أنثى';
                          final newNames = _getNamesForGender(_voiceGender);
                          if (!newNames.contains(_nameController.text)) {
                            _nameController.text = _voiceGender == 'ذكر' ? 'محمد' : 'سارة';
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('نوعك (صاحب الهاتف):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('ذكر (يا فندم)', style: TextStyle(fontSize: 13)),
                      value: 'male',
                      groupValue: _userGender,
                      onChanged: (v) => setState(() => _userGender = v ?? 'male'),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('أنثى (يا أستاذة)', style: TextStyle(fontSize: 13)),
                      value: 'female',
                      groupValue: _userGender,
                      onChanged: (v) => setState(() => _userGender = v ?? 'female'),
                    ),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 15),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('اختر أو أضف اسماً:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8.0, runSpacing: 8.0,
                children: names.map((name) {
                  final isSelected = _nameController.text == name;
                  return ActionChip(
                    label: Text(name),
                    backgroundColor: isSelected ? const Color(0xFFC5A059) : Colors.grey.shade200,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onPressed: () => setState(() => _nameController.text = name),
                  );
                }).toList(),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _nameController,
                onChanged: (v) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'اسم $secTitle',
                  prefixIcon: const Icon(Icons.badge, color: Color(0xFF1B2A4A)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B2A4A),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saveAndContinue,
                child: const Text('دخول لوحة التحكم', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// نهاية PART 2 / 8
// ══════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════
// PART 3 / 8
// SoundPickerDialog + MainDashboard (State + Fields + initState
// + Lifecycle + _initAll + PendingAlarm + PendingEvent
// + Adhan Scheduling + Speech Init + Shake + AdhanWatcher)
// ══════════════════════════════════════════════════════

class SoundPickerDialog extends StatefulWidget {
  final String? currentUri;
  final String voiceGender;
  final bool isProUser; // 👈 التعديل

  const SoundPickerDialog({super.key, this.currentUri, this.voiceGender = 'ذكر', this.isProUser = false}); // 👈 التعديل

  @override
  State<SoundPickerDialog> createState() => _SoundPickerDialogState();
}

class _SoundPickerDialogState extends State<SoundPickerDialog> {
  List<Map<String, String>> _sounds = [];
  String? _selected;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentUri ?? (widget.isProUser ? 'default' : 'system_alarm');
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    setState(() => _isLoading = true);
    try {
      final result = await _soundChannel.invokeMethod('getAvailableSounds');
      if (result is List) {
        setState(() {
          _sounds = result.map((e) => Map<String, String>.from(e as Map)).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _previewSound(String uri) async {
    if (uri == 'default') return;
    try {
      await _soundChannel.invokeMethod('previewSound', {'uri': uri});
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _soundChannel.invokeMethod('stopPreview');
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('🎵 اختر صوت المنبه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF1B2A4A)),
            onPressed: _loadSounds,
            tooltip: 'تحديث الأصوات',
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 450,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Scrollbar(
                thumbVisibility: true,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _soundTile(
  title: 'منبه الهاتف الافتراضي',
  uri: 'system_alarm',
),
const SizedBox(height: 5),
if (widget.isProUser)
  _soundTile(
    title: widget.voiceGender == 'ذكر'
        ? 'صوت السكرتير (برو)'
        : 'صوت السكرتيرة (برو)',
    uri: 'default',
  ),
                    const Divider(),
                    if (_sounds.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('لا توجد أصوات إضافية. جرب تدوس على زرار التحديث فوق.', textAlign: TextAlign.center),
                      ),
                    ..._sounds.map((s) => _soundTile(
                          title: s['title'] ?? '',
                          uri: s['uri'] ?? '',
                        )),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _soundTile({required String title, required String uri}) {
    final isSelected = _selected == uri;
    final isSecretaryVoice = uri == 'default';
final isSystemAlarm = uri == 'system_alarm';
final isCustomSound = uri.startsWith('raw://') || uri.contains('alarm_');
final isLocked = !widget.isProUser && (isSecretaryVoice || isCustomSound);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFC5A059).withOpacity(0.15) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? const Color(0xFFC5A059) : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Radio<String>(
          value: uri,
          groupValue: _selected,
          activeColor: const Color(0xFF1B2A4A),
          onChanged: isLocked ? null : (val) => setState(() => _selected = val),
        ),
        title: Text(title, style: TextStyle(fontSize: 12, color: isLocked ? Colors.grey : Colors.black87)),
        trailing: isLocked
            ? const Icon(Icons.lock, color: Color(0xFFC5A059), size: 20)
            : (uri == 'default'
                ? null
                : IconButton(
                    icon: const Icon(Icons.volume_up, color: Color(0xFF1B2A4A)),
                    onPressed: () => _previewSound(uri),
                  )),
        onTap: isLocked ? () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('هذا الصوت متاح في النسخة البرو 👑'), backgroundColor: Colors.orange)
          );
        } : null,
      ),
    );
  }
}

class MainDashboard extends StatefulWidget {
  final String secretaryName;
  final bool isUserMale;
  final Function(bool) onThemeChanged;

  const MainDashboard({
    super.key,
    required this.secretaryName,
    this.isUserMale = true,
    required this.onThemeChanged,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  FlutterTts get _tts => _appTts;

  final stt.SpeechToText _speech = stt.SpeechToText();

  final Random random = Random();

  bool _speechReady = false;
  bool _starting = false;
  bool _isListening = false;
  bool _isWakeWordListening = false;
  bool _isAlarmDialogOpen = false;
  bool _voiceDiaryAuthTemp = false;
  bool _isProUser = false;
  bool _isDeviceBlocked = false;
  String? _activeAlarmTitle;
  BuildContext? _alarmDialogContext;

  Timer? _activeAlarmLoopTimer;
  Timer? _alarmVoiceSafetyTimer;

  String? _activeAlarmTaskTitle;
  DateTime? _activeAlarmScheduledTime;
  String? _activeAlarmRepeat;
  String? _activeAlarmInterval;
  List<String> _activeAlarmCustomDays = [];
  String? _activeAlarmSoundUri;

  int _currentIndex = 0;
  DateTime _selectedDate = DateTime.now();
  DateTime _diaryDate = DateTime.now();
  DateTime? _lastShake;

  late String _secretaryName;
  late bool _isUserMale;

  bool _isInBackground = false;
  bool _ignoreNextWakeWordStart = false;
  int _tasbeehCount = 0;
  bool _isTasbeehMode = false;
  String _prayerSubView = 'times';

  int _wakeWordFailCount = 0;
  bool _showOnlyRecurring = false;

  bool _isHijriView = false;
  bool _isAdhkarMode = false;
  Map<String, int> _adhkarCounts = {};

  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _specialEvents = [];

  Map<String, dynamic> _diaries = {};

  AppSettings _settings = AppSettings();

  List<Map<String, dynamic>> _weeklySchedule = [];
  String _calendarSubView = 'calendar';

  final Set<Timer> _activeTimers = {};
  StreamSubscription? _accelerometerSub;
  Timer? _adhanTimer;

  Timer? _eventRepeatTimer;
  bool _eventAnnouncing = false;
  bool _eventDialogShowing = false;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  List<Map<String, dynamic>> _recordings = [];
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _currentlyPlayingPath;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  double _playbackVolume = 1.0;
  double _playbackSpeed = 1.0;
  double _ttsVolume = 1.0;

  String? _pendingVoiceAction;
  String? _pendingRawCommand;
  Timer? _pendingActionTimer;
  Map<String, dynamic>? _pendingConflictTaskData;
  int? _pendingConflictTaskIndex;
  BuildContext? _conflictDialogContext;
  Map<String, int> _tasbeehSubCounts = {};
  Map<String, dynamic>? _pendingEventData;

  static const List<Map<String, String>> _tasbeehItems = [
    {'key': 'subhan', 'text': 'سبحان الله'},
    {'key': 'subhan_bihamdih', 'text': 'سبحان الله وبحمده'},
    {'key': 'subhan_bihamdih_azim', 'text': 'سبحان الله وبحمده سبحان الله العظيم'},
    {'key': 'subhan_adada', 'text': 'سبحان الله وبحمده عدد خلقه ورضا نفسه وزنة عرشه ومداد كلماته'},
    {'key': 'subhan_azim', 'text': 'سبحان الله العظيم'},
    {'key': 'astaghfirullah', 'text': 'أستغفر الله'},
    {'key': 'salah_ala_nabi', 'text': 'اللهم صل على سيدنا محمد'},
    {'key': 'alhamdulillah', 'text': 'الحمد لله'},
    {'key': 'allahu_akbar', 'text': 'الله أكبر'},
    {'key': 'la_ilaha_illallah', 'text': 'لا إله إلا الله'},
  ];

  static const List<Map<String, dynamic>> _morningAdhkarList = [
    {'text': 'أصْبَحْنَا وَأَصْبَحَ المُلْكُ لِلَّهِ، والحَمْدُ لِلَّهِ، لا إلهَ إِلاَّ اللَّهُ وَحْدَهُ لا شَرِيكَ لَهُ، لَهُ المُلْكُ وَلَهُ الحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ.', 'count': 1},
    {'text': 'اللَّهُمَّ بِكَ أَصْبَحْنَا، وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ النُّشُورُ.', 'count': 1},
    {'text': 'اللَّهُمَّ أَنْتَ رَبِّي لا إلهَ إِلاَّ أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي فَإِنَّهُ لا يَغْفِرُ الذُّنُوبَ إِلاَّ أَنْتَ.', 'count': 1},
    {'text': 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ', 'count': 100},
  ];

  static const List<Map<String, dynamic>> _eveningAdhkarList = [
    {'text': 'أَمْسَيْنَا وَأَمْسَى المُلْكُ لِلَّهِ، والحَمْدُ لِلَّهِ، لا إلهَ إِلاَّ اللَّهُ وَحْدَهُ لا شَرِيكَ لَهُ، لَهُ المُلْكُ وَلَهُ الحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ.', 'count': 1},
    {'text': 'اللَّهُمَّ بِكَ أَمْسَيْنَا، وَبِكَ أَصْبَحْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ المَصِيرُ.', 'count': 1},
    {'text': 'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ', 'count': 3},
    {'text': 'بِسْمِ اللَّهِ الَّذِي لا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الأَرْضِ وَلا فِي السَّمَاءِ وَهُوَ السَّمِيعُ العَلِيمُ', 'count': 3},
  ];

  static const List<Map<String, dynamic>> _sleepAdhkarList = [
    {'text': 'بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا', 'count': 1},
    {'text': 'اللَّهُمَّ قِنِي عَذَابَكَ يَوْمَ تَبْعَثُ عِبَادَكَ', 'count': 3},
    {'text': 'سُبْحَانَ اللَّهِ', 'count': 33},
    {'text': 'الحَمْدُ لِلَّهِ', 'count': 33},
    {'text': 'اللَّهُ أَكْبَرُ', 'count': 34},
  ];

  static const Map<String, List<String>> _dayKeywords = {
    'السبت': ['السبت', 'سبت', 'يوم السبت', 'السبت الجاي', 'السبت الجاى'],
    'الأحد': ['الاحد', 'الأحد', 'الحد', 'حد', 'يوم الاحد', 'يوم الحد'],
    'الاثنين': ['الاتنين', 'الاثنين', 'اتنين', 'يوم الاتنين', 'يوم الاتنين'],
    'الثلاثاء': ['التلات', 'الثلاثاء', 'التلات', 'تلات', 'يوم التلات', 'يوم الثلاثاء'],
    'الأربعاء': ['الاربع', 'الأربعاء', 'الاربع', 'اربع', 'يوم الاربع', 'يوم الأربعاء'],
    'الخميس': ['الخميس', 'خميس', 'يوم الخميس'],
    'الجمعة': ['الجمعه', 'الجمعة', 'جمعه', 'جمعة', 'يوم الجمعه', 'يوم الجمعة'],
  };

  String get _userTitle => _settings.customUserTitle.trim().isNotEmpty ? _settings.customUserTitle.trim() : (_isUserMale ? "يا فندم" : "يا أستاذة");
  String get _secTitle => _settings.customSecTitle.trim().isNotEmpty ? _settings.customSecTitle.trim() : (_settings.voiceGender == 'ذكر' ? 'السكرتير' : 'السكرتيرة');
  String get _secWord => _settings.customSecTitle.trim().isNotEmpty ? _settings.customSecTitle.trim() : (_settings.voiceGender == 'ذكر' ? 'سكرتيرك' : 'سكرتيرتك');
  String get _pronoun => _isUserMale ? "وانت" : "وانتي";
  String get _takeCareWord => _isUserMale ? "خد" : "خدي";
  String get _readyWord => _settings.voiceGender == 'ذكر' ? "جاهز" : "جاهزة";
  String get _happyWord => _settings.voiceGender == 'ذكر' ? "مبسوط" : "مبسوطة";
  String get _listenWord => _settings.voiceGender == 'ذكر' ? "سامعك" : "سامعاك";
  String get _withYou => _isUserMale ? "معاك" : "معاكي";
  String get _sayWord => _isUserMale ? "قول" : "قولي";
  String get _dontForget => _isUserMale ? "متنساش" : "متتنسيش";
  String get _studyWord => _isUserMale ? "ذاكر" : "ذاكري";
  String get _youWant => _isUserMale ? "لو حابب" : "لو حابة";
  String get _youTalk => _isUserMale ? "تتكلم" : "تتكلمي";
  String get _sleepWord => _isUserMale ? "وتنام" : "وتنامي";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _secretaryName = widget.secretaryName;
    _isUserMale = widget.isUserMale;
    _checkAccountStatus();

    _wakeWordChannel.setMethodCallHandler((call) async {
      if (call.method == 'onWakeWordDetected') {
        if (mounted) {
          setState(() => _isListening = false);
          _listenVoiceCommand();
        }
      } else if (call.method == 'onAlarmStoppedByVoice') {
        if (_isAlarmDialogOpen) {
          _activeAlarmLoopTimer?.cancel();
          _alarmVoiceSafetyTimer?.cancel();
          _tts.stop();
          WakelockPlus.disable();
          _isAlarmDialogOpen = false;
          if (_alarmDialogContext != null) {
            Navigator.of(_alarmDialogContext!).pop();
            _alarmDialogContext = null;
          }
        }
      } else if (call.method == 'onAlarmStoppedByNotification') {
        if (_isAlarmDialogOpen) {
          _activeAlarmLoopTimer?.cancel();
          _alarmVoiceSafetyTimer?.cancel();
          _alarmVoiceSafetyTimer = null;
          _tts.stop();
          try { _soundChannel.invokeMethod('stopPreview'); } catch (_) {}
          WakelockPlus.disable();
          _isAlarmDialogOpen = false;
          _activeAlarmTitle = null;
          if (_alarmDialogContext != null) {
            try { Navigator.of(_alarmDialogContext!).pop(); } catch (_) {}
            _alarmDialogContext = null;
          }
        }
        try { await _speech.cancel(); } catch (_) {}
        if (mounted) setState(() => _isListening = false);
        _isWakeWordListening = false;
        _ignoreNextWakeWordStart = true;
        Future.delayed(const Duration(seconds: 15), () {
          _ignoreNextWakeWordStart = false;
        });
        SharedPreferences.getInstance().then((prefs) {
          prefs.remove('pending_alarm');
        });
      }
    });

    _shakeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onShakeDetected') {
        if (!_isListening && !_starting && !_isRecording) {
          _listenVoiceCommand();
        }
      }
    });

    _notificationActionController.stream.listen((action) {
      if (action == 'cancel') {
        _ignoreNextWakeWordStart = true;
        Future.delayed(const Duration(seconds: 5), () {
          _ignoreNextWakeWordStart = false;
        });

        _activeAlarmLoopTimer?.cancel();
        _alarmVoiceSafetyTimer?.cancel();
        _tts.stop();
        try { _soundChannel.invokeMethod('stopPreview'); } catch (_) {}
        WakelockPlus.disable();
        _isAlarmDialogOpen = false;

        final stoppedTitle = _activeAlarmTitle;
        _activeAlarmTitle = null;

        if (_alarmDialogContext != null) {
          try { Navigator.of(_alarmDialogContext!).pop(); } catch (_) {}
          _alarmDialogContext = null;
        }

        _speech.stop();
        if (mounted) setState(() => _isListening = false);

        try { _wakeWordChannel.invokeMethod('stopWakeWord'); } catch (_) {}
        _isWakeWordListening = false;

        if (stoppedTitle != null) {
          final task = _tasks.firstWhere(
            (t) => t['task'] == stoppedTitle,
            orElse: () => {},
          );
          final alarmId = task['alarmId'] as int?;

          if (alarmId != null) {
            try { _notifications.cancel(alarmId); } catch (_) {}
            _cancelNativeAlarm(stoppedTitle, customId: alarmId);
          } else {
            try { _notifications.cancel(stoppedTitle.hashCode + 1000); } catch (_) {}
            _cancelNativeAlarm(stoppedTitle);
          }

          SharedPreferences.getInstance().then((prefs) => prefs.remove('pending_alarm'));
          final idx = _tasks.indexWhere((t) => t['task'] == stoppedTitle);
          if (idx != -1) {
            final task = _tasks[idx];
            if (task['repeat'] == 'مرة واحدة' || task['repeat'] == null) {
              setState(() => _tasks.removeAt(idx));
              _saveData();
            }
          }
        }
      }

      if (action == 'stop_recording') {
        if (_isRecording) _stopRecording();
        if (_DiaryPageState.activeInstance != null) _DiaryPageState.activeInstance!.stopRecordingByVoice();
      }
    });

    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        final isPending = await _wakeWordChannel.invokeMethod('isWakeWordPending');
        if (isPending == true && mounted) {
          _listenVoiceCommand();
        }
      } catch (_) {}
    });

    _initAll();
  }

  Future<Map<String, String>> _getDeviceInfo() async {
  final deviceInfo = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return {'id': androidInfo.id, 'name': '${androidInfo.manufacturer} ${androidInfo.model}'};
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return {'id': iosInfo.identifierForVendor ?? 'unknown', 'name': iosInfo.name};
    }
  } catch (_) {}
  return {'id': 'unknown_${DateTime.now().millisecondsSinceEpoch}', 'name': 'جهاز غير معروف'};
}

Future<bool> _verifyDeviceLimit() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return true;

  final device = await _getDeviceInfo();
  final deviceId = device['id']!;
  final deviceName = device['name']!;

  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

  try {
    final doc = await userRef.get();
    final Map<String, dynamic> devices = Map<String, dynamic>.from(doc.data()?['devices'] ?? {});

    if (devices.containsKey(deviceId)) {
      if (devices[deviceId] != deviceName) {
        await userRef.update({'devices.$deviceId': deviceName});
      }
      return true;
    }

    if (devices.length >= 3) { // 👈 الحد الأقصى 3 أجهزة
      return false;
    }

    await userRef.update({'devices.$deviceId': deviceName});
    return true;
  } catch (e) {
    return true;
  }
}

Future<void> _checkAccountStatus() async {
  final allowed = await _verifyDeviceLimit();
  if (!allowed && mounted) {
    setState(() => _isDeviceBlocked = true);
    return;
  }
  if (mounted) setState(() => _isDeviceBlocked = false);
  await _checkProStatus();
}

Future<void> _showManageDevicesDialog(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  
  final device = await _getDeviceInfo();
  final currentDeviceId = device['id']!;

  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('الأجهزة المتصلة'),
        content: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const CircularProgressIndicator();
            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final devices = Map<String, dynamic>.from(data['devices'] ?? {});
            
            if (devices.isEmpty) return const Text('لا توجد أجهزة مسجلة.');

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: devices.entries.map((e) {
                final isCurrent = e.key == currentDeviceId;
                return ListTile(
                  leading: Icon(Icons.devices, color: isCurrent ? Colors.green : Colors.grey),
                  title: Text(e.value.toString(), style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  subtitle: isCurrent ? const Text('هذا الجهاز', style: TextStyle(color: Colors.green, fontSize: 12)) : null,
                  trailing: isCurrent ? null : IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                        'devices.${e.key}': FieldValue.delete()
                      });
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          if (_isDeviceBlocked)
            ElevatedButton(
              onPressed: () async {
                final allowed = await _verifyDeviceLimit();
                if (allowed) {
                  Navigator.pop(ctx);
                  _checkAccountStatus();
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('لا يزال الحد الأقصى ممتلئاً!')));
                }
              },
              child: const Text('تحديث والمتابعة'),
            )
        ],
      );
    },
  );
}
  
  Future<void> _checkProStatus() async {
    const storage = FlutterSecureStorage();
    final localIsPro = await storage.read(key: 'is_pro_user');
    if (localIsPro == 'true') {
      if (mounted) setState(() => _isProUser = true);
    }
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get().timeout(const Duration(seconds: 3));
        if (doc.exists && doc.get('isPro') == true) {
          await storage.write(key: 'is_pro_user', value: 'true');
          if (mounted) setState(() => _isProUser = true);
        }
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('wake_word_paused_by_alarm');
      });
      Future.delayed(const Duration(milliseconds: 500), _checkPendingAlarm);
      Future.delayed(const Duration(seconds: 2), _checkPendingEventAnnouncements);
      Future.delayed(const Duration(seconds: 1), () => _checkAdhanTime(forceCheck: true));

      if (_settings.wakeWordMode == 'app_open' ||
          _settings.wakeWordMode == 'background' ||
          _settings.wakeWordMode == 'always') {
        Future.delayed(const Duration(seconds: 1), () {
          if (!_isListening && !_ignoreNextWakeWordStart) _startWakeWordLoop();
        });
      }

      if (_settings.wakeWordMode != 'off' && !_ignoreNextWakeWordStart) {
        try { _wakeWordChannel.invokeMethod('startWakeWord'); } catch (_) {}
      }

    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _isInBackground = true;
      if (_isWakeWordListening) {
        _speech.stop();
        _isWakeWordListening = false;
      }

      if (_settings.wakeWordMode == 'app_open') {
        try { _wakeWordChannel.invokeMethod('stopWakeWord'); } catch (_) {}
      }
    }
  }

  Future<void> _initAll() async {
    try {
      await _loadData();
      await _loadRecordings();
      await _configureVoice();
      _initSpeech();
      _initShakeDetector();
      _startAdhanWatcher();

      Future.delayed(const Duration(seconds: 1), () {
        try { _scheduleAdhan30Days(); } catch (_) {}
      });

      Future.delayed(const Duration(seconds: 3), () { try { _checkPendingEventAnnouncements(); } catch (_) {} });
      Future.delayed(const Duration(seconds: 2), () { try { _checkPendingAlarm(); } catch (_) {} });

      Future.delayed(const Duration(seconds: 3), () {
        if (_settings.wakeWordMode == 'app_open' ||
            _settings.wakeWordMode == 'background' ||
            _settings.wakeWordMode == 'always') {
          _startWakeWordLoop();
        }
      });

      _checkSmartSuggestions();

    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  Future<void> _checkSmartSuggestions() async {
    final lastDiary = _diaries.keys.isNotEmpty ? _diaries.keys.reduce((a, b) => a.compareTo(b) > 0 ? a : b) : null;
    if (lastDiary != null) {
      final lastDate = DateTime.tryParse(lastDiary);
      if (lastDate != null && DateTime.now().difference(lastDate).inDays >= 3) {
        await Future.delayed(const Duration(seconds: 4));
        if (mounted && !_isInBackground) {
          _speak("فات 3 أيام مش كتبت يومياتك $_userTitle، تحب تفتحها؟");
        }
      }
    }
  }

  Future<void> _checkPendingAlarm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingStr = prefs.getString('pending_alarm');
      if (pendingStr == null) return;
      if (_isAlarmDialogOpen) return;

      final data = json.decode(pendingStr) as Map<String, dynamic>;
      final scheduledMillis = data['scheduledMillis'] as int?;
      final title = data['title'] as String? ?? '';
      final repeat = data['repeat'] as String? ?? 'مرة واحدة';
      final interval = data['interval'] as String? ?? 'بدون تنبيه';
      final customDays = List<String>.from(data['customDays'] ?? []);
      final sound = data['sound'] as String?;

      if (scheduledMillis == null || title.isEmpty) {
        await prefs.remove('pending_alarm');
        return;
      }

      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      final diff = nowMillis - scheduledMillis;

      if (repeat == 'مرة واحدة') {
        if (diff > 5 * 60 * 1000) {
          await prefs.remove('pending_alarm');
          return;
        }
        if (diff < -60 * 1000) return;
      } else {
        if (diff > 5 * 60 * 1000) {
          await prefs.remove('pending_alarm');
          return;
        }
      }

      await prefs.remove('pending_alarm');
      if (mounted) {
        _startAlarmLoop(
          title,
          repeat,
          interval,
          customDays,
          DateTime.fromMillisecondsSinceEpoch(scheduledMillis),
          sound,
        );
      }
    } catch (_) {}
  }

  Future<void> _checkPendingEventAnnouncements() async {
    if (_eventDialogShowing) return;
    final prefs = await SharedPreferences.getInstance();
    final pendingStr = prefs.getString('pending_event_announce');
    if (pendingStr == null) return;

    try {
      final data = json.decode(pendingStr) as Map<String, dynamic>;
      final scheduledMillis = data['scheduledMillis'] as int?;
      if (scheduledMillis == null) {
        await prefs.remove('pending_event_announce');
        return;
      }

      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      final diff = nowMillis - scheduledMillis;

      if (diff < 0) return;
      if (diff > 10 * 60 * 1000) {
        await prefs.remove('pending_event_announce');
        return;
      }

      await prefs.remove('pending_event_announce');
      final title = data['title'] as String? ?? '';
      final detail = data['detail'] as String? ?? '';
      final interval = data['interval'] as String? ?? 'مرة واحدة';
      final hasCustomSound = data['hasCustomSound'] as bool? ?? false;

      if (title.isNotEmpty && mounted) {
        _showEventReminder(title, detail, interval, hasCustomSound: hasCustomSound);
      }
    } catch (_) {}
  }

  String _prayerKey(String arabicName) {
    switch (arabicName) {
      case 'الفجر': return 'fajr';
      case 'الظهر': return 'dhuhr';
      case 'العصر': return 'asr';
      case 'المغرب': return 'maghrib';
      case 'العشاء': return 'isha';
      default: return '';
    }
  }

  Future<void> _scheduleAdhan30Days() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('adhan_schedule_start_date', DateTime.now().toIso8601String());

      for (int i = 1; i <= 500; i++) {
        try { await _notifications.cancel(i); } catch (_) {}
      }
      for (int i = 5000; i <= 5500; i++) {
        try { await _notifications.cancel(i); } catch (_) {}
      }

      final prayerIds = {'fajr': 1, 'dhuhr': 2, 'asr': 3, 'maghrib': 4, 'isha': 5};
      final prayers = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
      final names = {
        'fajr': 'الفجر', 'dhuhr': 'الظهر', 'asr': 'العصر',
        'maghrib': 'المغرب', 'isha': 'العشاء',
      };
      final sounds = {
        'fajr': 'adhan_fajr', 'dhuhr': 'adhan_dhuhr', 'asr': 'adhan_asr',
        'maghrib': 'adhan_maghrib', 'isha': 'adhan_isha',
      };

      final now = DateTime.now();

      for (int day = 0; day < 30; day++) {
        final targetDate = now.add(Duration(days: day));
        final coordinates = Coordinates(30.0444, 31.2357);
        final date = DateComponents.from(targetDate);
        final params = CalculationMethod.egyptian.getParameters();
        params.madhab = Madhab.shafi;
        final prayerTimes = PrayerTimes(coordinates, date, params);

        final Map<String, DateTime> dayPrayers = {
          'fajr': prayerTimes.fajr, 'dhuhr': prayerTimes.dhuhr,
          'asr': prayerTimes.asr, 'maghrib': prayerTimes.maghrib, 'isha': prayerTimes.isha,
        };

        for (final prayer in prayers) {
          final prayerTime = dayPrayers[prayer]!;
          if (prayerTime.isBefore(now)) continue;

          final channelId = 'adhan_channel_${prayer}_v2'; // 👈 v2
          final channelName = 'تنبيهات الأذان ${names[prayer]}';

          final androidDetails = AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: 'تنبيهات مواقيت الصلاة',
            importance: Importance.high, // 👈 التعديل
            priority: Priority.high, // 👈 التعديل
            playSound: true,
            sound: RawResourceAndroidNotificationSound(sounds[prayer]),
            enableVibration: true,
            category: AndroidNotificationCategory.alarm,
            autoCancel: true, // 👈 التعديل
            ongoing: false, // 👈 التعديل
            fullScreenIntent: false, // 👈 التعديل (عشان ميفتحش التطبيق لوحده)
            visibility: NotificationVisibility.public,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          );

          await _notifications.zonedSchedule(
            5000 + (day * 10) + prayerIds[prayer]!,
            'حان الآن موعد صلاة ${names[prayer]}',
            'موعد صلاة ${names[prayer]}',
            tz.TZDateTime.from(prayerTime.toLocal(), tz.local),
            NotificationDetails(android: androidDetails),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _scheduleSalatAlaNabi() async {
    for (int i = 8000; i <= 8500; i++) {
      try { await _notifications.cancel(i); } catch (_) {}
    }

    if (!_settings.salatAlaNabiEnabled) return;

    int intervalHours = 1;
    if (_settings.salatAlaNabiInterval == 'كل ساعتين') intervalHours = 2;
    if (_settings.salatAlaNabiInterval == 'كل 3 ساعات') intervalHours = 3;
    if (_settings.salatAlaNabiInterval == 'كل 4 ساعات') intervalHours = 4;
    if (_settings.salatAlaNabiInterval == 'كل 6 ساعات') intervalHours = 6;

    final now = DateTime.now();
    int notificationId = 8000;
    int count = 0;

    const int maxNotifications = 480;
    const int totalHoursToSchedule = 30 * 24;

    for (int i = 1; i <= totalHoursToSchedule; i++) {
      if (i % intervalHours != 0) continue;

      final scheduledTime = now.add(Duration(hours: i));

      final androidDetails = AndroidNotificationDetails(
        'salat_ala_nabi_channel_v2', // 👈 v2
        'تذكير الصلاة على النبي',
        channelDescription: 'تنبيهات تذكير الصلاة على النبي',
        importance: Importance.high, // 👈 التعديل
        priority: Priority.high, // 👈 التعديل
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('salat_ala_nabi'),
        enableVibration: true,
        category: AndroidNotificationCategory.reminder,
        fullScreenIntent: false, // 👈 التعديل
      );

      try {
        await _notifications.zonedSchedule(
          notificationId,
          'تذكير الصلاة على النبي',
          'قال رسول الله ﷺ: من صلى عليَّ صلاةً صلى الله عليه بها عشرًا',
          tz.TZDateTime.from(scheduledTime, tz.local),
          NotificationDetails(android: androidDetails),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
        notificationId++;
        count++;
      } catch (_) {}

      if (count >= maxNotifications) break;
    }
  }

  Future<void> _initSpeech() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            if (_isListening) {
              setState(() => _isListening = false);
              if (_settings.wakeWordMode != 'off') {
                try { _wakeWordChannel.invokeMethod('resumeWakeWord'); } catch (_) {}
              }
            }
            if (_isWakeWordListening) _isWakeWordListening = false;

            if (_isTasbeehMode) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && _isTasbeehMode && !_isListening) _listenVoiceCommand();
              });
            }
            if (_isAdhkarMode) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && _isAdhkarMode && !_isListening) _listenVoiceCommand();
              });
            }
            if (_isAlarmDialogOpen) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted && _isAlarmDialogOpen && !_isListening && !_isRecording) _listenVoiceCommand();
              });
            }
          }
        },
        onError: (error) {
          if (mounted) {
            final errorStr = error.toString().toLowerCase();
            if ((errorStr.contains('network') || errorStr.contains('internet') || errorStr.contains('no_internet'))
                && _pendingVoiceAction == 'confirm_time_conflict') {
              _speak("معلش $_userTitle، يبدو أن هناك مشكلة في الاتصال بالإنترنت. من فضلك استخدم الأزرار اللي على الشاشة.");
              return;
            }

            if (_isListening) {
              setState(() => _isListening = false);
              if (_settings.wakeWordMode != 'off') {
                try { _wakeWordChannel.invokeMethod('resumeWakeWord'); } catch (_) {}
              }
            }
            if (_isWakeWordListening) _isWakeWordListening = false;

            if (_isTasbeehMode) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && _isTasbeehMode && !_isListening) _listenVoiceCommand();
              });
            }
            if (_isAdhkarMode) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && _isAdhkarMode && !_isListening) _listenVoiceCommand();
              });
            }
            if (_isAlarmDialogOpen) {
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted && _isAlarmDialogOpen && !_isListening && !_isRecording) _listenVoiceCommand();
              });
            }
          }
        },
      );
    } catch (_) {
      _speechReady = false;
    }
  }

  void _initShakeDetector() {
    _accelerometerSub?.cancel();

    if (_settings.shakeMode == 'always') {
      try { _shakeChannel.invokeMethod('startShakeService'); } catch (_) {}
      return;
    }

    try { _shakeChannel.invokeMethod('stopShakeService'); } catch (_) {}

    if (_settings.shakeMode == 'off') return;

    _accelerometerSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      double gX = event.x / 9.81;
      double gY = event.y / 9.81;
      double gZ = event.z / 9.81;
      double gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

      if (gForce > 2.2) {
        final now = DateTime.now();
        if (_lastShake != null && now.difference(_lastShake!) < const Duration(seconds: 3)) return;
        if (_isInBackground && _settings.shakeMode != 'background') return;
        _lastShake = now;

        final isDiaryRec = _DiaryPageState.activeInstance?._isRecordingNow ?? false;

        if (_isRecording || isDiaryRec) {
          if (_settings.stopRecordMode == 'shake_only') {
            if (_isRecording) _stopRecording();
            if (isDiaryRec) _DiaryPageState.activeInstance!.stopRecordingByVoice();
          }
        } else {
          if (!_isListening && !_starting) _listenVoiceCommand();
        }
      }
    });
  }

  void _startAdhanWatcher() {
    _adhanTimer?.cancel();
    _adhanTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _settings.adhanAlertEnabled) _checkAdhanTime();
    });
  }

  Future<void> _checkAdhanTime({bool forceCheck = false}) async {
    if (!_settings.adhanAlertEnabled) return;
    try {
      final times = await _calculatePrayerTimes();
      final now = DateTime.now();

      final Map<String, String> prayerMap = {
        'الفجر': times['fajr'] ?? '',
        'الظهر': times['dhuhr'] ?? '',
        'العصر': times['asr'] ?? '',
        'المغرب': times['maghrib'] ?? '',
        'العشاء': times['isha'] ?? '',
      };

      final prefs = await SharedPreferences.getInstance();
      final startDateStr = prefs.getString('adhan_schedule_start_date');
      int dayOffset = 0;
      if (startDateStr != null) {
        final startDate = DateTime.parse(startDateStr);
        dayOffset = now.difference(startDate).inDays;
      }

      final prayerIds = {'fajr': 1, 'dhuhr': 2, 'asr': 3, 'maghrib': 4, 'isha': 5};
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      for (final entry in prayerMap.entries) {
        try {
          final prayerTime = DateFormat('HH:mm').parse(entry.value);
          final prayerDateTime = DateTime(now.year, now.month, now.day, prayerTime.hour, prayerTime.minute);

          final diffSeconds = now.difference(prayerDateTime).inSeconds;
          final tolerance = forceCheck ? 300 : 90;
          final isValidTime = diffSeconds >= 0 && diffSeconds <= tolerance;

          final alertKey = 'adhan_alerted_${todayStr}_${entry.key}';
          final alreadyAlerted = prefs.getBool(alertKey) ?? false;

          if (isValidTime && !alreadyAlerted) {
            await prefs.setBool(alertKey, true);

            final key = _prayerKey(entry.key);
            if (key.isNotEmpty && dayOffset >= 0 && dayOffset < 30) {
              await _notifications.cancel(5000 + (dayOffset * 10) + prayerIds[key]!);
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

// ══════════════════════════════════════════════════════
// نهاية PART 3 / 8
// ══════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════
// PART 4 / 8
// Load/Save Data + Recordings + Voice Config + Speak
// + ListenVoiceCommand + WakeWordLoop + HandleSocialReply
// ══════════════════════════════════════════════════════

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    String? tasksString = prefs.getString('saved_tasks');
    if (tasksString != null) {
      setState(() {
        _tasks = List<Map<String, dynamic>>.from(json.decode(tasksString));
      });
      for (final t in _tasks) {
        if (t['alarm'] == true && t['scheduled'] != null) {
          final dt = DateTime.tryParse(t['scheduled'].toString());
          if (dt != null && dt.isAfter(DateTime.now())) {
            _scheduleContinuousAlarm(
              t['task'].toString(), dt,
              t['repeat'] ?? 'مرة واحدة',
              t['repeatInterval'] ?? 'كل 10 ثواني',
              List<String>.from(t['customDays'] ?? []),
              soundUri: t['sound'],
            );
          }
        }
      }
    }

    String? eventsString = prefs.getString('saved_events');
    if (eventsString != null) {
      setState(() {
        _specialEvents = List<Map<String, dynamic>>.from(json.decode(eventsString));
      });
      _sortByTime(_specialEvents);
      for (final e in _specialEvents) {
        _scheduleEventReminder(e);
      }
    } else {
      setState(() => _specialEvents = []);
    }

    String? diariesString = prefs.getString('saved_diaries');
    if (diariesString != null) {
      setState(() {
        _diaries = Map<String, dynamic>.from(json.decode(diariesString));
      });
    }
    String? adhkarString = prefs.getString('saved_adhkar_counts');
    if (adhkarString != null) {
      try {
        final decoded = json.decode(adhkarString) as Map<String, dynamic>;
        _adhkarCounts = decoded.map((k, v) => MapEntry(k, v as int));
      } catch (_) {}
    }

    String? weeklyString = prefs.getString('saved_weekly_schedule');
    if (weeklyString != null) {
      setState(() {
        _weeklySchedule = List<Map<String, dynamic>>.from(json.decode(weeklyString));
      });
      for (final t in _weeklySchedule) {
        if (t['repeatInterval'] != 'بدون تنبيه' && t['scheduled'] != null) {
          final dt = DateTime.tryParse(t['scheduled'].toString());
          if (dt != null && dt.isAfter(DateTime.now())) {
            _scheduleWeeklyAlarm(
              t['task'].toString(), t['day'].toString(), dt, t['repeatInterval'] ?? 'مرة واحدة',
              t['advanceReminder'] ?? 'في الموعد', soundUri: t['sound'],
            );
          }
        }
      }
    }

    _settings.defaultReminderHour = prefs.getInt('default_reminder_hour') ?? 18;
    _settings.defaultReminderMinute = prefs.getInt('default_reminder_minute') ?? 0;
    _settings.voiceLevel = prefs.getString('voice_level') ?? 'متوسط';
    _settings.greetingEnabled = prefs.getBool('greeting_enabled') ?? true;
    _settings.adhanAlertEnabled = prefs.getBool('adhan_alert_enabled') ?? true;
    _settings.showAboveLockScreen = prefs.getBool('show_above_lock_screen') ?? false;
    _settings.shakeMode = prefs.getString('shake_mode') ?? 'app_open';
    _settings.muteBeep = prefs.getBool('mute_beep') ?? true;
    _settings.voiceGender = prefs.getString('voice_gender') ?? 'ذكر';
    _settings.defaultInterval = prefs.getString('default_interval') ?? 'كل 10 ثواني';
    _settings.customWakeWord = prefs.getString('custom_wake_word') ?? 'يا سكرتير';
    _settings.wakeWordMode = prefs.getString('wake_word_mode') ?? 'off';
    _settings.wakeWordTrigger = prefs.getString('wake_word_trigger') ?? 'both';
    _settings.useOverlayAlarm = prefs.getBool('use_overlay_alarm') ?? false;
    _settings.isKidsMode = prefs.getBool('is_kids_mode') ?? false;
    _settings.customGreeting = prefs.getString('custom_greeting') ?? 'أَهْلاً بِكَ {user}. أَنَا {sec} {name}، هُزَّ الهَاتِفَ فِي أَيِّ وَقْتٍ لِأَكُونَ فِي خِدْمَتِكَ.';
    _settings.tahajjudAlertEnabled = prefs.getBool('tahajjud_alert_enabled') ?? false;
    _settings.isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    _settings.customImagePath = prefs.getString('custom_secretary_image');
    _settings.salatAlaNabiEnabled = prefs.getBool('salat_ala_nabi_enabled') ?? false;
    _settings.salatAlaNabiInterval = prefs.getString('salat_ala_nabi_interval') ?? 'كل ساعة';
    _settings.customUserTitle = prefs.getString('custom_user_title') ?? '';
    _settings.customSecTitle = prefs.getString('custom_sec_title') ?? '';
    _settings.stopRecordMode = prefs.getString('stop_record_mode') ?? 'manual_only';

    _settings.snoozeMinutes = prefs.getInt('snooze_minutes') ?? 5;
    _settings.diaryLockEnabled = prefs.getBool('diary_lock_enabled') ?? false;
    _settings.diaryPin = prefs.getString('diary_pin') ?? '';
    _settings.diarySecurityQuestion = prefs.getString('diary_sec_q') ?? '';
    _settings.diarySecurityAnswer = prefs.getString('diary_sec_a') ?? '';
    _settings.isProUser = prefs.getBool('is_pro_user') ?? false; // 👈 التعديل

    Future.delayed(const Duration(seconds: 2), () {
      _scheduleSalatAlaNabi();
    });

    _tasbeehCount = prefs.getInt('tasbeeh_count') ?? 0;
    _playbackVolume = prefs.getDouble('playback_volume') ?? 1.0;
    _playbackSpeed = prefs.getDouble('playback_speed') ?? 1.0;
    _ttsVolume = prefs.getDouble('tts_volume') ?? 1.0;

    for (var item in _tasbeehItems) {
      _tasbeehSubCounts[item['key']!] = prefs.getInt('tasbeeh_${item['key']}') ?? 0;
    }

    if (mounted) setState(() {});
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_tasks', json.encode(_tasks));
    await prefs.setString('saved_events', json.encode(_specialEvents));
    await prefs.setString('saved_diaries', json.encode(_diaries));
    await prefs.setString('saved_weekly_schedule', json.encode(_weeklySchedule));
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_reminder_hour', _settings.defaultReminderHour);
    await prefs.setInt('default_reminder_minute', _settings.defaultReminderMinute);
    await prefs.setString('voice_level', _settings.voiceLevel);
    await prefs.setBool('greeting_enabled', _settings.greetingEnabled);
    await prefs.setBool('adhan_alert_enabled', _settings.adhanAlertEnabled);
    await prefs.setBool('show_above_lock_screen', _settings.showAboveLockScreen);
    await prefs.setString('shake_mode', _settings.shakeMode);
    await prefs.setBool('mute_beep', _settings.muteBeep);
    await prefs.setString('voice_gender', _settings.voiceGender);
    await prefs.setString('default_interval', _settings.defaultInterval);
    await prefs.setString('custom_wake_word', _settings.customWakeWord);
    await prefs.setString('wake_word_mode', _settings.wakeWordMode);
    await prefs.setString('wake_word_trigger', _settings.wakeWordTrigger);
    await prefs.setBool('use_overlay_alarm', _settings.useOverlayAlarm);
    await prefs.setBool('is_kids_mode', _settings.isKidsMode);
    await prefs.setString('custom_greeting', _settings.customGreeting);
    await prefs.setBool('tahajjud_alert_enabled', _settings.tahajjudAlertEnabled);
    await prefs.setBool('is_dark_mode', _settings.isDarkMode);
    await prefs.setBool('is_pro_user', _settings.isProUser); // 👈 التعديل
    if (_settings.customImagePath != null) {
      await prefs.setString('custom_secretary_image', _settings.customImagePath!);
    } else {
      await prefs.remove('custom_secretary_image');
    }
    await prefs.setInt('tasbeeh_count', _tasbeehCount);
    for (var item in _tasbeehItems) {
      await prefs.setInt('tasbeeh_${item['key']}', _tasbeehSubCounts[item['key']] ?? 0);
    }
    await prefs.setDouble('playback_volume', _playbackVolume);
    await prefs.setDouble('playback_speed', _playbackSpeed);
    await prefs.setDouble('tts_volume', _ttsVolume);
    await prefs.setString('stop_record_mode', _settings.stopRecordMode);

    await prefs.setInt('snooze_minutes', _settings.snoozeMinutes);
    await prefs.setBool('diary_lock_enabled', _settings.diaryLockEnabled);
    await prefs.setString('diary_pin', _settings.diaryPin);
    await prefs.setString('diary_sec_q', _settings.diarySecurityQuestion);
    await prefs.setString('diary_sec_a', _settings.diarySecurityAnswer);
  }

  Future<void> _saveWeeklySchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_weekly_schedule', json.encode(_weeklySchedule));
  }

  Future<void> _saveAdhkarCounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_adhkar_counts', json.encode(_adhkarCounts));
  }

  int _getAdvanceMinutes(String reminder) {
    switch (reminder) {
      case 'قبلها بـ 5 دقائق': return 5;
      case 'قبلها بـ 10 دقائق': return 10;
      case 'قبلها بـ 15 دقيقة': return 15;
      case 'قبلها بـ 20 دقيقة': return 20;
      case 'قبلها بـ 30 دقيقة': return 30;
      case 'قبلها بـ 45 دقيقة': return 45;
      case 'قبلها بساعة': return 60;
      case 'قبلها ب 6 ساعات': return 360;
      case 'قبلها ب 12 ساعة': return 720;
      case 'قبلها بـ 24 ساعة': return 1440;
      default: return 0;
    }
  }

  void _scheduleWeeklyAlarm(String taskTitle, String day, DateTime scheduledDateTime, String interval, String advanceReminder, {String? soundUri}) {
    int advanceMins = _getAdvanceMinutes(advanceReminder);
    DateTime alarmTime = scheduledDateTime.subtract(Duration(minutes: advanceMins));
    _scheduleContinuousAlarm('جدول_${day}_${DateFormat('HHmm').format(scheduledDateTime)}_$taskTitle', alarmTime, 'أسبوعي', interval, [day], soundUri: soundUri);
  }

  Future<void> _loadRecordings() async {
    final prefs = await SharedPreferences.getInstance();
    String? recordingsString = prefs.getString('saved_recordings');
    if (recordingsString != null) {
      setState(() {
        _recordings = List<Map<String, dynamic>>.from(json.decode(recordingsString));
      });
    }
  }

  Future<void> _saveRecordings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_recordings', json.encode(_recordings));
  }

  Future<void> _showRecordingNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'recording_channel_v1',
      'تسجيل الصوت',
      channelDescription: 'يظهر أثناء تسجيل الصوت',
      importance: Importance.low, priority: Priority.low,
      ongoing: true, autoCancel: false, showWhen: false,
      actions: [
        AndroidNotificationAction('stop_recording', 'إيقاف التسجيل', showsUserInterface: true, cancelNotification: true)
      ],
    );
    await _notifications.show(9999, 'جاري التسجيل...', 'اضغط لإيقاف التسجيل', NotificationDetails(android: androidDetails));
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final recordingsDir = Directory('${dir.path}/recordings');
        if (!await recordingsDir.exists()) {
          await recordingsDir.create(recursive: true);
        }
        final fileName = 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final path = '${recordingsDir.path}/$fileName';

        const config = RecordConfig(
          encoder: AudioEncoder.aacLc, bitRate: 128000,
          sampleRate: 44100, numChannels: 1,
        );
        await _audioRecorder.start(config, path: path);
        setState(() {
          _isRecording = true;
          _recordingDuration = Duration.zero;
        });

        _showRecordingNotification();

        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _recordingDuration += const Duration(seconds: 1));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التسجيل: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    setState(() => _isRecording = false);
    try {
      await _notifications.cancel(9999);
      _recordingTimer?.cancel();
      final path = await _audioRecorder.stop();
      if (path != null) {
        final newRecording = {
          'path': path,
          'name': 'تسجيل ${_recordings.length + 1}',
          'duration': _formatDuration(_recordingDuration),
          'createdAt': DateTime.now().toIso8601String(),
        };
        setState(() {
          _recordings.insert(0, newRecording);
          _isRecording = false;
          _recordingDuration = Duration.zero;
        });
        await _saveRecordings();
      }
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _playRecording(String path) async {
    try {
      if (_currentlyPlayingPath == path) {
        await _audioPlayer.stop();
        await _positionSub?.cancel();
        await _durationSub?.cancel();
        setState(() {
          _currentlyPlayingPath = null;
          _currentPosition = Duration.zero;
          _currentDuration = Duration.zero;
        });
      } else {
        await _audioPlayer.stop();
        await _positionSub?.cancel();
        await _durationSub?.cancel();

        _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
          if (mounted) setState(() => _currentPosition = pos);
        });
        _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
          if (mounted) setState(() => _currentDuration = dur);
        });

        await _audioPlayer.setVolume(_playbackVolume);
        await _audioPlayer.setPlaybackRate(_playbackSpeed);
        await _audioPlayer.play(DeviceFileSource(path));
        setState(() => _currentlyPlayingPath = path);

        _audioPlayer.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() {
              _currentlyPlayingPath = null;
              _currentPosition = Duration.zero;
              _currentDuration = Duration.zero;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التشغيل: $e')),
        );
      }
    }
  }

  Future<void> _shareRecording(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await Share.shareXFiles([XFile(path)], text: 'تسجيل صوتي');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في المشاركة: $e')),
        );
      }
    }
  }

  Future<void> _deleteRecording(int index) async {
    try {
      final path = _recordings[index]['path'].toString();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      setState(() {
        _recordings.removeAt(index);
      });
      await _saveRecordings();
    } catch (_) {}
  }

  void _renameRecording(int index) {
    TextEditingController nameCtrl = TextEditingController(text: _recordings[index]['name'].toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('إعادة تسمية التسجيل', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم الجديد')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                setState(() {
                  _recordings[index]['name'] = nameCtrl.text;
                });
                _saveRecordings();
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventRepeatTimer?.cancel();
    _accelerometerSub?.cancel();
    _adhanTimer?.cancel();
    _recordingTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _pendingActionTimer?.cancel();
    _alarmVoiceSafetyTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    for (var timer in _activeTimers) {
      timer.cancel();
    }
    _speech.cancel();
    super.dispose();
  }

  Future<void> _configureVoice({bool skipGreeting = false}) async {
    try {
      await _tts.setLanguage("ar-EG");
      await _tts.awaitSpeakCompletion(true);
      await Future.delayed(const Duration(milliseconds: 150));
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final gender = prefs.getString('voice_gender') ?? _settings.voiceGender;

    try {
      final voices = await _getArabicVoices();
      if (voices.isNotEmpty) {
        await _tts.setVoice({
          'name': voices.first['name']!,
          'locale': voices.first['locale']!,
        });
        await Future.delayed(const Duration(milliseconds: 150));
      }
    } catch (_) {}

    try {
      if (gender == 'ذكر') {
        await _tts.setPitch(0.6);
        await _tts.setSpeechRate(_settings.speechRate);
        await _tts.setVolume(1.0);
      } else {
        await _tts.setPitch(1.15);
        await _tts.setSpeechRate(_settings.speechRate);
        await _tts.setVolume(_settings.speechVolume * _ttsVolume);
      }

      if (!skipGreeting && _settings.greetingEnabled) {
        String greeting = _settings.customGreeting;

        String userPrefix = _settings.customUserTitle.trim().isNotEmpty ? _settings.customUserTitle.trim() : (_isUserMale ? 'يَا فَنْدِم' : 'يَا أُسْتَاذَة');
        greeting = greeting.replaceAll('{user}', userPrefix);

        if (!_isUserMale) {
          greeting = greeting.replaceAll('بِكَ', 'بِكِ');
          greeting = greeting.replaceAll('بك ', 'بِكِ ');
          greeting = greeting.replaceAll('بك.', 'بِكِ.');
        }

        greeting = greeting.replaceAll('{sec}', _secWord).replaceAll('{name}', _secretaryName);

        if (_settings.isKidsMode) greeting = "أَهْلاً يَا بَطَل! أَنَا صَدِيقُكَ $_secWord، هَنُسَاعِدَكْ نِلْعَبْ وَنِتْعَلِّمْ مَعْ بَعْض.";
        await _tts.speak(greeting);
      }
    } catch (_) {}
  }

  Future<List<Map<String, String>>> _getArabicVoices() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return [];
      final list = <Map<String, String>>[];
      for (final v in voices) {
        if (v is! Map) continue;
        final name = v['name']?.toString() ?? '';
        final locale = v['locale']?.toString() ?? '';
        if (locale.toLowerCase().startsWith('ar') && name.isNotEmpty) {
          list.add({'name': name, 'locale': locale});
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _speak(String text) async {
    if (_settings.wakeWordMode != 'off') {
      try { await _wakeWordChannel.invokeMethod('pauseWakeWord'); } catch (_) {}
      if (_isWakeWordListening) {
        try { await _speech.stop(); } catch (_) {}
        _isWakeWordListening = false;
      }
    }

    try {
      final gender = _settings.voiceGender;
      if (gender == 'ذكر') {
        await _tts.setPitch(0.6);
        await _tts.setSpeechRate(_settings.speechRate);
        await _tts.setVolume(1.0);
      } else {
        await _tts.setPitch(1.15);
        await _tts.setSpeechRate(_settings.speechRate);
        await _tts.setVolume(_settings.speechVolume * _ttsVolume);
      }
      await _tts.speak(text);
    } catch (e) {
      debugPrint("TTS Error: $e");
    }

    if (_settings.wakeWordMode != 'off') {
      Future.delayed(const Duration(seconds: 1), () {
        try { _wakeWordChannel.invokeMethod('resumeWakeWord'); } catch (_) {}
        if (!_isListening && !_isInBackground && !_ignoreNextWakeWordStart) _startWakeWordLoop();
      });
    }
  }

  Future<void> _listenVoiceCommand() async {
    // 👇 التعديل: قفل المايك للنسخة البرو
    if (!_isProUser) {
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => PremiumScreen(
          onActivated: () => setState(() => _isProUser = true),
        )));
      }
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      try { await _wakeWordChannel.invokeMethod('resumeWakeWord'); } catch (_) {}
      return;
    }
    if (_starting) return;
    _starting = true;
    try {
      if (!_speechReady) await _initSpeech();
      if (!_speechReady) return;

      try { await _wakeWordChannel.invokeMethod('pauseWakeWord'); } catch (_) {}

      if (_isRecording) {
        await _stopRecording();
      }
      if (_DiaryPageState.activeInstance != null) {
        _DiaryPageState.activeInstance!.stopRecordingByVoice();
      }

      await _tts.stop();
      try { await _speech.cancel(); } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) {
        setState(() => _isListening = true);
        if (!_isTasbeehMode && !_isAdhkarMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎤 التطبيق بيستمع ليك دلوقتي...', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFF1B2A4A),
            ),
          );
        }
      }

      bool hasFinishedTasbeeh = false;
      bool hasFinishedAdhkar = false;

      await _speech.listen(
        localeId: "ar-EG", onDevice: false,
        listenFor: const Duration(seconds: 60), pauseFor: const Duration(seconds: 10),
        partialResults: true,
        onResult: (val) {
          if (_isTasbeehMode) {
            if (val.finalResult && !hasFinishedTasbeeh) {
              hasFinishedTasbeeh = true;
              _handleTasbeehResult(val.recognizedWords);
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && _isTasbeehMode) _listenVoiceCommand();
              });
            }
          } else if (_isAdhkarMode) {
            if (val.finalResult && !hasFinishedAdhkar) {
              hasFinishedAdhkar = true;
              _handleAdhkarResult(val.recognizedWords);
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && _isAdhkarMode) _listenVoiceCommand();
              });
            }
          } else {
            if (val.finalResult) {
              if (mounted) setState(() => _isListening = false);
              if (_settings.wakeWordMode != 'off') {
                try { _wakeWordChannel.invokeMethod('resumeWakeWord'); } catch (_) {}
              }
              _processSmartVoiceCommand(val.recognizedWords);
            }
          }
        },
      );
    } catch (e) {
      debugPrint("Listen Error: $e");
      if (mounted) setState(() => _isListening = false);
      if (_settings.wakeWordMode != 'off') {
        try { await _wakeWordChannel.invokeMethod('resumeWakeWord'); } catch (_) {}
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _startWakeWordLoop() async {
    if (_settings.wakeWordMode == 'off') return;
    if (_ignoreNextWakeWordStart) return;
    if (_isListening || _starting || _isRecording) return;
    if (_isInBackground && _settings.wakeWordMode == 'app_open') return;

    if (_wakeWordFailCount >= 5) {
      Future.delayed(const Duration(seconds: 30), () {
        _wakeWordFailCount = 0;
        if (mounted && !_isListening && !_starting && !_isRecording) {
          _startWakeWordLoop();
        }
      });
      return;
    }

    _isWakeWordListening = true;
    try {
      await _speech.listen(
        localeId: "ar-EG",
        onDevice: false,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 60),
        partialResults: true,
        onResult: (val) {
          if (val.recognizedWords.isEmpty) return;

          final compact = _norm(val.recognizedWords).replaceAll(RegExp(r'\s+'), '');
          final nameCompact = _norm(_secretaryName).replaceAll(RegExp(r'\s+'), '');
          final customCompact = _norm(_settings.customWakeWord).replaceAll(RegExp(r'\s+'), '');
          final isGenericMatch = compact.contains('ياسكرتير') || compact.contains('ياسكرتيره') || compact.contains('ياسكرتيرة');

          bool isTriggered = false;
          if (_settings.wakeWordTrigger == 'name_only') {
            isTriggered = (nameCompact.isNotEmpty && compact.contains(nameCompact)) || isGenericMatch;
          } else if (_settings.wakeWordTrigger == 'custom_only') {
            isTriggered = customCompact.isNotEmpty && compact.contains(customCompact);
          } else {
            isTriggered = (nameCompact.isNotEmpty && compact.contains(nameCompact)) ||
                          (customCompact.isNotEmpty && compact.contains(customCompact)) ||
                          isGenericMatch;
          }

          if (isTriggered) {
            _isWakeWordListening = false;
            _speech.stop();
            _listenVoiceCommand();
          }
        },
      );

      _wakeWordFailCount = 0;
      _isWakeWordListening = false;
      if (mounted && !_isListening && !_starting && !_isRecording && _settings.wakeWordMode != 'off') {
        if (!_isInBackground || _settings.wakeWordMode != 'app_open') {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted && !_isListening && !_starting && !_isRecording) {
              _startWakeWordLoop();
            }
          });
        }
      }
    } catch (e) {
      _isWakeWordListening = false;
      _wakeWordFailCount++;
      debugPrint("WakeWord Error: $e");
      if (mounted && _settings.wakeWordMode != 'off') {
        final delay = Duration(milliseconds: 500 * _wakeWordFailCount);
        Future.delayed(delay, () {
          if (mounted && !_isListening && !_starting && !_isRecording && (!_isInBackground || _settings.wakeWordMode != 'app_open')) {
            _startWakeWordLoop();
          }
        });
      }
    }
  }

  Future<bool> _handleSocialReply(String cmd) async {
    final userTitle = _userTitle;
    final secTitle = _settings.voiceGender == 'ذكر' ? 'السكرتير' : 'السكرتيرة';
    final now = DateTime.now();

    if (_hasAny(cmd, ['اطول ايه في القران', 'أطول آية', 'اطول سورة', 'أطول سورة'])) {
      await _speak("أَطْوَلُ آيَةٍ فِي القُرْآنِ هِيَ آيَةُ الدَّيْنِ فِي سُورَةِ البَقَرَةِ، وَعَدَدُ كَلِمَاتِهَا 128 كَلِمَة $userTitle.");
      return true;
    }
    if (_hasAny(cmd, ['اول سوره نزلت', 'أول سورة', 'اول ما نزل'])) {
      await _speak("أَوَّلُ مَا نَزَلَ مِنَ القُرْآنِ هُوَ قَوْلُهُ تَعَالَى: (اقْرَأْ بِاسْمِ رَبِّكَ الَّذِي خَلَقَ) فِي سُورَةِ العَلَق $userTitle.");
      return true;
    }
    if (_hasAny(cmd, ['اركان الاسلام', 'أركان الإسلام', 'اركان الايمان'])) {
      await _speak("أَرْكَانُ الإِسْلَامِ خَمْسَةٌ: شَهَادَةُ أَنْ لَا إِلَهَ إِلَّا اللَّهُ وَأَنَّ مُحَمَّداً رَسُولُ اللَّهِ، وَإِقَامُ الصَّلَاةِ، وَإِيتَاءُ الزَّكَاةِ، وَصَوْمُ رَمَضَانَ، وَحَجُّ البَيْتِ لِمَنِ اسْتَطَاعَ إِلَيْهِ سَبِيلًا.");
      return true;
    }
    if (_hasAny(cmd, ['عندي امتحان', 'امتحان بكرة', 'امتحان بكره', 'امتحان قريب'])) {
      await _speak("رَبَّنَا يُوَفِّقْكَ $userTitle، $_dontForget تُصَلِّي الفَجْرَ $_sleepWord بَدْرِي، وَ$_studyWord كُوَيِّسْ وَرَبَّنَا $_withYou.");
      return true;
    }

    if (_hasAny(cmd, ['سبحان الله', 'استغفر الله', 'الحمد لله', 'الله اكبر', 'لا اله الا الله', 'سبحان الله وبحمده'])) {
      _handleTasbeehResult(cmd);
      await _speak("جَزَاكَ اللَّهُ خَيْراً $userTitle، تَمَّ تَسْجِيلُ التَّسْبِيحَةِ. عَدَدُ التَّسْبِيحَاتِ: $_tasbeehCount.");
      return true;
    }
    if (_hasAny(cmd, ['شوف العداد', 'العداد كام', 'سبحت كام', 'كام تسبيحة'])) {
      await _speak("لَقَدْ سَبَّحْتَ $userTitle $_tasbeehCount مَرَّةً.");
      return true;
    }

    if (_hasAny(cmd, ['صباح الخير', 'صباح النور', 'صباح الفل', 'صباحو', 'صبح صباح الخير', 'صباح الخيرات', 'صباح الورد', 'صباح العسل'])) {
      await _speak("صَبَاحُ النُّورِ وَالسُّرُورِ $userTitle ☀️ أَتَمَنَّى لَكَ يَوْمَ سَعِيد! النَّهَارْدَة يَوْمْ جَدِيدْ وَفُرْصَة جَدِيدَة.");
      return true;
    }
    if (_hasAny(cmd, ['صباح الفل والياسمين', 'صباح الحب', 'صباح الجمال'])) {
      await _speak("صَبَاحُ الفُلِّ وَاليَاسَمِينِ وَالوَرْدِ $userTitle 🌸 يَوْمَكَ يَبْدَأُ بِخَيْرٍ إِنْ شَاءَ اللَّهُ.");
      return true;
    }
    if (_hasAny(cmd, ['مساء الخير', 'مساء النور', 'مساء الفل', 'مسائو', 'مسا الخير', 'مساء الخيرات', 'مساء الورد', 'مساء العسل', 'مساء الحب'])) {
      await _speak("مَسَاءُ النُّورِ وَالفُلِّ وَاليَاسَمِينِ $userTitle 🌙 أَتَمَنَّى تِكُونْ بِخِير. الوَقْتْ اتْأَخَّرْ، لَازِمْ جِسْمَكْ يِرْتَاحْ.");
      return true;
    }
    if (_hasAny(cmd, ['اهلا', 'أهلاً', 'مرحبا', 'هاي', 'hello', 'hi', 'ازيك', 'ازيك يا', 'عامل ايه', 'عاملة ايه', 'إيه الأخبار', 'ايه الاخبار'])) {
      await _speak("أَهْلاً بِيكَ $userTitle 🌟 أَنَا $secTitle الشَّخْصِيِّ بِتَاعَكْ، تَحْتْ أَمْرَكْ دَايْمًا.");
      return true;
    }

    if (_hasAny(cmd, ['بحبك', 'احبك', 'أحبك', 'بعشقك', 'من عشاقك', 'انتي حبيبتي', 'انت حبيبي'])) {
      await _speak("وَأَنَا كَمَانْ بِحِبَّكَ $userTitle 💛 دَهْ أَنَا تَحْتْ أَمْرَكْ دَايْمًا.");
      return true;
    }
    if (_hasAny(cmd, ['وحشتني', 'وحشتينى', 'وحشني', 'اشتقتلك', 'اشتقت لك', 'مشتاقلك', 'مشتاقة لك'])) {
      await _speak("$_pronoun كَمَانْ وَحَشْتِنِي $userTitle، أَنَا $_readyWord لِأَيِّ خِدْمَة 💛.");
      return true;
    }
    if (_hasAny(cmd, ['شاطر', 'شاطرة', 'ذكي', 'ذكية', 'عسل', 'برنس', 'جامد', 'جامدة', 'ممتاز', 'ممتازة', 'تسلم ايدك', 'تسلم إيدك'])) {
      await _speak("دَهْ مِنْ زُوقَكْ $userTitle، شُكْراً عَلَى المُجَامَلَةِ الحَلْوَةِ دِي 🙏.");
      return true;
    }
    if (_hasAny(cmd, ['ربنا يخليك', 'ربنا يخليكي', 'ربنا يسعدك', 'ربنا يوفقك', 'ربنا يخليك ليا', 'ربنا يكرمك'])) {
      await _speak("وَرَبَّنَا يِخَلِّيكْ لِيَا $userTitle، أَنَا فِي خِدْمَتِكَ دَايْمًا 💛.");
      return true;
    }

    if (_hasAny(cmd, ['تعبان', 'تعبانة', 'مش كويس', 'مش كويسة', 'مضايق', 'مضايقة', 'زعلان', 'زعلانة', 'حزين', 'حزينة', 'مش قادر', 'مش قادرة', 'مخنوق', 'مخنوقة'])) {
      await _speak("أَلْفْ سَلَامَة عَلِيكْ $userTitle، $_takeCareWord بِالَكْ مِنْ نَفْسَكْ. $_youWant أَفْتَحْلَكْ يَوْمِيَّاتَكْ تِكْتِبْ فِيهَا أَوْ أَحْجِزْلَكْ مَوْعِدْ، أَنَا تَحْتْ أَمْرَكْ 💚.");
      return true;
    }
    if (_hasAny(cmd, ['مبسوط', 'مبسوطة', 'فرحان', 'فرحانة', 'سعيد', 'سعيدة', 'الحمد لله مبسوط'])) {
      await _speak("وَأَنَا كَمَانْ $_happyWord لِيكْ $userTitle 😊 رَبَّنَا يِدِيمْ الفَرْحَة عَلِيكْ.");
      return true;
    }
    if (_hasAny(cmd, ['زهقان', 'زهقانة', 'مليت', 'حاسس بالوحدة', 'حاسة بالوحدة', 'طفشان', 'طفشانة', 'مخنوق ومش عارف أعمل ايه', 'مخنوقة ومش عارفة أعمل ايه'])) {
      await _speak("مَا تِزْعَلْشْ $userTitle، أَنَا مَعَاكْ. تِحِبْ أَحْكِيلَكْ نُكْتَة تِضَحِّكَكْ؟ وَلَا أَحْكِيلَكْ لُغْزْ تِشْغَلْ دِمَاغَكْ شُوَيَّةْ؟");
      return true;
    }
    if (_hasAny(cmd, ['خايف', 'خايفة', 'قلقان', 'قلقانة', 'متوتر', 'متوترة'])) {
      await _speak("هَدِّي نَفْسَكْ $userTitle، كُلِّ حَاجَة هَتْبَقَى تَمَام. أَنَا هِنَا $_youWant $_youTalk.");
      return true;
    }

    if (_hasAny(cmd, ['جعان', 'جعانة', 'عايز اكل', 'عايزة اكل', 'مش لاقي اكل', 'مش لاقية اكل'])) {
      await _speak("خُدْ بِالَكْ مِنْ نَفْسَكْ $userTitle، لَازِمْ تَاكُلْ حَاجَة. تِحِبْ أَفَكِّرَكْ بِمَوْعِدْ الأَكِلْ؟ 💚.");
      return true;
    }
    if (_hasAny(cmd, ['عطشان', 'عطشانة', 'عايز اشرب', 'عايزة اشرب'])) {
      await _speak("اشْرَبْ مَيَّة وَهَتِرْتَاحْ $userTitle، صِحَّتَكْ تِهِمَّنِي 💧.");
      return true;
    }
    if (_hasAny(cmd, ['قرفان', 'قرفانة'])) {
      await _speak("رَبَّنَا يُعِينَكْ $userTitle، خُدْ نَفَسْ عَمِيقْ وَغَيِّرْ جَوْ.");
      return true;
    }

    if (_hasAny(cmd, ['الساعه كام', 'الساعة كام', 'الوقت ايه', 'الساعة كم', 'الوقت كام', 'الساعه كم'])) {
      final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final period = now.hour >= 12 ? 'مَسَاءً' : 'صَبَاحاً';
      final min = now.minute.toString().padLeft(2, '0');
      await _speak("السَّاعَة $hour:$min $period $userTitle.");
      return true;
    }
    if (_hasAny(cmd, ['التاريخ ايه', 'تاريخ اليوم', 'انهاردة كام', 'تاريخ النهاردة', 'تاريخ النهارده'])) {
      final date = DateFormat('dd MMMM yyyy', 'ar').format(now);
      await _speak("تَارِيخْ النَّهَارْدَة هُوَ $date $userTitle.");
      return true;
    }
    if (_hasAny(cmd, ['اليوم ايه', 'يوم ايه النهاردة', 'انهاردة يوم ايه', 'اسم اليوم ايه'])) {
      final dayName = DateFormat('EEEE', 'ar').format(now);
      await _speak("النَّهَارْدَة يَوْمْ $dayName $userTitle.");
      return true;
    }

    if (_hasAny(cmd, ['نكته', 'نكتة', 'ضحكني', 'قولي نكته', 'اضحكني', 'حاجة تضحك', 'هزار', 'ضحكة', 'فشخرة', 'نكت'])) {
      final jokes = [
        "المُدَرِّسْ قَالْ لِلطَّالِبْ: لَوْ مَعَاكْ 10 جِنِيهْ وَخَدِتْ مِنْهُمْ 5 جِنِيهْ، فَاضِلَكْ كَامْ؟ الطَّالِبْ رَدْ وَقَالَهْ: خِنَاقَة كَبِيرَة يَا أُسْتَاذ! 😂",
        "وَاحِدْ صَاحِبَهْ سَأَلَهْ: إِيهْ الجَدِيدْ فِي المُوبَايِلْ اللي جِبْتَهْ دَهْ؟ قَالَهْ: دَهْ بِيِقْرَا البَصْمَة! صَاحِبَهْ قَالَهْ: يَا رَاجُلْ؟! طِيبْ جَرَّبْتْ تِفْتَحَهْ بِبَصْمَة رِجْلَكْ؟ 😂",
        "وَاحِدْ رَاحْ لِلصَّيْدَلِي وَقَالَهْ: عِنْدَكْ دَوَا لِلصَّلَعْ؟ الصَّيْدَلِي قَالَهْ: أَيُوهْ، عَايِزَهْ فِي كِيسْ وَلَا فِي إِزَازَةْ؟ 😂",
        "وَاحِدْ رَكِبْ تَاكْسِي وَقَالْ لِلسَّوَّاقْ: يَا أُسْطَى وَدِّينِي الجَامِعَة. الأُسْطَى بَصَلَهْ وَقَالَهْ: طِيبْ، هَتِقْعُدْ فِينْ؟ 😂"
      ];
      final randomJoke = jokes[random.nextInt(jokes.length)];
      await _speak("$userTitle، خُدْ دِي: $randomJoke");
      return true;
    }

    if (_hasAny(cmd, ['لغز', 'الغاز', 'ألغاز', 'حزورة', 'حزازير', 'شغل دماغك', 'اسألني لغز', 'فزورة', 'فزازير', 'شغل مخك'])) {
      final riddles = [
        "شَيْءٌ مَوْجُودٌ فِي السَّمَاءِ، إِذَا أَضَفْتَ إِلَيْهِ حَرْفاً وَاحِداً أَصْبَحَ فِي الأَرْضِ. فَمَا هُوَ؟",
        "مَا هُوَ الشَّيْءُ الَّذِي يَكْتُبُ وَلَا يَقْرَأُ؟",
        "مَا هُوَ الشَّيْءُ الَّذِي كُلَّمَا زَادَ نَقَصَ؟",
        "شَيْءٌ لَهُ أَسْنَانٌ وَلَا يَعَضُّ، مَا هُوَ؟",
      ];
      final answers = [
        "نَجْم، لَوْ ضِفْتَلَهْ حَرْفَ المِيمْ بِيِبْقَى مَنْجَمْ.",
        "القَلَمْ.",
        "العُمْرْ.",
        "المِشْطْ.",
      ];
      int randomIndex = random.nextInt(riddles.length);
      await _speak("$userTitle، خُدْ اللُّغْزْ دَهْ: ${riddles[randomIndex]}");
      await Future.delayed(const Duration(seconds: 10));
      await _speak("فَكَّرْتْ؟ الإِجَابَة هِيَ: ${answers[randomIndex]}");
      return true;
    }

    if (_hasAny(cmd, ['شكرا', 'شكراً', 'متشكر', 'متشكرة', 'مشكور', 'مشكورة', 'ميرسي', 'ميرسى', 'ثانكس', 'تسلم', 'تسلمي', 'تسلم ايدك', 'تسلم إيدك'])) {
      await _speak("العَفْو $userTitle، دَهْ وَاجِبِي 🙏.");
      return true;
    }
    if (_hasAny(cmd, ['تصبح على خير', 'تصبحى على خير', 'تصبحي على خير', 'تصبحوا على خير', 'ليلتك سعيدة', 'ليلة سعيدة'])) {
      await _speak("$_pronoun مِنْ أَهْلِهْ $userTitle، تُصْبَحْ عَلَى خَيْرٍ وَأَحْلَامٍ سَعِيدَة 🌙.");
      return true;
    }
    if (_hasAny(cmd, ['اسمك ايه', 'اسمك إيه', 'اسمك ايش', 'انت مين', 'انتي مين', 'مين انت', 'مين انتي'])) {
      await _speak("اِسْمِي $_secretaryName، $secTitle الشَّخْصِيِّ بِتَاعَكْ، تَحْتْ أَمْرَكْ $userTitle.");
      return true;
    }
    if (_hasAny(cmd, ['بتعمل ايه', 'بتعملي ايه', 'بتعمل إيه', 'بتشتغل ايه', 'بتشغلي ايه', 'مشغول بايه', 'مشغولة بايه'])) {
      await _speak("بَسْتَ نَى أَوَامِرَكْ $userTitle، جَاهِزْ أَرُدْ عَلَى أَيِّ حَاجَة 👌.");
      return true;
    }
    if (_hasAny(cmd, ['تمام', 'ماشي', 'اوكي', 'أوكي', 'ok', 'طيب', 'حاضر', 'خلاص كده'])) {
      await _speak("تَمَام $userTitle 👌.");
      return true;
    }
    if (_hasAny(cmd, ['سلام عليكم', 'السلام عليكم', 'باي', 'يلا سلام', 'مع السلامة', 'سلام'])) {
      await _speak("وَعَلَيْكُمْ السَّلَامُ وَرَحْمَةُ اللَّهِ وَبَرَكَاتُهُ $userTitle، فِي رِعَايَةِ اللَّهِ 🌟.");
      return true;
    }
    if (_hasAny(cmd, ['يلا', 'يالا', 'بسرعة', 'بسرعه', 'حالا', 'حالاً', 'دلوقتي'])) {
      await _speak("حَاضِرْ $userTitle، أَنَا فِي الخِدْمَة 🏃.");
      return true;
    }
    if (_hasAny(cmd, ['انت موجود', 'انتي موجودة', 'معايا', 'سامعني', 'سامعاني', 'سامعنى'])) {
      await _speak("أَيُوهْ $userTitle، أَنَا $_listenWord وَأَنَا فِي الخِدْمَة 👂.");
      return true;
    }
    if (_hasAny(cmd, ['صحة', 'أيوة', 'ايوه', 'ايوة', 'نعم', 'اه', 'آه'])) {
      await _speak("فِي الخِدْمَة $userTitle 👌.");
      return true;
    }
    if (_hasAny(cmd, ['مبروك', 'ألف مبروك', 'الف مبروك'])) {
      await _speak("اللَّهُ يُبَارِكْ فِيكْ $userTitle، عُقْبَالْ كُلِّ حَاجَة حَلْوَة 🎉.");
      return true;
    }
    if (_hasAny(cmd, ['سلامتك', 'الف سلامة', 'ألف سلامة'])) {
      await _speak("اللَّهُ يُسَلِّمَكْ $userTitle 💚.");
      return true;
    }

    return false;
  }

// ══════════════════════════════════════════════════════
// نهاية PART 4 / 8
// ══════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════
// PART 5 / 8
// Date Parsers + _processSmartVoiceCommand (بداية)
// يشمل: أوامر الإعدادات الصوتية (14 بلوك) + إيقاف التسجيل
// ══════════════════════════════════════════════════════

  DateTime? _parseFullDate(String cmd) {
    final now = DateTime.now();
    String normCmd = _norm(cmd);

    if (normCmd.contains('بعد بكره') || normCmd.contains('بعد بكرة') || normCmd.contains('بعد غد')) return now.add(const Duration(days: 2));
    if (normCmd.contains('بكره') || normCmd.contains('بكرة') || normCmd.contains('غدا') || normCmd.contains('غداً')) return now.add(const Duration(days: 1));

    if (normCmd.contains('الاسبوع الجاي') || normCmd.contains('الاسبوع القادم') || normCmd.contains('اسبوع جاي') || normCmd.contains('الاسبوع اللي جاي')) {
      return now.add(const Duration(days: 7));
    }
    if (normCmd.contains('الشهر الجاي') || normCmd.contains('الشهر القادم') || normCmd.contains('شهر جاي') || normCmd.contains('الشهر اللي جاي')) {
      return DateTime(now.year, now.month + 1, now.day);
    }
    if (normCmd.contains('السنة الجاية') || normCmd.contains('السنة القادمة') || normCmd.contains('سنة جاية') || normCmd.contains('العام الجاي') || normCmd.contains('السنة اللي جاية')) {
      return DateTime(now.year + 1, now.month, now.day);
    }

    if (normCmd.contains('النهاردة') || normCmd.contains('النهارده') || normCmd.contains('اليوم') || normCmd.contains('انهاردة') || normCmd.contains('انهارده')) return now;
    if (normCmd.contains('امبارح') || normCmd.contains('امس') || normCmd.contains('البارح')) return now.subtract(const Duration(days: 1));
    if (normCmd.contains('اول امبارح') || normCmd.contains('قبل امبارح')) return now.subtract(const Duration(days: 2));

    final afterDaysMatch = RegExp(r'بعد\s*(\d+)\s*(يوم|ايام|أيام)').firstMatch(normCmd);
    if (afterDaysMatch != null) return now.add(Duration(days: int.parse(afterDaysMatch.group(1)!)));

    final dayKeywords = {
      DateTime.saturday: ['السبت', 'سبت'],
      DateTime.sunday: ['الاحد', 'الأحد', 'الحد', 'حد'],
      DateTime.monday: ['الاتنين', 'الاثنين', 'اتنين'],
      DateTime.tuesday: ['التلات', 'الثلاثاء', 'تلات'],
      DateTime.wednesday: ['الاربع', 'الأربعاء', 'اربع'],
      DateTime.thursday: ['الخميس', 'خميس'],
      DateTime.friday: ['الجمعه', 'الجمعة', 'جمعه'],
    };

    int? targetWeekday;
    for (final entry in dayKeywords.entries) {
      if (_hasAny(normCmd, entry.value)) {
        targetWeekday = entry.key;
        break;
      }
    }

    if (targetWeekday != null) {
      final isAfterNext = _hasAny(normCmd, ['بعد الجاي', 'اللي بعد الجاي', 'بعد القادم', 'اللي بعد القادم', 'اللي بعده', 'اللي بعدها', 'اللي بعدهم']);
      final isLast = _hasAny(normCmd, ['اللي فات', 'اللى فات', 'الماضي']);
      final isNext = _hasAny(normCmd, ['الجاي', 'القادم', 'اللي جاي']);

      if (isLast) {
        var diff = now.weekday - targetWeekday;
        if (diff <= 0) diff += 7;
        return now.subtract(Duration(days: diff));
      } else if (isAfterNext) {
        var diff = targetWeekday - now.weekday;
        if (diff <= 0) diff += 7;
        return now.add(Duration(days: diff + 7));
      } else if (isNext) {
        var diff = targetWeekday - now.weekday;
        if (diff <= 0) diff += 7;
        return now.add(Duration(days: diff));
      } else {
        var diff = targetWeekday - now.weekday;
        if (diff < 0) diff += 7;
        return now.add(Duration(days: diff));
      }
    }

    int? parsedDay; int? parsedMonth;

    final dateMatch = RegExp(r'(\d{1,2})\s*[/\-\s]\s*(\d{1,2})').firstMatch(normCmd);
    if (dateMatch != null) {
      parsedDay = int.tryParse(dateMatch.group(1)!);
      parsedMonth = int.tryParse(dateMatch.group(2)!);
    } else {
      String tempCmd = normCmd;
      final numWords = {
        'واحد': '1', 'واحده': '1', 'اتنين': '2', 'اثنين': '2',
        'تلاته': '3', 'ثلاثه': '3', 'اربعه': '4', 'خمسه': '5',
        'سته': '6', 'سبعه': '7', 'تمانيه': '8', 'ثمانيه': '8',
        'تسعه': '9', 'عشره': '10', 'احداشر': '11', 'اتناشر': '12',
        'عشرين': '20', 'تلاتين': '30'
      };

      numWords.forEach((word, digit) {
        tempCmd = tempCmd.replaceAll(RegExp(r'\b' + word + r'\b'), digit);
      });

      final wordDateMatch = RegExp(r'(\d{1,2})\s*[/\-\s]\s*(\d{1,2})').firstMatch(tempCmd);
      if (wordDateMatch != null) {
        parsedDay = int.tryParse(wordDateMatch.group(1)!);
        parsedMonth = int.tryParse(wordDateMatch.group(2)!);
      }
    }

    if (parsedMonth == null) {
      final monthsMap = {
        1: ['يناير', '1'], 2: ['فبراير', '2'], 3: ['مارس', '3'], 4: ['ابريل', 'أبريل', '4'],
        5: ['مايو', '5'], 6: ['يونيو', '6'], 7: ['يوليو', '7'], 8: ['اغسطس', 'أغسطس', '8'],
        9: ['سبتمبر', '9'], 10: ['اكتوبر', 'أكتوبر', '10'], 11: ['نوفمبر', '11'], 12: ['ديسمبر', '12'],
      };

      for (var entry in monthsMap.entries) {
        if (_hasAny(normCmd, entry.value)) {
          parsedMonth = entry.key;
          break;
        }
      }

      if (parsedMonth != null) {
        final dayWordsMap = {
          1: ['واحد', 'واحدة'], 2: ['اتنين'], 3: ['تلاتة'], 4: ['اربعة'], 5: ['خمسة'],
          6: ['ستة'], 7: ['سبعة'], 8: ['تمانية'], 9: ['تسعة'], 10: ['عشرة'],
          11: ['حداشر'], 12: ['اتناشر'], 13: ['تلتاشر'], 14: ['اربعطاشر'], 15: ['خمستاشر', 'خمسة عشر'],
          16: ['ستاشر'], 17: ['سبعتاشر'], 18: ['تمنتاشر'], 19: ['تسعتاشر'], 20: ['عشرين'],
          21: ['واحد وعشرين'], 22: ['اتنين وعشرين'], 23: ['تلاتة وعشرين'], 24: ['اربعة وعشرين'],
          25: ['خمسة وعشرين'], 26: ['ستة وعشرين'], 27: ['سبعة وعشرين'], 28: ['تمانية وعشرين'],
          29: ['تسعة وعشرين'], 30: ['تلاتين'], 31: ['واحد وتلاتين']
        };

        final dayDigitMatch = RegExp(r'(\d{1,2})').firstMatch(normCmd);
        if (dayDigitMatch != null) {
          parsedDay = int.tryParse(dayDigitMatch.group(1)!);
        } else {
          for (var entry in dayWordsMap.entries) {
            if (_hasAny(normCmd, entry.value)) {
              parsedDay = entry.key;
              break;
            }
          }
        }
      }
    }

    if (parsedDay != null && parsedMonth != null && parsedMonth >= 1 && parsedMonth <= 12 && parsedDay >= 1 && parsedDay <= 31) {
      try { return DateTime(now.year, parsedMonth, parsedDay); } catch (_) { return null; }
    }

    if (parsedMonth == null) {
      final dayOnlyMatch = RegExp(r'يوم\s*(\d{1,2})').firstMatch(normCmd);
      if (dayOnlyMatch != null) {
        parsedDay = int.tryParse(dayOnlyMatch.group(1)!);
      } else {
        final dayWordsMap = {
          1: ['واحد', 'واحدة'], 2: ['اتنين'], 3: ['تلاتة'], 4: ['اربعة'], 5: ['خمسة'],
          6: ['ستة'], 7: ['سبعة'], 8: ['تمانية'], 9: ['تسعة'], 10: ['عشرة'],
          11: ['حداشر'], 12: ['اتناشر'], 13: ['تلتاشر'], 14: ['اربعطاشر'], 15: ['خمستاشر', 'خمسة عشر'],
          16: ['ستاشر'], 17: ['سبعتاشر'], 18: ['تمنتاشر'], 19: ['تسعتاشر'], 20: ['عشرين'],
          21: ['واحد وعشرين'], 22: ['اتنين وعشرين'], 23: ['تلاتة وعشرين'], 24: ['اربعة وعشرين'],
          25: ['خمسة وعشرين'], 26: ['ستة وعشرين'], 27: ['سبعة وعشرين'], 28: ['تمانية وعشرين'],
          29: ['تسعة وعشرين'], 30: ['تلاتين'], 31: ['واحد وتلاتين']
        };
        for (var entry in dayWordsMap.entries) {
          if (_hasAny(normCmd, entry.value)) {
            parsedDay = entry.key;
            break;
          }
        }
      }

      if (parsedDay != null && parsedDay >= 1 && parsedDay <= 31) {
        var result = DateTime(now.year, now.month, parsedDay);
        if (result.isBefore(now)) result = DateTime(now.year, now.month + 1, parsedDay);
        return result;
      }
    }

    return null;
  }

  String _cleanDateWordsFromText(String text) {
    String cleaned = text;
    final monthsList = ['يناير','فبراير','مارس','ابريل','أبريل','مايو','يونيو','يوليو','اغسطس','أغسطس','سبتمبر','اكتوبر','أكتوبر','نوفمبر','ديسمبر'];
    final dayWords = ['واحد', 'واحدة', 'اتنين', 'اثنين', 'تلاتة', 'ثلاثة', 'اربعة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'تمانية', 'ثمانية', 'تسعة', 'عشرة', 'حداشر', 'اتناشر', 'تلتاشر', 'اربعطاشر', 'خمستاشر', 'خمسة عشر', 'ستاشر', 'سبعتاشر', 'تمنتاشر', 'تسعتاشر', 'عشرين', 'تلاتين', 'ثلاثين'];

    for (var m in monthsList) {
      cleaned = cleaned.replaceAll(RegExp(r'\d+\s*' + m), '');
      for (var w in dayWords) {
        cleaned = cleaned.replaceAll(RegExp(r'\b' + w + r'\s*' + m), '');
      }
      cleaned = cleaned.replaceAll(RegExp(r'\b' + m + r'\b'), '');
    }

    final relativeDays = [
      'النهاردة', 'النهارده', 'انهاردة', 'انهارده', 'اليوم',
      'بكرة', 'بكره', 'غدا', 'غداً',
      'امبارح', 'امس', 'البارح', 'اول امبارح', 'قبل امبارح',
      'بعد بكرة', 'بعد بكره', 'بعد غد',
      'الاسبوع الجاي', 'الاسبوع القادم', 'اسبوع جاي', 'الاسبوع اللي جاي',
      'الشهر الجاي', 'الشهر القادم', 'شهر جاي', 'الشهر اللي جاي',
      'السنة الجاية', 'السنة القادمة', 'سنة جاية', 'العام الجاي', 'السنة اللي جاية'
    ];
    relativeDays.sort((a, b) => b.length.compareTo(a.length));
    for (var d in relativeDays) {
      cleaned = cleaned.replaceAll(RegExp(r'\b' + d + r'\b'), '');
    }

    final days = ['السبت', 'سبت', 'الاحد', 'الأحد', 'الحد', 'حد', 'الاتنين', 'الاثنين', 'التلات', 'الثلاثاء', 'الاربع', 'الأربعاء', 'الخميس', 'خميس', 'الجمعه', 'الجمعة', 'جمعه'];
    for (var d in days) {
      cleaned = cleaned.replaceAll(RegExp(r'\bيوم\s+' + d + r'\b'), '');
      cleaned = cleaned.replaceAll(RegExp(r'\b' + d + r'\b'), '');
    }
    cleaned = cleaned.replaceAll(RegExp(r'\bيوم\b'), '');

    cleaned = cleaned.replaceAll(RegExp(r'بعد\s*\d+\s*(يوم|ايام|أيام)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\bيوم\s*\d{1,2}\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b\d{1,2}\s*[/\-]\s*\d{1,2}\b'), '');

    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  DateTime? _parseDiaryDate(String cmd) {
    return _parseFullDate(cmd);
  }

  List<String> _parseCustomDays(String cmd) {
    final days = <String>[];
    _dayKeywords.forEach((dayName, keywords) {
      if (_hasAny(cmd, keywords)) days.add(dayName);
    });
    return days;
  }

  String _parseRepeatType(String cmd) {
    final customDays = _parseCustomDays(cmd);
    if (customDays.isNotEmpty) return 'مخصص';
    if (_hasAny(cmd, ['كل يومين', 'يوم بعد يوم'])) return 'كل يومين';
    if (_hasAny(cmd, ['كل اسبوعين', 'كل أسبوعين'])) return 'كل أسبوعين';
    if (_hasAny(cmd, ['كل يوم', 'يومي', 'يوميا', 'يومياً', 'كل يوم الصبح', 'كل يوم بالليل', 'يوم بيوم', 'دائما', 'على طول', 'كل صباح', 'كل مساء', 'كل ليله', 'بشكل يومي'])) return 'يومي';
    if (_hasAny(cmd, ['كل اسبوع', 'اسبوعي', 'اسبوعيا', 'كل جمعه', 'كل جمعة', 'كل 7 ايام', 'اسبوع ورا اسبوع'])) return 'أسبوعي';
    if (_hasAny(cmd, ['كل شهر', 'شهري', 'شهريا', 'كل 30 يوم', 'شهر ورا شهر', 'كل اول الشهر'])) return 'شهري';
    return 'مرة واحدة';
  }

  String _parseIntervalType(String cmd) {
    if (_hasAny(cmd, ['بدون تنبيه', 'بدون تنبيهات', 'مش محتاج تنبيه', 'مش عايز تنبيه', 'مش عايزة تنبيه', 'من غير تنبيه', 'بلاش تنبيه', 'مش عاوزة تنبيه'])) return 'بدون تنبيه';
    if (_hasAny(cmd, ['مره واحده بس', 'مرة واحدة بس', 'تنبيه واحد بس', 'مش محتاج يتكرر', 'مش محتاجة يتكرر'])) return 'مرة واحدة';
    if (_hasAny(cmd, ['كل 10 ثواني', 'كل عشر ثواني', 'كل عشره ثواني'])) return 'كل 10 ثواني';
    if (_hasAny(cmd, ['كل 20 ثانية', 'كل عشرين ثانيه'])) return 'كل 20 ثانية';
    if (_hasAny(cmd, ['كل 30 ثانية', 'كل تلاتين ثانيه', 'نص دقيقه', 'نصف دقيقة'])) return 'كل 30 ثانية';
    if (_hasAny(cmd, ['كل دقيقة', 'كل دقيقه', 'كل 60 ثانيه'])) return 'كل دقيقة';
    if (_hasAny(cmd, ['كل دقيقتين'])) return 'كل دقيقتين';
    if (_hasAny(cmd, ['كل 3 دقايق', 'كل تلات دقايق'])) return 'كل 3 دقايق';
    if (_hasAny(cmd, ['كل 5 دقايق', 'كل خمس دقايق'])) return 'كل 5 دقايق';
    if (_hasAny(cmd, ['كل 10 دقايق', 'كل عشر دقايق'])) return 'كل 10 دقايق';
    return 'كل 10 ثواني';
  }

  List<String> _extractWeeklyDaysFromCmd(String cmd) {
    final result = <String>[];

    if (_hasAny(cmd, ['بالكامل', 'الجدول كله', 'كل الايام', 'كل الأيام', 'طول الاسبوع', 'طول الأسبوع', 'كل الجدول'])) {
      return ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];
    }

    if (_hasAny(cmd, ['النهاردة', 'النهارده', 'انهاردة', 'انهارده', 'اليوم'])) {
      result.add(_weekDays[(DateTime.now().weekday) % 7]);
    }
    if (_hasAny(cmd, ['بكره', 'بكرة', 'غدا', 'غداً'])) {
      result.add(_weekDays[(DateTime.now().add(const Duration(days: 1)).weekday) % 7]);
    }

    for (final day in _weekDays) {
      if (result.contains(day)) continue;
      final keywords = _dayKeywords[day] ?? [day];
      if (_hasAny(cmd, keywords)) {
        result.add(day);
      }
    }
    return result;
  }

  String _extractWeeklyTaskName(String rawCommand) {
    final stripRaw = <String>{
      'امسح', 'امسحي', 'احذف', 'احذفي', 'شيل', 'شيلي', 'الغي', 'الغى', 'الغيلي',
      'مسح', 'حذف', 'امسحلي', 'امسحيلي',
      'عدل', 'عدلي', 'عدللي', 'عدليلي', 'غير', 'غيري', 'غيرلي', 'غيريلي',
      'بدل', 'بدلي', 'بدللي', 'بدليلي', 'تعديل', 'تعديلي',
      'ضيف', 'ضيفي', 'ضيفلي', 'اضف', 'أضف', 'أضفي', 'حط', 'حطي', 'حطلي',
      'سجل', 'سجلي', 'سجللي', 'اعمل', 'اعملي', 'اعمللي',
      'الجدول', 'جدول', 'الاسبوعي', 'الأسبوعي', 'اسبوعي', 'أسبوعي',
      'جدولي', 'جدولى', 'بتاعي', 'بتاعى',
      'في', 'من', 'على', 'علي', 'بتاع', 'بتاعه', 'بتاعت', 'يوم',
      'موعد', 'ميعاد', 'الميعاد', 'الموعد', 'و',
      'الساعة', 'ساعة', 'الساعه', 'صباحا', 'صباحاً', 'مساء', 'مساءً',
      'الصبح', 'بالليل', 'الليل',
      'لي', 'لى', 'بكام', 'لحد', 'عشان', 'ورايا', 'وراي',
      'بصوت', 'بنغمة', 'نغمة', 'صوت', 'مرعب', 'ايفون', 'آيفون', 'مشهور', 'صحيان', 'قوي', 'السكرتير', 'السكرتيرة', 'الافتراضي',
      'بالكامل', 'الجدول كله', 'كل الايام', 'كل الأيام', 'طول الاسبوع', 'طول الأسبوع'
    };
    for (final day in _weekDays) {
      stripRaw.add(day);
      stripRaw.add('يوم $day');
      stripRaw.add(day.replaceAll('ال', ''));
      final keywords = _dayKeywords[day] ?? [];
      for (final k in keywords) {
        stripRaw.add(k);
      }
    }
    final strip = stripRaw.map((e) => _norm(e)).toSet();
    final nameNorm = _norm(_secretaryName);
    final kept = <String>[];

    for (final t in rawCommand.split(RegExp(r'\s+'))) {
      final n = _norm(t);
      if (n.isEmpty) continue;
      if (strip.contains(n) || n == nameNorm) continue;

      String nWithoutWaw = n.startsWith('و') ? n.substring(1) : n;
      if (strip.contains(nWithoutWaw)) continue;

      bool isDay = false;
      for (final day in _weekDays) {
        if (_hasAny(nWithoutWaw, _dayKeywords[day] ?? [day])) {
          isDay = true;
          break;
        }
      }
      if (isDay) continue;

      if (RegExp(r'^\d{1,2}(:\d{2})?$').hasMatch(n)) continue;
      if (_hourWords.containsKey(n) || _hourWords.containsKey(nWithoutWaw)) continue;
      if (n == 'ونص' || n == 'وربع' || n == 'وثلث') continue;
      kept.add(t);
    }
    return kept.join(' ').trim();
  }

  Future<void> _processSmartVoiceCommand(String rawCommand) async {
    final userTitle = _userTitle;
    final cmd = _norm(rawCommand);
    final nameNorm = _norm(_secretaryName);
    bool isCalledByName = cmd.contains(nameNorm) || cmd.contains('يا سكرتير') || cmd.contains('يا سكرتيره') || cmd.contains('يا سكرتيرة');

    // 👈 ==========================================
    // 👈 بداية الأوامر الصوتية للإعدادات
    // 👈 ==========================================

    // 1. تغيير اسم السكرتير
    if (_hasAny(cmd, ['غير اسم السكرتير', 'غيري اسم السكرتير', 'غير اسمك', 'غيري اسمك', 'من دلوقتي اسمك', 'خلي اسمك'])) {
      String newName = rawCommand
          .replaceAll(RegExp(r'^(?:يا\s+)?(?:سكرتير|سكرتيرة)\s*'), '')
          .replaceAll(RegExp(r'(?:غير|غيري)\s+اسم(?:ك| السكرتير| السكرتيرة)\s+(?:لـ|إلى|الى)?\s*'), '')
          .replaceAll(RegExp(r'(?:من دلوقتي|من دلوقتى)\s+اسمك\s*'), '')
          .replaceAll(RegExp(r'خلي\s+اسمك\s*'), '')
          .trim();
      if (newName.isNotEmpty) {
        setState(() => _secretaryName = newName);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('secretary_name', newName);
        await _speak("تَمَام $userTitle، مِنْ دِلْوَقْتِي اِسْمِي $newName.");
        return;
      }
    }

    // 2. تغيير نوع السكرتير (ذكر/أنثى)
    if (_hasAny(cmd, ['خليك سكرتير', 'خليك راجل', 'رجع صوتك رجالي', 'خليكي راجل', 'غير نوعك لذكر'])) {
      setState(() {
        _settings.voiceGender = 'ذكر';
        final newNames = _getNamesForGender('ذكر');
        if (!newNames.contains(_secretaryName)) _secretaryName = 'محمد';
      });
      await _saveSettings();
      await _configureVoice(skipGreeting: true);
      await _speak("تَمَام $userTitle، دِلْوَقْتِي أَنَا سِكْرِتِير ذَكَر.");
      return;
    }
    if (_hasAny(cmd, ['خليك سكرتيرة', 'خليك بنت', 'رجع صوتك نسائي', 'خليكي سكرتيرة', 'غير نوعك لانثى', 'غيري نوعك لانثى'])) {
      setState(() {
        _settings.voiceGender = 'أنثى';
        final newNames = _getNamesForGender('أنثى');
        if (!newNames.contains(_secretaryName)) _secretaryName = 'سارة';
      });
      await _saveSettings();
      await _configureVoice(skipGreeting: true);
      await _speak("تَمَام $userTitle، دِلْوَقْتِي أَنَا سِكْرِتِيرَة.");
      return;
    }

    // 3. تغيير لقب المستخدم
    if (_hasAny(cmd, ['غير لقبي', 'غيري لقبي', 'ناديني', 'خلي لقبي', 'خليكي تناديني'])) {
      String newTitle = rawCommand
          .replaceAll(RegExp(r'^(?:يا\s+)?(?:سكرتير|سكرتيرة)\s*'), '')
          .replaceAll(RegExp(r'(?:غير|غيري)\s+لقبي\s+(?:لـ|إلى|الى)?\s*'), '')
          .replaceAll(RegExp(r'(?:ناديني|ناديني)\s*'), '')
          .replaceAll(RegExp(r'خلي(?:كي)?\s+لقبي\s*'), '')
          .trim();
      if (newTitle.isNotEmpty) {
        setState(() => _settings.customUserTitle = newTitle);
        await _saveSettings();
        await _speak("تَمَام $userTitle، مِنْ دِلْوَقْتِي هَنَادِيك $newTitle.");
        return;
      }
    }

    // 4. تغيير لقب السكرتير
    if (_hasAny(cmd, ['غير لقبك', 'غيري لقبك', 'غير لقب السكرتير', 'غيري لقب السكرتير', 'غير لقب السكرتيرة'])) {
      String newTitle = rawCommand
          .replaceAll(RegExp(r'^(?:يا\s+)?(?:سكرتير|سكرتيرة)\s*'), '')
          .replaceAll(RegExp(r'(?:غير|غيري)\s+لقب(?:ك| السكرتير| السكرتيرة)\s+(?:لـ|إلى|الى)?\s*'), '')
          .trim();
      if (newTitle.isNotEmpty) {
        setState(() => _settings.customSecTitle = newTitle);
        await _saveSettings();
        await _speak("تَمَام $userTitle، مِنْ دِلْوَقْتِي لَقَبِي $newTitle.");
        return;
      }
    }

    // 5. سرعة الصوت
    if (_hasAny(cmd, ['خلي سرعة الصوت سريعة', 'خلي الصوت سريع', 'كلمني بسرعة'])) {
      setState(() => _settings.voiceLevel = 'سريع');
      await _saveSettings();
      await _speak("تَمَام $userTitle، خَلِّيتْ سُرْعَة الصَّوْت سَرِيعَة.");
      return;
    }
    if (_hasAny(cmd, ['خلي سرعة الصوت متوسطة', 'خلي الصوت متوسط'])) {
      setState(() => _settings.voiceLevel = 'متوسط');
      await _saveSettings();
      await _speak("تَمَام $userTitle، خَلِّيتْ سُرْعَة الصَّوْت مُتَوَسِّطَة.");
      return;
    }
    if (_hasAny(cmd, ['خلي سرعة الصوت بطيئة', 'خلي الصوت بطيء', 'كلمني بالراحة'])) {
      setState(() => _settings.voiceLevel = 'بطيء');
      await _saveSettings();
      await _speak("تَمَام $userTitle، خَلِّيتْ سُرْعَة الصَّوْت بَطِيئَة.");
      return;
    }

    // 6. تنبيه الأذان
    if (_hasAny(cmd, ['شغل الأذان', 'فعل تنبيه الأذان', 'شغلي الأذان'])) {
      setState(() => _settings.adhanAlertEnabled = true);
      await _saveSettings();
      _scheduleAdhan30Days();
      await _speak("تَمَام $userTitle، تَمَّ تَشْغِيل تَنْبِيهَات الأَذَان.");
      return;
    }
    if (_hasAny(cmd, ['اقفل الأذان', 'الغي الأذان', 'اقفلي الأذان', 'وقف الأذان', 'قفل تنبيه الأذان'])) {
      setState(() => _settings.adhanAlertEnabled = false);
      await _saveSettings();
      await _speak("تَمَام $userTitle، تَمَّ إِلْغَاء تَنْبِيهَات الأَذَان.");
      return;
    }

    // 7. الصلاة على النبي
    if (_hasAny(cmd, ['شغل الصلاة على النبي', 'فعل الصلاة على النبي', 'شغلي الصلاة على النبي'])) {
      setState(() => _settings.salatAlaNabiEnabled = true);
      await _saveSettings();
      _scheduleSalatAlaNabi();
      await _speak("تَمَام $userTitle، تَمَّ تَشْغِيل تَذْكِير الصَّلَاة عَلَى النَّبِيّ.");
      return;
    }
    if (_hasAny(cmd, ['اقفل الصلاة على النبي', 'وقف التذكير', 'اقفلي الصلاة على النبي'])) {
      setState(() => _settings.salatAlaNabiEnabled = false);
      await _saveSettings();
      _scheduleSalatAlaNabi();
      await _speak("تَمَام $userTitle، تَمَّ إِلْغَاء تَذْكِير الصَّلَاة عَلَى النَّبِيّ.");
      return;
    }

    // 8. تغيير الوضع الليلي
    if (_hasAny(cmd, ['شغل الوضع الليلي', 'فعل الوضع الداكن', 'شغلي الوضع الليلي'])) {
      setState(() => _settings.isDarkMode = true);
      await _saveSettings();
      widget.onThemeChanged(true);
      await _speak("تَمَام $userTitle، تَمَّ تَشْغِيل الوَضْع اللَّيْلِيّ.");
      return;
    }
    if (_hasAny(cmd, ['اقفل الوضع الليلي', 'شغل الوضع النهاري', 'اقفلي الوضع الليلي'])) {
      setState(() => _settings.isDarkMode = false);
      await _saveSettings();
      widget.onThemeChanged(false);
      await _speak("تَمَام $userTitle، تَمَّ تَشْغِيل الوَضْع النَّهَارِيّ.");
      return;
    }

    // 9. شاشة القفل
    if (_hasAny(cmd, ['شغل شاشة القفل', 'خلي التطبيق يظهر فوق شاشة القفل', 'شغلي شاشة القفل'])) {
      setState(() => _settings.showAboveLockScreen = true);
      await _saveSettings();
      try { await _lockScreenChannel.invokeMethod('enableShowWhenLocked'); } catch (_) {}
      await _speak("تَمَام $userTitle، التَّطْبِيق هَيَظْهَر فَوْقَ شَاشَة القَفْل.");
      return;
    }
    if (_hasAny(cmd, ['اقفل شاشة القفل', 'خلي التطبيق ميبانش فوق شاشة القفل', 'اقفلي شاشة القفل'])) {
      setState(() => _settings.showAboveLockScreen = false);
      await _saveSettings();
      try { await _lockScreenChannel.invokeMethod('disableShowWhenLocked'); } catch (_) {}
      await _speak("تَمَام $userTitle، التَّطْبِيق مِشْ هَيَظْهَر فَوْقَ شَاشَة القَفْل.");
      return;
    }

    // 10. الهز
    if (_hasAny(cmd, ['شغل الهز', 'فعل الهز', 'شغلي الهز'])) {
      setState(() => _settings.shakeMode = 'app_open');
      await _saveSettings();
      _initShakeDetector();
      await _speak("تَمَام $userTitle، تَمَّ تَشْغِيل الهَز.");
      return;
    }
    if (_hasAny(cmd, ['اقفل الهز', 'وقف الهز', 'اقفلي الهز'])) {
      setState(() => _settings.shakeMode = 'off');
      await _saveSettings();
      _initShakeDetector();
      try { await _shakeChannel.invokeMethod('stopShakeService'); } catch (_) {}
      await _speak("تَمَام $userTitle، تَمَّ إِلْغَاء الهَز.");
      return;
    }
    if (_hasAny(cmd, ['خلي الهز دايماً', 'خلي الهز دائمًا', 'خلي الهز في الخلفية'])) {
      setState(() => _settings.shakeMode = 'always');
      await _saveSettings();
      _initShakeDetector();
      await _speak("تَمَام $userTitle، الهَزْ شَغَّال دَايْمًا.");
      return;
    }

    // 11. إيقاف التسجيل
    if (_hasAny(cmd, ['خلي ايقاف التسجيل بالهز', 'خلي إيقاف التسجيل بالهز'])) {
      setState(() => _settings.stopRecordMode = 'shake_only');
      await _saveSettings();
      await _speak("تَمَام $userTitle، إِيقَاف التَّسْجِيل هَيَكُون بِالهَز.");
      return;
    }
    if (_hasAny(cmd, ['خلي ايقاف التسجيل بالزرار', 'خلي إيقاف التسجيل بالزرار'])) {
      setState(() => _settings.stopRecordMode = 'manual_only');
      await _saveSettings();
      await _speak("تَمَام $userTitle، إِيقَاف التَّسْجِيل هَيَكُون بِالأَزْرَار.");
      return;
    }

    // 12. كلمة السر للنداء
    if (_hasAny(cmd, ['غير كلمة السر', 'غيري كلمة السر', 'غير كلمة النداء'])) {
      String newWord = rawCommand
          .replaceAll(RegExp(r'^(?:يا\s+)?(?:سكرتير|سكرتيرة)\s*'), '')
          .replaceAll(RegExp(r'(?:غير|غيري)\s+كلمة\s+(?:السر|النداء)\s+(?:لـ|إلى|الى)?\s*'), '')
          .trim();
      if (newWord.isNotEmpty) {
        setState(() => _settings.customWakeWord = newWord);
        await _saveSettings();
        await _speak("تَمَام $userTitle، كَلِمَة السِّرْ بَقَتْ $newWord.");
        return;
      }
    }

    // 13. استعادة الإعدادات الافتراضية
    if (_hasAny(cmd, ['استعيد الإعدادات الافتراضية', 'رجع كل حاجة زي الأول', 'امسح الإعدادات', 'استعيدي الإعدادات'])) {
      setState(() {
        _settings = AppSettings();
        _ttsVolume = 1.0;
      });
      await _saveSettings();
      await _configureVoice(skipGreeting: true);
      widget.onThemeChanged(false);
      _initShakeDetector();
      _scheduleAdhan30Days();
      _scheduleSalatAlaNabi();
      await _speak("تَمَام $userTitle، تَمَّتْ اِسْتِعَادَة كُلِّ الإِعْدَادَات الِافْتِرَاضِيَّة.");
      return;
    }

    // 14. تغيير النغمات الافتراضية
    if (_hasAny(cmd, [
      'غير صوت المنبه', 'غيري صوت المنبه', 'خلي صوت المنبه', 'غير نغمة المنبه', 'خلي نغمة المنبه',
      'غير صوت منبه المهام', 'غير نغمة منبه المهام', 'خلي نغمة منبه المهام', 'خلي صوت منبه المهام',
      'خلي النغمة الافتراضية للمهام', 'خلي النغمة الافتراضي للمهام', 'خلي الصوت الافتراضي للمهام',
      'غير النغمة الافتراضية للمهام', 'غير النغمة الافتراضي للمهام', 'غير الصوت الافتراضي للمهام',
      'خلي نغمة المهام', 'غير نغمة المهام', 'خلي صوت المهام', 'غير صوت المهام'
    ])) {
      final sound = _parseSoundFromVoice(cmd);
      if (sound != 'use_default') {
        final prefs = await SharedPreferences.getInstance();
        if (sound == 'secretary') {
          await prefs.remove('default_alarm_sound');
        } else {
          await prefs.setString('default_alarm_sound', sound!);
        }
        setState(() {});
        await _speak("تَمَام $userTitle، خَلِّيتْ نَغْمَة مِنْبِه الْمَهَام ${sound == 'secretary' ? 'صَوْت السِّكْرِتِير' : _getSoundName(sound)}.");
        return;
      } else {
        await _speak("مَعْلِشْ $userTitle، مَفْهَمْتِشْ النَّغْمَة. قُولْ مَثَلًا: مَرْعِب، ايفون، صَحْيَان، أَوْ صَوْت السِّكْرِتِير.");
        return;
      }
    }

    if (_hasAny(cmd, [
      'غير صوت الجدول', 'غيري صوت الجدول', 'خلي صوت الجدول', 'غير نغمة الجدول', 'خلي نغمة الجدول',
      'غير صوت منبه الجدول', 'خلي صوت منبه الجدول', 'غير نغمة منبه الجدول', 'خلي نغمة منبه الجدول',
      'خلي النغمة الافتراضية للجدول', 'خلي الصوت الافتراضي للجدول', 'غير النغمة الافتراضية للجدول',
      'غير النغمة الافتراضية للجدول الأسبوعي', 'خلي نغمة الجدول الأسبوعي'
    ])) {
      final sound = _parseSoundFromVoice(cmd);
      if (sound != 'use_default') {
        final prefs = await SharedPreferences.getInstance();
        if (sound == 'secretary') {
          await prefs.remove('default_weekly_sound');
        } else {
          await prefs.setString('default_weekly_sound', sound!);
        }
        setState(() {});
        await _speak("تَمَام $userTitle، خَلِّيتْ نَغْمَة مِنْبِه الْجَدْوَل ${sound == 'secretary' ? 'صَوْت السِّكْرِتِير' : _getSoundName(sound)}.");
        return;
      } else {
        await _speak("مَعْلِشْ $userTitle، مَفْهَمْتِشْ النَّغْمَة. قُولْ مَثَلًا: مَرْعِب، ايفون، صَحْيَان، أَوْ صَوْت السِّكْرِتِير.");
        return;
      }
    }

    if (_hasAny(cmd, [
      'غير صوت المناسبات', 'غيري صوت المناسبات', 'خلي صوت المناسبات', 'غير نغمة المناسبات', 'خلي نغمة المناسبات',
      'خلي النغمة الافتراضية للمناسبات', 'خلي الصوت الافتراضي للمناسبات', 'غير النغمة الافتراضية للمناسبات',
      'غير نغمة منبه المناسبات', 'خلي نغمة منبه المناسبات'
    ])) {
      final sound = _parseSoundFromVoice(cmd);
      if (sound != 'use_default') {
        final prefs = await SharedPreferences.getInstance();
        if (sound == 'secretary') {
          await prefs.remove('default_event_sound');
        } else {
          await prefs.setString('default_event_sound', sound!);
        }
        setState(() {});
        await _speak("تَمَام $userTitle، خَلِّيتْ نَغْمَة الْمُنَاسَبَات ${sound == 'secretary' ? 'صَوْت السِّكْرِتِير' : _getSoundName(sound)}.");
        return;
      } else {
        await _speak("مَعْلِشْ $userTitle، مَفْهَمْتِشْ النَّغْمَة. قُولْ مَثَلًا: مَرْعِب، ايفون، صَحْيَان، أَوْ صَوْت السِّكْرِتِير.");
        return;
      }
    }

    // 👈 التعرف العالمي على أوامر إيقاف التسجيل
    if (_hasAny(cmd, [
      'وقف تسجيل', 'وقف التسجيل', 'وقفي تسجيل', 'وقفي التسجيل',
      'اوقف تسجيل', 'اوقف التسجيل', 'أوقف تسجيل', 'أوقف التسجيل',
      'خلص تسجيل', 'خلص التسجيل', 'خلصت تسجيل', 'خلصت التسجيل',
      'انهي التسجيل', 'انهي تسجيل', 'أنهي التسجيل', 'بطل تسجيل', 'بطل التسجيل',
      'اقفل التسجيل', 'اقفلي التسجيل', 'كفاية تسجيل', 'كفاية التسجيل', 'ستوب', 'stop'
    ])) {
      bool stopped = false;
      if (_isRecording) {
        await _stopRecording();
        stopped = true;
      }
      if (_DiaryPageState.activeInstance != null) {
        _DiaryPageState.activeInstance!.stopRecordingByVoice();
        stopped = true;
      }

      if (stopped) {
        await _speak("تَمَّ إِيقَافُ التَّسْجِيل $_userTitle.");
      } else {
        await _speak("مَفِيشْ تَسْجِيل شَغَّال دِلْوَقْتِي $_userTitle.");
      }
      return;
    }

// ══════════════════════════════════════════════════════
// نهاية PART 5 / 8
// ═════════════════════════════════════════════════════
    // ══════════════════════════════════════════════════════
// PART 6 / 8
// _processSmartVoiceCommand (تكملة) + التعديل ب (قراءة المواقيت
// والوقت المتبقي والصلاة الجاية) + التعديل أ (منبه الصلاة)
// + _getTasksForDate + _deleteAllRecurringTasks
// + _listTodayTasks + _listWeeklySchedule + _listDayTasks
// ══════════════════════════════════════════════════════

    // 0. الحوار الذكي (خطوة بخطوة) للمناسبات
    if (_pendingVoiceAction != null && _pendingVoiceAction!.startsWith('event_')) {
      if (_hasAny(cmd, ['إلغاء', 'الغي', 'خلاص', 'كفاية'])) { _pendingVoiceAction = null; _pendingEventData = null; await _speak("تَمَّ إِلْغَاءُ إِضَافَةِ المُنَاسَبَةِ $_userTitle."); return; }
      if (_pendingVoiceAction == 'event_name') { _pendingEventData!['title'] = rawCommand; _pendingVoiceAction = 'event_date'; await _speak("تَمَام $_userTitle. تَارِيخُ المُنَاسَبَةِ إِيهْ؟"); _listenVoiceCommand(); return; }
      if (_pendingVoiceAction == 'event_date') {
        final parsedDate = _parseDiaryDate(cmd);
        if (parsedDate != null) { _pendingEventData!['eventDate'] = parsedDate.toIso8601String(); } else { await _speak("مَعْلِشْ مَفْهَمْتِشْ التَّارِيخْ $_userTitle."); _listenVoiceCommand(); return; }
        _pendingVoiceAction = 'event_time'; await _speak("السَّاعَةِ كَامْ $_userTitle؟"); _listenVoiceCommand(); return;
      }
      if (_pendingVoiceAction == 'event_time') {
        final hour = _parseHour(cmd); final minute = _parseMinute(cmd);
        if (hour != null) { _pendingEventData!['reminderHour'] = hour; _pendingEventData!['reminderMinute'] = minute; _pendingVoiceAction = 'event_advance'; await _speak("التَّذْكِيرُ قَبْلَهَا بِقَدْ إِيهْ؟"); _listenVoiceCommand(); return; } else { await _speak("مَفْهَمْتِشْ السَّاعَة $_userTitle."); _listenVoiceCommand(); return; }
      }
      if (_pendingVoiceAction == 'event_advance') {
        String advance = 'قبلها بيوم';
        if (_hasAny(cmd, ['نفس اليوم', 'في نفس اليوم'])) advance = 'في نفس اليوم';
        else if (_hasAny(cmd, ['اسبوع', 'أسبوع'])) advance = 'قبلها بأسبوع';
        _pendingEventData!['advanceReminder'] = advance; _pendingEventData!['repeatInterval'] = 'مرة واحدة'; _pendingEventData!['repeatType'] = 'سنوي'; _pendingEventData!['sound'] = null;
        setState(() { _specialEvents.add(_pendingEventData!); }); _saveData(); _scheduleEventReminder(_pendingEventData!);
        await _speak("تَمَّتْ إِضَافَةُ مُنَاسَبَةِ: ${_pendingEventData!['title']} بِنَجَاح $_userTitle.");
        _pendingVoiceAction = null; _pendingEventData = null; return;
      }
    }

    // 1. تأكيد تداخل المواعيد
    if (_pendingVoiceAction == 'confirm_time_conflict') {
      _pendingActionTimer?.cancel();
      if (_hasAny(cmd, ['احفظ', 'حفظ', 'احفظهم', 'خليهم', 'سيبهم', 'موافق', 'ايوه', 'أيوة', 'تمام', 'ماشي', 'احفظهم الاتنين'])) {
        _handleConflictResolution(true);
      } else {
        _handleConflictResolution(false);
      }
      return;
    }

    // 2. تأكيد مسح كل اليوميات
    if (_pendingVoiceAction == 'confirm_delete_all_diaries') {
      _pendingActionTimer?.cancel();
      _pendingVoiceAction = null;
      if (_hasAny(cmd, ['ايوه', 'أيوة', 'تمام', 'موافق', 'امسح'])) {
        setState(() {
          _diaries.clear();
        });
        await _saveData();
        await _speak("تَمَّ مَسْحُ كُلِّ اليَوْمِيَّاتِ بِنَجَاح $_userTitle.");
      } else {
        await _speak("تَمَّ إِلْغَاءُ المَسْح $_userTitle.");
      }
      return;
    }

    // 3. إلغاء الحوار
    if (_hasAny(cmd, ['خلاص', 'إلغاء', 'الغي', 'كفاية', 'كفايه'])) {
      if (_pendingVoiceAction != null) {
        _pendingVoiceAction = null;
        _pendingRawCommand = null;
        _pendingActionTimer?.cancel();
        await _speak("تَمَام $_userTitle، لَغِيت الأَمْر.");
        return;
      }
    }

    // 4. متابعة الحوار
    if (_pendingVoiceAction != null && _pendingRawCommand != null) {
      final combined = '$_pendingRawCommand $rawCommand';
      final action = _pendingVoiceAction;
      _pendingVoiceAction = null;
      _pendingRawCommand = null;
      _pendingActionTimer?.cancel();

      if (action == 'alarm_time') {
        await _createAlarmFromVoice(combined, _norm(combined));
        return;
      } else if (action == 'weekly_day' || action == 'weekly_time') {
        await _createWeeklyAlarmFromVoice(combined, _norm(combined));
        return;
      }
    }

    // 5. أوامر اليوميات
    final isWritingToDiary = _hasAny(cmd, [
      'اكتب في اليوميات', 'اكتب في يومياتي', 'سجل في اليوميات', 'سجل في يومياتي',
      'اكتب يومية', 'سجل يومية', 'سجل عندك في يومية',
      'اكتب عندك في يومية', 'اكتب عندك', 'اكتبلي في يومية', 'اكتبلي يومية', 'سجللي يومية',
      'سجل عندك', 'اكتب في المذكرة', 'سجل في المذكرة', 'اكتبي عندك', 'اكتبي', 'اكتب', 'سجلي', 'سجل'
    ]);

    // 1. طلب الباسورد الصوتي لليوميات
if (_pendingVoiceAction == 'diary_pin_auth') {
  _pendingActionTimer?.cancel();
  _pendingVoiceAction = null;

  String spokenPin = cmd.replaceAll(RegExp(r'[^0-9]'), '');
  
  if (spokenPin.isEmpty) {
    String wordPin = cmd;
    final words = {'صفر':'0','زيرو':'0','واحد':'1','واحدة':'1','اتنين':'2','اثنين':'2','تلاتة':'3','ثلاثة':'3','اربعة':'4','أربعة':'4','خمسة':'5','سته':'6','ستة':'6','سبعة':'7','تمانية':'8','ثمانية':'8','تسعة':'9'};
    words.forEach((k, v) { wordPin = wordPin.replaceAll(k, v); });
    spokenPin = wordPin.replaceAll(RegExp(r'[^0-9]'), '');
  }

  if (spokenPin == _settings.diaryPin && _settings.diaryPin.isNotEmpty) {
    _voiceDiaryAuthTemp = true;
    await _speak("تَمَام $_userTitle، تَمَّ فَتْحُ القَفْل.");
    if (_pendingRawCommand != null) {
      final originalCmd = _pendingRawCommand!;
      _pendingRawCommand = null;
      await _processSmartVoiceCommand(originalCmd);
    }
  } else {
    await _speak("مَعْلِشْ $_userTitle، كَلِمَة السِّرْ غَلَط.");
    _pendingRawCommand = null;
  }
  return;
}

// 2. سد ثغرة الأوامر الصوتية لليوميات (لو مقفولة)
final bool isDiaryLocked = _settings.diaryLockEnabled && _settings.diaryPin.isNotEmpty && _DiaryPageState.activeInstance == null && !_voiceDiaryAuthTemp;
final bool isDiaryRelatedCommand = isWritingToDiary || 
    _hasAny(cmd, [
      'يوميات', 'يوميه', 'يومية', 'اليوميات', 'مفكره', 'مفكرة', 'مذكرة', 'مذكرتي',
      'اقرا يومية', 'اقرا يوميات', 'قولي يومية', 'اللي في يومية', 'اقرالي يومية', 'اقرا اليومية', 'قولي اليومية',
      'امسح اليومية', 'امسح اليوميه', 'افرغ اليومية', 'مسح اليومية', 'امسح كل حاجه في اليومية', 'امسح كل اليوميات', 'امسح اليوميات كلها', 'احذف كل اليوميات', 'افرغ كل اليوميات'
    ]);

if (isDiaryLocked && isDiaryRelatedCommand) {
  _pendingVoiceAction = 'diary_pin_auth';
  _pendingRawCommand = rawCommand;
  _pendingActionTimer?.cancel();
  _pendingActionTimer = Timer(const Duration(seconds: 15), () {
    _pendingVoiceAction = null;
    _pendingRawCommand = null;
    _voiceDiaryAuthTemp = false;
  });
  await _speak("اليَوْمِيَّات مَقْفُولَة $_userTitle. قُولِي كَلِمَة السِّرْ بَصَوْتَك، أَوِ افْتَحْهَا مِنَ التَّطْبِيق.");
  _listenVoiceCommand();
  return;
}

    if (!isWritingToDiary && _hasAny(cmd, ['يوميات', 'يوميه', 'يومية', 'مفكره', 'مفكرة'])) {
      if (_DiaryPageState.activeInstance == null) {
        _openDiaryPage(DateTime.now());
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (_DiaryPageState.activeInstance != null) {
        if (_hasAny(cmd, ['ضيف مهمة', 'ضيفي مهمة', 'حط مهمة', 'أضف مهمة', 'ضيفلي مهمة', 'ضيفيلي مهمة'])) {
          String text = rawCommand.trim();
          text = text.replaceFirst(RegExp(r'^(?:(?:يا\s+)?(?:سكرتير|سكرتيرة)\s+)?(?:ضيف|ضيفي|حط|أضف|اضف|ضيفلي|ضيفيلي)\s+(?:مهمة\s+)?'), '');
          text = text.replaceFirst(RegExp(r'^(?:في\s+)?(?:اليوميات|يومياتي|يوميتي|يومية|مفكرة|المفكرة)\s+'), '');
          text = text.replaceAll(RegExp(r'\s+(?:يا\s+)?(?:سكرتير|سكرتيرة)\s*$'), '');
          text = text.trim();
          _diaryVoiceStream.add({'action': 'add_todo', 'text': text.isEmpty ? 'مهمة جديدة' : text});
          await _speak("تَمَام $_userTitle، ضِفْتْ المُهِمَّة فِي اليَوْمِيَّة.");
          return;
        }
        if (_hasAny(cmd, ['اكتب', 'سجل نص', 'ضيف ملاحظة', 'اكتبلي'])) {
          String text = rawCommand.replaceFirst(RegExp(r'^(?:(?:يا\s+)?(?:سكرتير|سكرتيرة)\s+)?(?:اكتب|سجل|ضيف|اكتبلي|سجلي)\s+(?:ملاحظة\s+)?'), '');
          text = text.replaceAll(RegExp(r'\s+(?:في|على)\s+(?:اليوميات|يومياتي|يوميتي|يومية|مفكرة|المفكرة)\s*'), ' ');
          text = _cleanDateWordsFromText(text);

          if (text.isNotEmpty) {
            _diaryVoiceStream.add({'action': 'add_text_note', 'text': text});
            await _speak("تَمَام $_userTitle، كَتَبْتْ النَّصْ.");
            return;
          }
        }
        if (_hasAny(cmd, ['خلصت رقم', 'عملت رقم', 'تم رقم', 'done رقم'])) {
          final m = RegExp(r'رقم\s*(\d+)').firstMatch(rawCommand);
          if (m != null) {
            final idx = int.parse(m.group(1)!) - 1;
            _diaryVoiceStream.add({'action': 'mark_done', 'index': idx});
            await _speak("تَمَام $_userTitle، عَلَّمْتْ عَلَى المُهِمَّة رَقْم ${idx + 1}.");
            return;
          }
        }
        if (_hasAny(cmd, ['ضيف صورة', 'ضيفي صورة', 'أضف صورة'])) {
          _diaryVoiceStream.add({'action': 'add_image'});
          await _speak("اخْتَارْ الصُّورَة يَا $_userTitle.");
          return;
        }
        if (_hasAny(cmd, ['وقف تسجيل', 'وقفي تسجيل', 'خلصت تسجيل', 'انهي تسجيل', 'انهي التسجيل'])) {
          _diaryVoiceStream.add({'action': 'stop_recording'});
          await _speak("تَمَّ إِيقَافُ التَّسْجِيل.");
          return;
        }
        if (_hasAny(cmd, ['سجل صوت', 'سجلي صوت', 'ابدأ تسجيل', 'ابدأ التسجيل'])) {
          _diaryVoiceStream.add({'action': 'start_recording'});
          await _speak("بَدَأْتْ التَّسْجِيل يَا $_userTitle.");
          return;
        }
        if (_hasAny(cmd, ['امسح اليومية', 'امسح اليوميه', 'افرغ اليومية', 'مسح اليومية', 'امسح كل حاجه في اليومية'])) {
  if (_settings.diaryLockEnabled && _settings.diaryPin.isNotEmpty && !_voiceDiaryAuthTemp) {
    await _speak("مَعْلِشْ $_userTitle، اليَوْمِيَّات مَقْفُولَة. لَازِمْ تِفْتَحْهَا الأَوَّل.");
    return;
  }
  _diaryVoiceStream.add({'action': 'clear_all'});
  await _speak("تَمَّ مَسْحُ كُلِّ مَحْتُوِيَّاتِ اليَوْمِيَّةِ $_userTitle.");
  return;
        }
        if (_hasAny(cmd, ['اقرا اليوميات', 'قولي اليوميات', 'اللي في اليوميات'])) {
          final readableText = _DiaryPageState.activeInstance!.getReadableText();
          await _speak(readableText.isEmpty ? "اليَوْمِيَّة فَاضْيَة $_userTitle." : readableText);
          return;
        }
        if (_hasAny(cmd, ['امسح اخر مهمة', 'احذف اخر مهمة'])) {
          _diaryVoiceStream.add({'action': 'delete_last_task'});
          await _speak("تَمَّ مَسْحُ آخِرْ مُهِمَّة $_userTitle.");
          return;
        }
        if (_hasAny(cmd, ['عدل مهمة', 'عدل المهمة', 'عدلي مهمة', 'تعديل مهمة', 'عدل ملاحظة', 'عدل الملاحظة'])) {
          final numMatch = RegExp(r'رقم\s*(\d+)').firstMatch(rawCommand);
          if (numMatch != null) {
            final taskNum = int.parse(numMatch.group(1)!);
            String newText = rawCommand
                .replaceFirst(RegExp(r'^(?:(?:يا\s+)?(?:سكرتير|سكرتيرة)\s+)?(?:عدل|عدلي)\s+(?:مهمة|المهمة|ملاحظة|الملاحظة)\s+رقم\s*\d+\s*(?:خليها|خليه|لـ|إلى|الى)\s*'), '')
                .trim();
            if (newText.isNotEmpty) {
              _diaryVoiceStream.add({'action': 'edit_task_by_number', 'index': taskNum - 1, 'text': newText});
              await _speak("تَمَام $_userTitle، تَمَّ تَعْدِيلُ المَهَامِّ رَقْم $taskNum.");
              return;
            }
          }
        }

        if (_hasAny(cmd, ['امسح كل اليوميات', 'امسح اليوميات كلها', 'احذف كل اليوميات', 'افرغ كل اليوميات'])) {
          await _speak("هَلْ أَنْتَ مُتَأَكِّدٌ أَنَّكَ تُرِيدُ مَسْحَ كُلِّ اليَوْمِيَّاتِ $_userTitle؟ قُلْ أَيْوَة لِلتَّأْكِيد.");
          _pendingVoiceAction = 'confirm_delete_all_diaries';
          _listenVoiceCommand();
          return;
        }

        final requestedDate = _parseDiaryDate(cmd);
        if (requestedDate != null) {
          _openDiaryPage(requestedDate);
          await _speak("تَمَّ فَتْحُ يَوْمِيَّةِ ${DateFormat('EEEE، dd MMMM', 'ar').format(requestedDate)} $_userTitle.");
        } else {
          setState(() => _currentIndex = 1);
          await _speak("تَمَّ فَتْحُ قِسْمِ اليَوْمِيَّاتِ $_userTitle، اخْتَارْ اليَوْمَ اللي تِحِبَّهْ.");
        }
        return;
      }
    }

    // 6. إيقاف المنبه
    if (_hasAny(cmd, ['خلاص', 'صحيت', 'صحيتي', 'قومت', 'قومتي', 'فوقت', 'فوقتي', 'اقفل', 'اقفلي', 'كفاية', 'كفايه', 'إيقاف', 'ايقاف', 'إلغاء', 'الغي', 'بس'])) {
      if (_isAlarmDialogOpen) {
        _activeAlarmLoopTimer?.cancel();
        _alarmVoiceSafetyTimer?.cancel();
        _alarmVoiceSafetyTimer = null;
        if (_activeAlarmLoopTimer != null) _activeTimers.remove(_activeAlarmLoopTimer!);
        _activeAlarmLoopTimer = null;

        _tts.stop();
        try { _soundChannel.invokeMethod('stopPreview'); } catch (_) {}
        WakelockPlus.disable();
        _isAlarmDialogOpen = false;

        final stoppedTitle = _activeAlarmTitle;
        final stoppedRepeat = _activeAlarmRepeat;
        final stoppedInterval = _activeAlarmInterval;
        final stoppedCustomDays = List<String>.from(_activeAlarmCustomDays);
        final stoppedScheduled = _activeAlarmScheduledTime;
        final stoppedSound = _activeAlarmSoundUri;
        final stoppedCtx = _alarmDialogContext;

        _activeAlarmTitle = null;
        _alarmDialogContext = null;

        if (stoppedTitle != null) {
          try { await _notifications.cancel(stoppedTitle.hashCode + 1000); } catch (_) {}
        }
        try { await _nativeAlarmChannel.invokeMethod('stopAlarmService'); } catch (_) {}

        if (stoppedTitle != null) {
          if (stoppedRepeat == 'مرة واحدة' || stoppedRepeat == null) {
            final idx = _tasks.indexWhere((t) => t['task'] == stoppedTitle);
            if (idx != -1) {
              setState(() => _tasks.removeAt(idx));
              _saveData();
            }
            try { await _cancelNativeAlarm(stoppedTitle); } catch (_) {}
          } else if (stoppedScheduled != null) {
            _rescheduleRepeating(stoppedTitle, stoppedRepeat!, stoppedInterval ?? 'بدون تنبيه', stoppedCustomDays, stoppedScheduled, stoppedSound);
          }
        }
        SharedPreferences.getInstance().then((p) => p.remove('pending_alarm'));
        if (stoppedCtx != null) {
          try { Navigator.of(stoppedCtx).pop(); } catch (_) {}
        }
        await _speak("تَمَّ إِيقَافُ المُنَبِّه $_userTitle");
        return;
      }
    }

    // 7. تأجيل المنبه
    if (_hasAny(cmd, [
      'فكرني', 'أجله', 'أجلي', 'صحيني', 'نومة', 'قيلولة', 'استنى', 'استني',
      '5 دقايق', 'خمس دقايق', '10 دقايق', 'عشر دقايق', 'عشر دقائق',
      'ربع ساعة', 'تلت ساعة', 'ثلث ساعة', 'نص ساعة', 'نصف ساعة', 'نصايه',
      '20 دقيقة', 'عشرين دقيقة', 'ساعة'
    ])) {
      if (_isAlarmDialogOpen || _activeAlarmTitle != null) {
        int minutes = 5;

        if (cmd.contains('نص ساعه') || cmd.contains('نصف ساعه') || cmd.contains('نصايه')) minutes = 30;
        else if (cmd.contains('ربع ساعه')) minutes = 15;
        else if (cmd.contains('تلت ساعه') || cmd.contains('ثلث ساعه')) minutes = 20;
        else if (cmd.contains('ساعه ونص') || cmd.contains('ساعة ونص') || cmd.contains('ساعه ونصف')) minutes = 90;
        else if (cmd.contains('ساعه وربع') || cmd.contains('ساعة وربع')) minutes = 75;
        else if (cmd.contains('ساعه وتلت') || cmd.contains('ساعة وتلت') || cmd.contains('ساعه وثلث')) minutes = 80;
        else if (cmd.contains('ساعه وخمس') || cmd.contains('ساعة وخمس')) minutes = 65;
        else if (cmd.contains('ساعه وعشر') || cmd.contains('ساعة وعشر')) minutes = 70;
        else if (cmd.contains('ساعه الا خمس') || cmd.contains('ساعة الا خمس')) minutes = 55;
        else if (cmd.contains('ساعه الا عشر') || cmd.contains('ساعة الا عشر')) minutes = 50;
        else if (cmd.contains('ساعه الا ربع') || cmd.contains('ساعة الا ربع')) minutes = 45;
        else if (cmd.contains('ساعه الا تلت') || cmd.contains('ساعة الا تلت')) minutes = 40;
        else if (cmd.contains('ساعه الا نص') || cmd.contains('ساعة الا نص')) minutes = 30;
        else if (cmd.contains('ساعتين') || cmd.contains('ساعتان')) minutes = 120;
        else if (cmd.contains('تلات ساعات') || cmd.contains('ثلاث ساعات') || cmd.contains('3 ساعات')) minutes = 180;
        else if (cmd.contains('اربع ساعات') || cmd.contains('أربع ساعات') || cmd.contains('4 ساعات')) minutes = 240;
        else if (cmd.contains('ساعه')) minutes = 60;
        else if (cmd.contains('خمستاشر') || cmd.contains('خمسه عشر') || cmd.contains('خمسة عشر') || cmd.contains('15')) minutes = 15;
        else if (cmd.contains('تلاتين') || cmd.contains('ثلاثين') || cmd.contains('30')) minutes = 30;
        else if (cmd.contains('خمسه واربعين') || cmd.contains('خمسة وأربعين') || cmd.contains('45')) minutes = 45;
        else if (cmd.contains('عشرين') || cmd.contains('20')) minutes = 20;
        else if (cmd.contains('عشر') || cmd.contains('10')) minutes = 10;
        else if (cmd.contains('خمسه') || cmd.contains('خمس') || cmd.contains('5')) minutes = 5;
        else if (cmd.contains('دقيقتين')) minutes = 2;

        final originalTitle = _activeAlarmTitle ?? 'المنبه';
        final snoozeTime = DateTime.now().add(Duration(minutes: minutes));
        final snoozeTimestamp = DateTime.now().millisecondsSinceEpoch;

        _scheduleContinuousAlarm(
          originalTitle,
          snoozeTime,
          'مرة واحدة',
          'كل 10 ثواني',
          [],
          customId: snoozeTimestamp,
          customNotificationId: snoozeTimestamp + 1000000,
          soundUri: _activeAlarmSoundUri,
        );

        if (_activeAlarmRepeat != null && _activeAlarmRepeat != 'مرة واحدة' && _activeAlarmScheduledTime != null) {
          _rescheduleRepeating(
            originalTitle,
            _activeAlarmRepeat!,
            _activeAlarmInterval ?? 'بدون تنبيه',
            _activeAlarmCustomDays,
            _activeAlarmScheduledTime!,
            _activeAlarmSoundUri
          );
        }

        if (_isAlarmDialogOpen) {
          _activeAlarmLoopTimer?.cancel();
          _alarmVoiceSafetyTimer?.cancel();
          _alarmVoiceSafetyTimer = null;
          _tts.stop();
          WakelockPlus.disable();
          if (_alarmDialogContext != null) Navigator.pop(_alarmDialogContext!);
          _isAlarmDialogOpen = false;
          _activeAlarmTitle = null;
          _alarmDialogContext = null;
        }

        String timeText;
        if (minutes == 30) {
          timeText = 'نص ساعة';
        } else if (minutes == 60) {
          timeText = 'ساعة';
        } else if (minutes == 20) {
          timeText = 'تلت ساعة';
        } else if (minutes == 1) {
          timeText = 'دقيقة واحدة';
        } else if (minutes == 2) {
          timeText = 'دقيقتين';
        } else if (minutes >= 3 && minutes <= 10) {
          timeText = '$minutes دقائق';
        } else {
          timeText = '$minutes دقيقة';
        }
        await _speak("حَاضِرْ $_userTitle، هَفَكَّرَكْ تَانِي عَلَى $originalTitle بَعْد $timeText.");
        return;
      }
    }

    // 8. إضافة مناسبة شات (جملة واحدة)
    if (_hasAny(cmd, ['ضيف مناسبة', 'اضف مناسبة', 'ضيفي مناسبة', 'اضيفي مناسبة', 'عايز اضيف مناسبة', 'عايزة اضيف مناسبة', 'ضيفلي مناسبة', 'ضيفلي مناسبه', 'فكرني بمناسبة', 'فكرني ب مناسبة', 'مناسبة', 'مناسبه'])) {
      DateTime? parsedEventDate = _parseFullDate(cmd);
      int? eventDay = parsedEventDate?.day;
      int? hour = _parseHour(cmd);
      int minute = _parseMinute(cmd);
      String advance = 'قبلها بيوم';
      if (_hasAny(cmd, ['قبلها بأسبوع', 'قبلها اسبوع'])) advance = 'قبلها بأسبوع';

      String title = rawCommand;
      final removeWords = ['ضيف', 'مناسبة', 'فكرني', 'ذكرني', 'يوم', 'الساعة', 'الساعه', 'مساء', 'مساءً', 'صباحا', 'صباحاً', 'قبلها', 'بيوم', 'بأسبوع', 'اسبوع', 'أيام', 'ايام', 'في', 'نفس', 'اليوم', 'يا', 'سكرتير', 'سكرتيرة', 'يناير','فبراير','مارس','ابريل','أبريل','مايو','يونيو','يوليو','اغسطس','أغسطس','سبتمبر','اكتوبر','أكتوبر','نوفمبر','ديسمبر'];
      for (var w in removeWords) { title = title.replaceAll(w, ''); }
      title = title.replaceAll(RegExp(r'\d+'), '').trim();

      if (title.isEmpty) title = 'مناسبة';

      if (parsedEventDate == null || hour == null) {
        _pendingEventData = {'title': title};
        _pendingVoiceAction = 'event_date';
        await _speak("حَاضِرْ $_userTitle، التَّارِيخِ أَوِ الوَقْتِ مُشْ وَاضِحْ. تَارِيخُ المُنَاسَبَةِ إِيهْ؟");
        _listenVoiceCommand();
        return;
      }
      if (hour < 12 && _hasAny(cmd, ['مساء', 'بالليل', 'الليل'])) hour += 12;

      final newEvent = {'title': title, 'detail': 'مناسبة سنوية', 'phone': '', 'advanceReminder': advance, 'eventDate': parsedEventDate.toIso8601String(), 'reminderHour': hour, 'reminderMinute': minute, 'repeatInterval': 'مرة واحدة', 'repeatType': 'سنوي', 'sound': 'default'};
      setState(() { _specialEvents.add(newEvent); }); _sortByTime(_specialEvents); _saveData(); _scheduleEventReminder(newEvent);
      final formattedHour = hour % 12 == 0 ? 12 : hour % 12;
      final period = hour >= 12 ? 'مَسَاءً' : 'صَبَاحاً';
      await _speak("تَمَّتْ إِضَافَةُ: $title يَوْمْ $eventDay السَّاعَة $formattedHour $period، وَالتَّذْكِيرُ $advance $_userTitle.");
      return;
    }

    // 9. تعديل موعد شات (جملة واحدة)
    if (_hasAny(cmd, ['عدل موعد', 'عدلي موعد', 'تعديل موعد', 'غير موعد', 'غيري موعد'])) {
      String searchTerm = cmd.replaceAll('عدل', '').replaceAll('موعد', '').replaceAll('غير', '').trim();
      searchTerm = searchTerm.split('وخليه').first.trim(); searchTerm = searchTerm.split('الساعة').first.trim();
      if (searchTerm.isEmpty) { await _speak("قُولِّي أَعَدِّلْ أَنَّهِي مَوْعِدْ $_userTitle؟"); return; }
      final matches = _tasks.where((t) { final taskName = _norm(t['task'].toString()); return taskName.contains(_norm(searchTerm)) || _norm(searchTerm).contains(taskName); }).toList();
      if (matches.isEmpty) { await _speak("مَفِيشْ مَوْعِدْ بِالاِسْمْ دَهْ $_userTitle."); return; }

      final task = matches.first; final index = _tasks.indexOf(task);
      final newHour = _parseHour(cmd);
      if (newHour == null) { await _speak("مَفْهَمْتِشْ الوَقْتْ الجَدِيدْ $_userTitle."); return; }

      final newMinute = _parseMinute(cmd);
      DateTime newDate = DateTime.parse(task['scheduled']);
      if (cmd.contains('بكره') || cmd.contains('بكرة')) { newDate = newDate.add(const Duration(days: 1)); }
      final scheduled = DateTime(newDate.year, newDate.month, newDate.day, newHour, newMinute);

      setState(() { _tasks[index] = {...task, 'scheduled': scheduled.toIso8601String(), 'time': DateFormat('hh:mm a', 'ar').format(scheduled)}; });
      _saveData(); await _cancelNativeAlarm(task['task'].toString());
      if (task['repeatInterval'] != 'بدون تنبيه') { _scheduleContinuousAlarm(task['task'].toString(), scheduled, task['repeat'] ?? 'مرة واحدة', task['repeatInterval'] ?? 'بدون تنبيه', List<String>.from(task['customDays'] ?? []), soundUri: task['sound']); }
      await _speak("تَمَّ تَعْدِيلُ مَوْعِدْ ${task['task']} إِلَى السَّاعَة ${newHour}:${newMinute.toString().padLeft(2, '0')} $_userTitle.");
      return;
    }

    // 10. قراءة اليوميات
    if (_hasAny(cmd, ['اقرا يومية', 'اقرا يوميات', 'قولي يومية', 'اللي في يومية', 'اقرالي يومية', 'اقرا اليومية', 'قولي اليومية'])) {
      final targetDate = _parseDiaryDate(cmd) ?? DateTime.now();
      final key = DateFormat('yyyy-MM-dd').format(targetDate);
      if (_diaries.containsKey(key)) {
        final data = _diaries[key]; String readable = "";
        if (data['text'] != null && data['text'].toString().isNotEmpty) readable += "النَّصْ: ${data['text']}. ";
        if (data['entries'] != null) {
          final entries = List<Map<String, dynamic>>.from(data['entries']);
          if (entries.isNotEmpty) {
            readable += "وَالمُحْتَوَيَاتْ: ";
            for (var e in entries) { if (e['type'] == 'todo') readable += "مُهِمَّة: ${e['content']} ${e['done'] == true ? '(تَمَّتْ)' : '(لَمْ تَتِمَّ)'}. "; if (e['type'] == 'image') readable += "صُورَة. "; if (e['type'] == 'audio') readable += "تَسْجِيلٌ صَوْتِيٌّ. "; }
          }
        }
        await _speak(readable.trim().isNotEmpty ? readable : "اليَوْمِيَّةُ فَاضْيَة يَا $_userTitle.");
      } else { await _speak("مَفِيشْ يَوْمِيَّة مَكْتُوبَة فِي اليَوْمَ دَه يَا $_userTitle."); }
      return;
    }

    // 11. كتابة اليوميات
    if (isWritingToDiary) {
      String textToWrite = rawCommand;
      final removeWords = ['اكتب', 'اكتبي', 'اكتبلي', 'سجل', 'سجلي', 'سجللي', 'في', 'اليوميات', 'يومياتي', 'يوميتي', 'يومية', 'يوميه', 'يا', 'سكرتير', 'سكرتيرة', 'عندك', 'عندي'];
      for (var w in removeWords) { textToWrite = textToWrite.replaceAll(w, ''); }
      textToWrite = _cleanDateWordsFromText(textToWrite);

      if (textToWrite.isNotEmpty) {
        if (_DiaryPageState.activeInstance != null) {
          _diaryVoiceStream.add({'action': 'add_text_note', 'text': textToWrite});
          await _speak("تَمَام $_userTitle، كَتَبْتْ النَّصْ فِي اليَوْمِيَّة الْمَفْتُوحَة.");
        } else {
          DateTime targetDate = _parseDiaryDate(cmd) ?? DateTime.now();
          final key = DateFormat('yyyy-MM-dd').format(targetDate);
          final existing = _diaries[key] ?? {'text': '', 'entries': []};
          existing['text'] = (existing['text'] ?? '') + '\n' + textToWrite;
          setState(() => _diaries[key] = existing); _saveData();
          await _speak("تَمَّ كِتَابَةُ اليَوْمِيَّةِ بِنَجَاح $_userTitle.");
        }
      } else {
        if (mounted) _openDiaryPage(DateTime.now());
        await _speak("اتْفَضَّلْ $_userTitle، اكْتُبْ يَوْمِيَّاتَك.");
      }
      return;
    }

    // 12. أوامر الإعدادات والوضع الليلي (القديمة كاحتياطي)
    if (_hasAny(cmd, ['افتح الإعدادات', 'افتحي الإعدادات', 'الإعدادات', 'اعدادات', 'الاعدادات', 'افتح الاعدادات'])) { _openSettingsScreen(); await _speak("تَمَّ فَتْحُ الإِعْدَادَاتِ $_userTitle."); return; }

    // 13. وضع التركيز
    if (_hasAny(cmd, ['وضع التركيز', 'فوكس', 'ركز معايا'])) {
      setState(() => _settings.wakeWordMode = 'off');
      await _saveSettings();
      try { await _wakeWordChannel.invokeMethod('stopWakeWord'); } catch (_) {}
      await _speak("تَمَّ تَفْعِيلُ وَضْعِ التَّرْكِيز $_userTitle، هَلْتَزِمْ الصَّمْت.");
      return;
    }

    // 14. وضع التسبيح
    if (_hasAny(cmd, ['وضع التسبيح', 'افتحي التسبيح', 'افتح التسبيح', 'ابدأ التسبيح'])) {
      setState(() {
        _currentIndex = 2;
        _prayerSubView = 'tasbeeh';
        _isTasbeehMode = true;
        _isAdhkarMode = false;
      });
      await _speak("تَمَّ فَتْحُ وَضْعِ التَّسْبِيح $_userTitle.");
      _listenVoiceCommand();
      return;
    }

    if (_hasAny(cmd, ['اقفلي التسبيح', 'اقفل التسبيح', 'قفلي التسبيح', 'قفل التسبيح', 'خلص تسبيح'])) {
      setState(() => _isTasbeehMode = false);
      await _speak("تَمَّ إِغْلَاقُ وَضْعِ التَّسْبِيح $_userTitle.");
      return;
    }

    if (_hasAny(cmd, ['صفري', 'امسحي العداد', 'امسحي التسبيح', 'صفر العداد'])) {
      setState(() {
        _tasbeehCount = 0;
        _tasbeehSubCounts.clear();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('tasbeeh_count', 0);
      for (var item in _tasbeehItems) {
        await prefs.setInt('tasbeeh_${item['key']}', 0);
      }
      await _speak("تَمَّ تَصْفِيرُ كُلِّ العَدَّادَات $_userTitle.");
      return;
    }

    if (_hasAny(cmd, ['سبحان الله', 'الحمد لله', 'الله اكبر', 'لا اله الا الله'])) {
      if (_isTasbeehMode) {
        _handleTasbeehResult(rawCommand);
        return;
      }
    }

    // 15. وضع الأذكار
    if (_hasAny(cmd, ['وضع الأذكار', 'افتح الأذكار', 'ابدأ الأذكار', 'تشغيل وضع الأذكار'])) {
      setState(() {
        _currentIndex = 2;
        _prayerSubView = 'adhkar';
        _isAdhkarMode = true;
        _isTasbeehMode = false;
      });
      await _speak("تَمَّ فَتْحُ وَضْعِ الأَذْكَارِ $_userTitle.");
      _listenVoiceCommand();
      return;
    }

    if (_hasAny(cmd, ['اقفلي الأذكار', 'اقفل الأذكار', 'قفلي الأذكار', 'قفل الأذكار', 'خلص أذكار'])) {
      setState(() => _isAdhkarMode = false);
      await _speak("تَمَّ إِغْلَاقُ وَضْعِ الأذْكَارِ $_userTitle.");
      return;
    }

    // ==========================================
    // 👈 التعديل ب: الوقت المتبقي + الصلاة الجاية + قراءة المواقيت
    // ==========================================

    // ⏳ الوقت المتبقي
    final targetPrayerKey = _parsePrayerName(cmd);
    if (targetPrayerKey != null && _hasAny(cmd, ['فاضل', 'باقي', 'كام خالص', 'بعد كام', 'قد ايه', 'اد ايه'])) {
      final times = await _calculatePrayerTimes();
      final timeStr = times[targetPrayerKey] ?? '';
      if (timeStr.isNotEmpty) {
        final parts = timeStr.split(':');
        final now = DateTime.now();
        var dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
        if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
        final diff = dt.difference(now);
        final hours = diff.inHours;
        final minutes = diff.inMinutes % 60;
        String remainingText;
        if (hours > 0 && minutes > 0) remainingText = 'فَاضِلْ $hours سَاعَة و $minutes دَقِيقَة';
        else if (hours > 0) remainingText = 'فَاضِلْ $hours سَاعَة';
        else if (minutes > 0) remainingText = 'فَاضِلْ $minutes دَقِيقَة';
        else remainingText = 'فَاضِلْ أَقَلْ مِنْ دَقِيقَة';
        final prayerNames = {
          'fajr': 'الفَجْر', 'dhuhr': 'الظُّهْر', 'asr': 'العَصْر',
          'maghrib': 'المَغْرِب', 'isha': 'العِشَاء', 'sunrise': 'الشُّرُوق'
        };
        await _speak("$remainingText عَلَى صَلَاةِ ${prayerNames[targetPrayerKey]} $_userTitle.");
        return;
      }
    }

    // 🕌 الصلاة الجاية
    if (_hasAny(cmd, [
      'الصلاة الجاية', 'الصلاة القادمة', 'الاذان الجاي', 'امتى الصلاة الجاية',
      'الصلاة اللي جاية', 'الصلاة الجاية امتى', 'الصلاة الجاية كام', 'الاذان القادم',
      'صلاة ايه الجاية', 'ايه الصلاة الجاية'
    ])) {
      final times = await _calculatePrayerTimes();
      final now = DateTime.now();
      final prayerKeys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
      final prayerNames = {
        'fajr': 'الفَجْر', 'dhuhr': 'الظُّهْر', 'asr': 'العَصْر',
        'maghrib': 'المَغْرِب', 'isha': 'العِشَاء'
      };
      String nextKey = 'fajr';
      DateTime? nextTime;
      for (final key in prayerKeys) {
        final timeStr = times[key] ?? '';
        if (timeStr.isEmpty) continue;
        final parts = timeStr.split(':');
        final dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
        if (dt.isAfter(now)) {
          nextKey = key;
          nextTime = dt;
          break;
        }
      }
      final speechTime = _formatTimeForSpeech(times[nextKey] ?? '');
      final tomorrowText = nextTime == null ? 'بُكْرَة ' : '';
      await _speak("الصَّلَاةُ الجَايَةُ هِيَ ${prayerNames[nextKey]} $tomorrowText$speechTime $_userTitle.");
      return;
    }

    // 🕌 الفجر
    if (_hasAny(cmd, [
      'امتى الفجر', 'امتا الفجر', 'إمتى الفجر', 'إمتا الفجر',
      'الفجر امتى', 'الفجر امتا', 'الفجر إمتى',
      'الفجر كام', 'كام الفجر', 'الفجر الساعة كام',
      'وقت الفجر', 'ميعاد الفجر', 'موعد الفجر', 'معاد الفجر',
      'امتى اذان الفجر', 'اذان الفجر امتى', 'امتى اذن الفجر', 'اذن الفجر امتى',
      'امتى يأذن الفجر', 'الفجر بيأذن امتى', 'هيأذن الفجر امتى',
      'امتى صلاة الفجر', 'صلاة الفجر امتى',
      'اقولي الفجر', 'قوليلي الفجر', 'قولي الفجر', 'قوللي الفجر', 'قولى الفجر',
    ])) {
      await _speakPrayerTimes(specificPrayer: 'fajr', name: 'الفَجْر');
      return;
    }

    // 🕌 الظهر
    if (_hasAny(cmd, [
      'امتى الظهر', 'امتا الظهر', 'الظهر امتى', 'الظهر امتا',
      'الظهر كام', 'كام الظهر', 'الظهر الساعة كام',
      'وقت الظهر', 'ميعاد الظهر', 'موعد الظهر',
      'امتى اذان الظهر', 'اذان الظهر امتى',
      'امتى يأذن الظهر', 'الظهر بيأذن امتى', 'هيأذن الظهر امتى',
      'امتى صلاة الظهر', 'صلاة الظهر امتى',
      'اقولي الظهر', 'قوليلي الظهر', 'قولي الظهر', 'قوللي الظهر',
    ])) {
      await _speakPrayerTimes(specificPrayer: 'dhuhr', name: 'الظُّهْر');
      return;
    }

    // 🕌 العصر
    if (_hasAny(cmd, [
      'امتى العصر', 'امتا العصر', 'العصر امتى', 'العصر امتا',
      'العصر كام', 'كام العصر', 'العصر الساعة كام',
      'وقت العصر', 'ميعاد العصر', 'موعد العصر',
      'امتى اذان العصر', 'اذان العصر امتى',
      'امتى يأذن العصر', 'العصر بيأذن امتى', 'هيأذن العصر امتى',
      'امتى صلاة العصر', 'صلاة العصر امتى',
      'اقولي العصر', 'قوليلي العصر', 'قولي العصر', 'قوللي العصر',
    ])) {
      await _speakPrayerTimes(specificPrayer: 'asr', name: 'العَصْر');
      return;
    }

    // 🕌 المغرب
    if (_hasAny(cmd, [
      'امتى المغرب', 'امتا المغرب', 'المغرب امتى', 'المغرب امتا',
      'المغرب كام', 'كام المغرب', 'المغرب الساعة كام',
      'وقت المغرب', 'ميعاد المغرب', 'موعد المغرب',
      'امتى اذان المغرب', 'اذان المغرب امتى',
      'امتى يأذن المغرب', 'المغرب بيأذن امتى', 'هيأذن المغرب امتى',
      'امتى صلاة المغرب', 'صلاة المغرب امتى',
      'اقولي المغرب', 'قوليلي المغرب', 'قولي المغرب', 'قوللي المغرب',
    ])) {
      await _speakPrayerTimes(specificPrayer: 'maghrib', name: 'المَغْرِب');
      return;
    }

    // 🕌 العشاء
    if (_hasAny(cmd, [
      'امتى العشاء', 'امتا العشاء', 'العشاء امتى', 'العشاء امتا',
      'امتى العشا', 'العشا امتى', 'العشا كام', 'كام العشا',
      'العشاء كام', 'كام العشاء', 'العشاء الساعة كام',
      'وقت العشاء', 'وقت العشا', 'ميعاد العشاء', 'موعد العشاء',
      'امتى اذان العشاء', 'اذان العشاء امتى',
      'امتى يأذن العشاء', 'العشاء بيأذن امتى', 'هيأذن العشاء امتى',
      'امتى صلاة العشاء', 'صلاة العشاء امتى',
      'اقولي العشاء', 'قوليلي العشاء', 'قولي العشاء', 'قوللي العشاء',
    ])) {
      await _speakPrayerTimes(specificPrayer: 'isha', name: 'العِشَاء');
      return;
    }

    // 🌅 الشروق
    if (_hasAny(cmd, [
      'امتى الشروق', 'الشروق امتى', 'الشروق كام',
      'وقت الشروق', 'ميعاد الشروق', 'موعد الشروق',
      'امتى يطلع الشروق', 'الشروق بيطلع امتى',
      'اقولي الشروق', 'قوليلي الشروق',
    ])) {
      await _speakPrayerTimes(specificPrayer: 'sunrise', name: 'الشُّرُوق');
      return;
    }

    // 🕌 كل المواقيت
    if (_hasAny(cmd, [
      'مواقيت الصلاة', 'مواعيد الصلاة', 'مواقيت الصلوات', 'مواعيد الصلوات',
      'قوليلي مواقيت', 'قوليلي مواعيد', 'اقولي المواقيت', 'اقولي المواعيد',
      'اقرا المواقيت', 'اقرا المواعيد', 'قوليلي الصلوات', 'اقولي الصلوات',
      'امتى الصلوات', 'الصلوات امتى', 'امتى الاذان', 'الاذان امتى',
      'مواقيت النهاردة', 'مواعيد النهاردة', 'الصلوات النهاردة',
      'مواقيت الصلاة النهاردة', 'مواعيد الصلاة النهاردة',
      'عايز اعرف مواقيت الصلاة', 'عايز اعرف مواعيد الصلاة',
      'عايزة اعرف مواقيت الصلاة', 'عايزة اعرف مواعيد الصلاة',
      'قوليلي مواقيت الصلاة', 'قوليلي مواعيد الصلاة',
      'اقولي مواقيت الصلاة', 'اقولي مواعيد الصلاة',
    ])) {
      await _speakPrayerTimes();
      return;
    }

    if (await _handleSocialReply(cmd)) return;

    if (cmd.contains('اكتب') && cmd.contains('يوميات')) {
      if (mounted) _openDiaryPage(DateTime.now());
      await _speak("اتْفَضَّلْ $_userTitle، اكْتُبْ يَوْمِيَّاتَك.");
      return;
    }
    if (cmd.contains('امسح') && cmd.contains('يوميات')) {
      final key = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (_diaries.containsKey(key)) {
        setState(() => _diaries.remove(key));
        _saveData();
        await _speak("تَمَّ مَسْحُ يَوْمِيَّةِ النَّهَارْدَة $_userTitle.");
      } else {
        await _speak("مَفِيشْ يَوْمِيَّةِ النَّهَارْدَة $_userTitle.");
      }
      return;
    }
    if (cmd.contains('دور') && (cmd.contains('يوميات') || cmd.contains('مفكرة'))) {
      final keyword = rawCommand.replaceAll(RegExp(r'(دور|على|ابحث|عن|في|يوميات|مفكرة)'), '').trim();
      if (keyword.isNotEmpty) {
        final results = _diaries.entries.where((e) => e.value['text'] != null && e.value['text'].toString().contains(keyword)).toList();
        if (results.isEmpty) {
          await _speak("مَفِيشْ يَوْمِيَّات فِيهَا كَلِمَة $keyword $_userTitle.");
        } else {
          await _speak("لَقِيتْ $keyword فِي ${results.length} يَوْمِيَّات. أَوَّلْ وَاحْدَة كَانَتْ يَوْم ${DateFormat('dd MMMM', 'ar').format(DateTime.parse(results.first.key))}.");
        }
        return;
      }
    }

    final weeklyIndicators = [
      'الجدول', 'جدول', 'الجدول الاسبوعي', 'الجدول الأسبوعي', 'جدول اسبوعي', 'جدول أسبوعي',
      'الجدول بتاع الاسبوع', 'الجدول بتاع الأسبوع', 'الجدول بتاعى', 'الجدول بتاعي',
      'الجدول بتاعنا', 'جدول الأسبوع', 'جدولي', 'جدولى', 'جدولي الاسبوعي', 'جدولي الأسبوعي',
      'جدولى الاسبوعي', 'جدولى الأسبوعي', 'في جدولي', 'في جدولى', 'من جدولي', 'من جدولى',
      'البرنامج الاسبوعي', 'البرنامج الأسبوعي', 'برنامجي الاسبوعي', 'برنامجي الأسبوعي',
      'برنامج الاسبوع', 'برنامج الأسبوع', 'خطة الاسبوع', 'خطة الأسبوع',
      'الخطة الاسبوعية', 'الخطة الأسبوعية', 'خطتي الاسبوعية', 'خطتي الأسبوعية',
      'اجندة الاسبوع', 'أجندة الأسبوع', 'الاجندة الاسبوعية', 'الأجندة الأسبوعية',
      'اجندتي الاسبوعية', 'أجندتي الأسبوعية', 'مواعيد الاسبوع', 'مواعيد الأسبوع',
      'المواعيد الاسبوعية', 'المواعيد الأسبوعية', 'مواعيدي الاسبوعية', 'مواعيدي الأسبوعية',
      'مهام الاسبوع', 'مهام الأسبوع', 'المهام الاسبوعية', 'المهام الأسبوعية',
      'في الجدول', 'من الجدول', 'على الجدول', 'علي الجدول', 'في جدول', 'من جدول',
      'التخطيط الاسبوعي', 'التخطيط الأسبوعي', 'التقويم الاسبوعي', 'التقويم الأسبوعي',
    ];
    final isWeeklyCmd = _hasAny(cmd, weeklyIndicators);

    final isAdding = _hasAny(cmd, [
      'ضفلي', 'ضف', 'ضفيه', 'ضيفه',
      'ضيف', 'ضيفي', 'ضيفلي', 'ضيفيلي', 'ضيفيه', 'اضف', 'أضف', 'اضفي', 'أضفي', 'اضفلي', 'أضفلي',
      'حط', 'حطي', 'حطلي', 'حطيلي', 'حطه', 'حطيها',
      'سجل', 'سجلي', 'سجللي', 'سجليلي', 'سجله', 'اعمل', 'اعملي', 'اعمللي', 'اعمليلي', 'اعمله',
      'ظبط', 'ظبطي', 'ظبطلي', 'ظبطيلي', 'ضبط', 'ضبطي', 'ضبطلي', 'ضبطيلي', 'اضبط', 'أضبط', 'اضبطي', 'أضبطي',
      'اظبط', 'أظبط', 'اظبطي', 'أظبطي', 'عايز اضيف', 'عايز أضيف', 'عايزة اضيف', 'عايزة أضيف',
      'عاوز اضيف', 'عاوز أضيف', 'عاوزة اضيف', 'عاوزة أضيف', 'عايز احط', 'عايز أحط', 'عايزة احط', 'عايزة أحط',
      'عاوز احط', 'عاوز أحط', 'عاوزة احط', 'عاوزة أحط', 'عايز اسجل', 'عايز أسجل', 'عايزة اسجل', 'عايزة أسجل',
      'عاوز اسجل', 'عاوز أسجل', 'عاوزة اسجل', 'عاوزة أسجل', 'حدد لي', 'حددلي', 'حدديلي', 'حددلي موعد',
    ]);

    final isDeleting = _hasAny(cmd, [
      'امسح', 'امسحي', 'امسحلي', 'امسحيلي', 'امسحه', 'امسحيها', 'أمسح', 'امسحى', 'مسح', 'مسحي', 'مسحلي', 'مسحيلي', 'مسحه',
      'احذف', 'احذفي', 'احذفلي', 'احذفيلي', 'احذفه', 'احذفيها', 'أحذف', 'حذف', 'حذفي', 'حذفلي', 'حذفيلي', 'حذفه',
      'شيل', 'شيلي', 'شيللي', 'شيليلي', 'شيله', 'شيليها', 'أشيل', 'اشيل', 'أشيله', 'اشيله',
      'الغي', 'الغى', 'الغيلي', 'الغيه', 'ألغي', 'ألغى', 'ألغيه', 'إلغاء', 'إلغى', 'الغاء',
      'كانسل', 'كنسل', 'كنسلي', 'كانسلي', 'كنسله', 'وقف', 'وقفي', 'اوقف', 'أوقف', 'اوقفه', 'أوقفه',
      'ازيل', 'أزيل', 'ازيلي', 'أزيلي', 'ازيله', 'أزيله', 'مش عايز', 'مش عاوز', 'مش عايزة', 'مش عاوزة', 'بلاش', 'بلاشه', 'بلاشيها',
    ]);

    final isEditing = _hasAny(cmd, [
      'عدل', 'عدلي', 'عدللي', 'عدليلي', 'عدله', 'عدليها', 'تعدل', 'تعدلي', 'أعدل', 'اعدل',
      'غير', 'غيري', 'غيرلي', 'غيريلي', 'غيره', 'غيريها', 'تغير', 'تغيري', 'أغير', 'اغير',
      'غيّر', 'غيّري', 'غيّره', 'غيّريها', 'بدل', 'بدلي', 'بدللي', 'بدليلي', 'بدله', 'بدليها',
      'تبدل', 'تبدلي', 'حرك', 'حركي', 'حركه', 'حركيها', 'أخر', 'أخري', 'أخره', 'أخريها',
      'أجل', 'أجّل', 'أجلي', 'أجّلي', 'أجله', 'تعديل', 'تعديلي', 'تعديله', 'غير الوقت', 'غيري الوقت',
      'عدل الوقت', 'عدلي الوقت', 'عدل الميعاد', 'غير الميعاد', 'خلي الميعاد', 'خلي الوقت',
    ]);

    // 👇 المسح الجماعي للمنبهات المتكررة
    if (_hasAny(cmd, ['امسح كل المنبهات المتكررة', 'امسح كل المنبهات اليومية', 'امسح كل المنبهات الأسبوعية', 'امسح كل المنبهات الشهرية'])) {
      await _deleteAllRecurringTasks();
      return;
    }

    if (_hasAny(cmd, [
      "امسح", "امسحي", "امسحلي", "امسحيلي", "أمسح", "أمسحي",
      "مسح", "مسحي", "مسحلي", "مسحيلي",
      "احذف", "احذفي", "احذفلي", "احذفيلي", "أحذف", "أحذفي",
      "حذف", "حذفي", "حذفلي", "حذفيلي",
      "شيل", "شيلي", "شيللي", "شيليلي", "أشيل",
      "الغي", "الغى", "ألغي", "ألغى", "الغيلي", "ألغيلي",
      "إلغاء", "إلغى", "كانسل", "كنسل", "كنسلي", "كانسلي",
      "وقف المنبه", "وقفي المنبه", "اوقف المنبه", "أوقف المنبه",
      "اقفل المنبه", "اقفلي المنبه", "الغي المنبه", "ألغي المنبه",
    ])) {
      if (isWeeklyCmd) {
        if (_hasAny(cmd, ['كل', 'كله', 'الكل', 'كلها', 'جميع', 'كل مواعيد', 'كل المواعيد']) ||
            (!_hasAny(cmd, ['موعد', 'ميعاد', 'مهام', 'درس']) && _hasAny(cmd, ['الجدول', 'جدول']))) {
          await _deleteAllWeeklyTasks();
          return;
        }
        await _deleteWeeklyTaskByVoice(rawCommand, cmd);
        return;
      }
      else {
        await _deleteTaskByVoice(cmd);
        return;
      }
    }

    if (!isAdding && !isDeleting && !isEditing &&
        _hasAny(cmd, [
          'افتح الجدول', 'افتحي الجدول', 'افتحلي الجدول', 'افتحيلي الجدول',
          'افتح الجدول الاسبوعي', 'افتحي الجدول الأسبوعي',
          'افتح جدولي', 'افتحي جدولي', 'افتح لي الجدول',
          'فتح الجدول', 'فتحي الجدول', 'فتحلي الجدول', 'فتحيلي الجدول',
          'وريني الجدول', 'وريني الجدول الاسبوعي', 'وريني الجدول الأسبوعي',
          'وريني جدولي', 'وريني جدولى',
          'اعرض الجدول', 'اعرضي الجدول', 'اعرضيلي الجدول',
          'اعرض الجدول الاسبوعي', 'اعرض الجدول الأسبوعي',
          'عرض الجدول', 'عرضي الجدول', 'عرض الجدول الاسبوعي',
          'هات الجدول', 'هاتي الجدول', 'هاتيلي الجدول', 'هاتلي الجدول',
          'هات الجدول الاسبوعي', 'هاتي الجدول الأسبوعي',
          'شوف الجدول', 'شوفي الجدول', 'شوفيلي الجدول',
          'روح للجدول', 'روحي للجدول', 'روح على الجدول', 'روحي على الجدول',
          'دخل الجدول', 'دخلي الجدول', 'دخلني الجدول', 'دخليني الجدول',
          'خلي الجدول', 'خليكي الجدول',
          'الجدول الاسبوعي', 'الجدول الأسبوعي',
          'جدول اسبوعي', 'جدول أسبوعي',
          'جدولي الاسبوعي', 'جدولي الأسبوعي',
          'البرنامج الاسبوعي', 'البرنامج الأسبوعي',
          'عرض الجدول', 'اعرض لي الجدول',
          'ايه في الجدول', 'إيه في الجدول', 'ايه في الجدول الاسبوعي', 'إيه في الجدول الأسبوعي',
          'ايه اللي في الجدول', 'إيه اللي في الجدول',
          'ايه عندي في الجدول', 'إيه عندي في الجدول',
          'اللي في الجدول', 'اللي عندي في الجدول',
          'عندي ايه في الجدول', 'عندي إيه في الجدول',
          'ايه مواعيدي', 'إيه مواعيدي', 'ايه مواعيدي الاسبوعية', 'إيه مواعيدي الأسبوعية',
          'المواعيد الاسبوعية', 'المواعيد الأسبوعية',
          'مواعيد الجدول', 'مواعيد الاسبوع',
          'مهام الجدول', 'مهام الاسبوع', 'مهامي في الجدول',
          'المهام الاسبوعية', 'المهام الأسبوعية',
          'اقرالي الجدول', 'اقرأيلي الجدول', 'اقرا الجدول', 'اقرأي الجدول',
          'اقرالي الجدول الاسبوعي', 'اقرأيلي الجدول الأسبوعي',
          'احكيلي الجدول', 'احكي الجدول', 'احكيلي عن الجدول',
          'اخبريني الجدول', 'قوليلي الجدول', 'قولي الجدول',
          'علميني الجدول', 'عرفيني الجدول',
          'قوليلي عندي ايه في الجدول', 'قولي عندي ايه',
        ])) {
      await _listWeeklySchedule();
      return;
    }

    if (isWeeklyCmd && isAdding) {
      await _createWeeklyAlarmFromVoice(rawCommand, cmd);
      return;
    }

    if (isWeeklyCmd && isEditing) {
      await _editWeeklyTaskByVoice(rawCommand, cmd);
      return;
    }

    final askingAboutDay = _hasAny(cmd, [
      'عندي ايه يوم', 'عندي إيه يوم', 'عندي ايه في يوم', 'عندي إيه في يوم',
      'ماذا لدي يوم', 'ماذا لدي في يوم', 'ماذا لدي يوم ال',
      'ماذا لديك يوم', 'ماذا لديك في يوم', 'ماذا لديك يوم ال',
      'ماذا عندي يوم', 'ماذا عندي في يوم', 'ماذا عندك يوم', 'ماذا عندك في يوم',
      'ايه عندي يوم', 'إيه عندي يوم', 'ايه عندي في يوم', 'إيه عندي في يوم',
      'ايه لدي يوم', 'إيه لدي يوم', 'ايه لدي في يوم', 'إيه لدي في يوم',
      'ورايا ايه يوم', 'ورايا إيه يوم', 'ورايا ايه في يوم', 'ورايا إيه في يوم',
      'ايه ورايا يوم', 'إيه ورايا يوم', 'ايه ورايا في يوم', 'إيه ورايا في يوم',
      'عندي ايه نهار', 'عندي إيه نهار', 'ايه يوم', 'إيه يوم',
      'مهام يوم', 'مواعيد يوم', 'جدول يوم', 'الجدول يوم',
      'قولي عندي ايه يوم', 'قوليلي عندي ايه يوم',
      'قولي عندي ايه في يوم', 'قوليلي عندي ايه في يوم',
      'قوليلي ماذا لدي يوم', 'قوليلي ايه عندي يوم',
      'عندي ايه يوم ال', 'عندي إيه يوم ال',
      'ايه اللي عندي يوم', 'إيه اللي عندي يوم',
      'ايه اللي عندي في يوم', 'إيه اللي عندي في يوم',
      'ايه مواعيدي يوم', 'إيه مواعيدي يوم',
      'ايه مهامي يوم', 'إيه مهامي يوم',
      'اعرض يوم', 'اعرضي يوم', 'وريني يوم', 'وريني مهام يوم',
      'عرض يوم', 'عرضي يوم',
    ]);
    final dayInQuestion = _extractWeeklyDaysFromCmd(cmd);
    if (dayInQuestion.isNotEmpty && (askingAboutDay || _hasAny(cmd, ['عندي ايه', 'عندي إيه', 'ايه عندي', 'إيه عندي', 'ورايا ايه', 'ورايا إيه', 'ايه ورايا', 'إيه ورايا', 'ايه مهامي', 'إيه مهامي', 'ايه مواعيدي', 'إيه مواعيدي']))) {
      await _listDayTasks(dayInQuestion.first);
      return;
    }

    if (_hasAny(cmd, [
      'ماذا لدي بكرة', 'ماذا لدي بكره', 'ماذا لدي بكرا', 'ماذا لدي غدا', 'ماذا لدي غداً',
      'ماذا لديك بكرة', 'ماذا لديك بكره', 'ماذا لديك غدا', 'ماذا لديك غداً',
      'ماذا عندي بكرة', 'ماذا عندي بكره', 'ماذا عندي غدا', 'ماذا عندك بكرة', 'ماذا عندك بكره', 'ماذا عندك غدا',
      'مهام بكرة', 'مهام بكره', 'مهام بكرا', 'مهام غدا', 'مهام غداً', 'مهامي بكرة', 'مهامي بكره', 'مهامي غدا',
      'مواعيد بكرة', 'مواعيد بكره', 'مواعيد غدا', 'مواعيد غداً',
      'عندي ايه بكرة', 'عندي ايه بكره', 'عندي ايه بكرا', 'عندي ايه غدا', 'عندي إيه بكرة', 'عندي إيه بكره', 'عندي إيه غدا',
      'ايه عندي بكرة', 'ايه عندي بكره', 'ايه عندي غدا', 'إيه عندي بكرة', 'إيه عندي بكره', 'إيه عندي غدا',
      'ايه ورايا بكرة', 'ايه ورايا بكره', 'ايه ورايا غدا', 'إيه ورايا بكرة', 'إيه ورايا بكره', 'إيه ورايا غدا',
      'ايه مهامي بكرة', 'ايه مهامي بكره', 'ايه مهامي غدا', 'اللي عندي بكرة', 'اللي عندي بكره', 'اللي عندي غدا',
      'عندي ايه بكرا', 'ايه لدي بكرة', 'ايه لدي غدا',
    ])) {
      await _listTodayTasks(targetDate: DateTime.now().add(const Duration(days: 1)));
      return;
    }

    if (_hasAny(cmd, [
      'ماذا لدي امبارح', 'ماذا لدي امبارحه', 'ماذا لدي البارحة', 'ماذا لدي البارحه', 'ماذا لدي امس',
      'ماذا لديك امبارح', 'ماذا لديك البارحة', 'ماذا لديك امس', 'ماذا عندي امبارح', 'ماذا عندي البارحة', 'ماذا عندي امس',
      'ماذا عندك امبارح', 'ماذا عندك البارحة', 'ماذا عندك امس', 'مهام امبارح', 'مهام امبارحه', 'مهام البارحة', 'مهام البارحه', 'مهام امس',
      'مهامي امبارح', 'مهامي البارحة', 'مهامي امس', 'مواعيد امبارح', 'مواعيد البارحة', 'مواعيد امس',
      'عندي ايه امبارح', 'عندي ايه البارحة', 'عندي ايه امس', 'عندي إيه امبارح', 'عندي إيه البارحة', 'عندي إيه امس',
      'ايه عندي امبارح', 'ايه عندي البارحة', 'ايه عندي امس', 'إيه عندي امبارح', 'إيه عندي البارحة', 'إيه عندي امس',
      'ايه ورايا امبارح', 'ايه ورايا البارحة', 'ايه ورايا امس', 'إيه ورايا امبارح', 'إيه ورايا البارحة', 'إيه ورايا امس',
      'ايه مهامي امبارح', 'ايه مهامي البارحة', 'ايه مهامي امس', 'اللي عندي امبارح', 'اللي عندي البارحة', 'اللي عندي امس',
      'ايه لدي امبارح', 'ايه لدي امس',
    ])) {
      await _listTodayTasks(targetDate: DateTime.now().subtract(const Duration(days: 1)));
      return;
    }

    if (_hasAny(cmd, [
      'مهام النهاردة', 'مهام اليوم', 'مهام النهارده', 'مهام انهاردة', 'مهامي النهاردة', 'مهامي اليوم', 'مهامي النهارده', 'مهامي انهاردة',
      'المهام النهاردة', 'المهام اليوم', 'المهام النهارده', 'المهام انهاردة', 'ماذا لدي اليوم', 'ماذا لدي النهاردة', 'ماذا لدي النهارده', 'ماذا لدي انهاردة',
      'ماذا لديك اليوم', 'ماذا لديك النهاردة', 'ماذا لديك النهارده', 'ماذا لديك انهاردة', 'ماذا عندي اليوم', 'ماذا عندي النهاردة', 'ماذا عندي النهارده',
      'ماذا عندك اليوم', 'ماذا عندك النهاردة', 'ماذا عندك النهارده', 'عندي ايه مهام', 'عندي إيه مهام', 'عندي ايه مهام النهاردة', 'عندي إيه مهام النهاردة',
      'ايه مهامي', 'إيه مهامي', 'ايه مهامي النهاردة', 'إيه مهامي النهاردة', 'ايه مهامي النهارده', 'إيه مهامي النهارده', 'ايه مهامي انهاردة',
      'ايه اللي عندي النهاردة', 'إيه اللي عندي النهاردة', 'ايه اللي عندي النهارده', 'إيه اللي عندي النهارده', 'اللي عندي النهاردة', 'اللي عندي اليوم', 'اللي عندي النهارده',
      'عندي ايه النهاردة', 'عندي إيه النهاردة', 'عندي ايه النهارده', 'عندي إيه النهارده', 'عندي ايه انهاردة', 'عندي إيه انهاردة',
      'ايه عندي النهاردة', 'إيه عندي النهاردة', 'ايه عندي النهارده', 'إيه عندي النهارده', 'ايه عندي انهاردة', 'إيه عندي انهاردة',
      'ايه عندي اليوم', 'إيه عندي اليوم', 'ايه عندي النهارده', 'ايه لدي اليوم', 'إيه لدي اليوم', 'ايه لدي النهاردة', 'إيه لدي النهاردة',
      'ايه لدي النهارده', 'إيه لدي النهارده', 'عندي ايه مهام النهارده', 'عندي إيه مهام النهارده', 'قولي مهامي', 'قوليلي مهامي', 'قوليلي ايه عندي',
      'قولي عندي ايه', 'قوليلي عندي ايه', 'قوليلي ايه اللي عندي', 'اعرض مهامي', 'اعرضي مهامي', 'اعرضي ايه عندي', 'هات مهامي', 'هاتي مهامي', 'هاتي ايه عندي',
      'ايه ورايا النهاردة', 'إيه ورايا النهاردة', 'ايه ورايا النهارده', 'ورايا ايه النهاردة', 'ورايا إيه النهاردة', 'ورايا ايه النهارده',
      'ايه ورايا', 'إيه ورايا', 'ايه ورايا اليوم', 'إيه ورايا اليوم', 'مهامي', 'المهام بتاعتي', 'المهام بتاعتى',
      'مواعيدي النهاردة', 'مواعيدي اليوم', 'مواعيدي النهارده', 'ايه مواعيدي', 'إيه مواعيدي', 'ايه مواعيدي النهاردة',
    ])) {
      await _listTodayTasks();
      return;
    }

    final alarmKeywords = [
      "فكرني", "فكريني", "فكروني", "فكرنى", "تفكرني", "تفكريني", "هتفكرني", "هتفكريني",
      "افتكرني", "افتكريني", "افتكرلي", "افتكرى لي", "هفتكرك",
      "ذكرني", "ذكريني", "ذكروني", "ذكرنى", "تذكرني", "تذكريني", "هتذكرني", "هتذكريني",
      "نبهني", "نبهيني", "نبهوني", "نبهنى", "تنبهني", "تنبهيني", "تنبيهي", "تنبيهني",
      "منبه", "منبّه", "منبهني", "منبهلي", "منبهيلي", "المنبه", "نبّهني",
      "اضبطلي", "اظبطلي", "اضبطيلي", "اظبطيلي", "ظبطلي", "ظبطيلي",
      "ضبطلي", "ضبطيلي", "اضبط", "اظبط", "اضبطي", "اظبطي", "ظبط", "ظبطي",
      "ضبط", "ضبطي", "اضبطيلى",
      "سجل عندك", "سجلي عندك", "سجللي", "سجليلي", "سجللى", "سجلى لى",
      "حطلي", "حطلى", "حطيلي", "حطى لي", "حطني", "حطيني",
      "اعمللي", "اعمليلي", "اعمللى", "اعملى لي", "اعملني", "اعمليني", "اعمليلى",
      "عايز", "عاوز", "عايزة", "عاوزة", "عايزك", "عاوزك", "عايزاك", "عاوزاك",
      "عايز افتكر", "عاوز افتكر", "عايزة افتكر", "عاوزة افتكر",
      "عايز منبه", "عاوز منبه", "عايزة منبه", "عاوزة منبه",
      "عايز تذكير", "عاوز تذكير", "عايزة تذكير", "عاوزة تذكير",
      "عايز اضبط", "عايزة اضبط", "عاوز اضبط", "عاوزة اضبط",
      "صحيني", "صحيني الصبح", "صحيني بكرة", "صحوني", "صحى", "تصحيني",
      "صحي", "صحيلي", "أصحى", "صيحيني", "صحيلى",
      "ورايا", "ورايه", "ورايا حاجه", "ورايا حاجة", "وراك", "وراك حاجة",
      "ورايا حاجه مهمه", "ورايا حاجة مهمة",
      "دبرلي", "دبريلي", "دبرلى", "دبرى لي",
      "رتبلي", "رتبيلي", "رتبلى", "رتبى لي",
      "جهزلي", "جهزيلي", "جهزلى", "جهزى لي",
      "علمني", "علميني",
      "خلي بالك", "خليكي بالك", "خد بالك", "خدي بالك",
      "ما تنساني", "ماتنساني", "متنساني", "ماتنسانيش", "متنسانيش",
      "ماتنساش", "متنساش", "ماتنساشي", "متنساشي",
      "ماتنسى", "متنسى", "ماتنسيش", "متنسيش",
      "موعد", "ميعاد", "موعدي", "ميعادي", "حددلي موعد", "حددلي ميعاد",
      "حدديلي موعد", "حدديلي ميعاد",
      "تنبيه", "التنبيه", "هنسى", "هنسي", "هنساه",
      "خايف أنسى", "خايفة أنسى", "خايف انسى", "خايفة انسى",
      "جهز نفسك", "خليك جاهز", "خليكي جاهزة",
      "ساعدني", "ساعديني", "تساعدني", "تساعديني",
      "تذكره", "تذكرة", "تذكيري", "تذكيرى",
      "بفكرك", "بتفكرني", "تفتكر", "تفكر",
    ];

    // 👈 التعديل أ: منبه مرتبط بالصلاة (لازم يكون قبل alarmKeywords)
    if (await _handlePrayerRelativeAlarm(rawCommand, cmd)) return;

    if (_hasAny(cmd, alarmKeywords)) {
      await _createAlarmFromVoice(rawCommand, cmd);
      return;
    }

    final editKeywords = [
      "عدل", "عدلي", "عدللي", "عدليلي", "تعدل", "تعدلي", "تعديل", "تعديلي", "أعدل", "اعدل",
      "غير", "غيري", "غيرلي", "غيريلي", "تغير", "تغيري", "غيّر", "غيّري", "تغيير", "تغييري",
      "بدل", "بدلي", "بدللي", "بدليلي", "تبدل", "تبدلي", "حرك", "حركي", "أخر", "أخري",
    ];

    if (_hasAny(cmd, editKeywords)) {
      await _editTaskByVoice(cmd);
      return;
    }

    final prayerKeywords = ["صلوات", "صلاة", "صلاه", "الصلاة", "مواقيت", "اذان", "أذان", "الفجر", "الظهر", "العصر", "المغرب", "العشاء"];
    final diaryKeywords = ["يوميات", "يوميه", "يومية", "اليوميات", "مفكرة", "مفكرتي", "المفكرة", "مذكرة", "مذكرتي", "تدوين", "خواطر", "اكتبلي", "اكتبيلي"];
    final eventKeywords = ["مناسبات", "مناسباتي", "المناسبات", "مناسبة", "مناسبه", "عيد", "العيد", "أعياد", "اعياد", "ذكرى", "الذكرى", "احتفال", "حفلة"];
    final openRecorderKeywords = [
      "افتح المسجل", "افتح مسجل", "افتحلي المسجل", "افتحي المسجل", "افتحيلى المسجل", "المسجل", "مسجل", "المسجل الصوتي",
      "سجل صوت", "سجل صوتي", "سجلي صوت", "سجلي صوتي", "التسجيلات", "تسجيلات", "تسجيلاتي", "صوتيات", "الصوتيات", "المذكرات الصوتيه", "مذكرات صوتيه", "المذكرات الصوتية",
    ];
    final startRecordKeywords = [
      "ابدأ تسجيل", "ابدأ التسجيل", "ابدئي تسجيل", "ابدئي التسجيل", "ابدا تسجيل", "ابدا التسجيل", "سجل دلوقتي", "سجل حالا", "سجل حالاً",
      "سجلي دلوقتي", "سجلي حالا", "سجلي حالاً", "سجللي دلوقتي", "سجليلي دلوقتي", "سجللي حالا", "سجليلي حالا", "ابدأ دلوقتي", "ابدئي دلوقتي",
      "ابدأ سجل", "ابدئي سجل", "عايز أسجل", "عايز اسجل", "عاوز أسجل", "عاوز اسجل", "عايزة أسجل", "عايزة اسجل", "عاوزة أسجل", "عاوزة اسجل",
      "شغل التسجيل", "شغلي التسجيل", "شغل المسجل", "شغلي المسجل", "ابدأ التسجيل دلوقتي", "ابدئي التسجيل دلوقتي", "سجل يلا", "سجلي يلا", "سجل بسرعة", "سجلي بسرعة",
    ];
    final stopRecordKeywords = [
      "وقف تسجيل", "وقف التسجيل", "وقفي تسجيل", "وقفي التسجيل", "اوقف تسجيل", "اوقف التسجيل", "أوقف تسجيل", "أوقف التسجيل", "وقفت تسجيل", "وقفت التسجيل",
      "خلاص وقف تسجيل", "خلاص وقف التسجيل", "خلاص وقفي تسجيل", "خلاص وقفي التسجيل", "خلاص وقف", "خلاص وقفي", "خلاص اوقف", "خلاص أوقف", "خلاص ايقاف", "خلاص إيقاف",
      "خلاص كفاية", "خلاص كفايه", "خلاص بلاها", "خلاص بلاش", "خلاص انتهي", "خلاص انتهى", "خلاص اقفل التسجيل", "خلاص اقفلي التسجيل", "خلص تسجيل", "خلص التسجيل",
      "خلصي تسجيل", "خلصي التسجيل", "خلصت تسجيل", "خلصت التسجيل", "خلص خلاص", "خلصي خلاص", "بطل تسجيل", "بطل التسجيل", "بطلي تسجيل", "بطلي التسجيل",
      "بطل بقي", "بطلي بقي", "انهي التسجيل", "انهي تسجيل", "أنهي التسجيل", "أنهي تسجيل", "اقفل التسجيل", "اقفلي التسجيل", "اقفل تسجيل", "اقفلي تسجيل",
      "قفل التسجيل", "قفلي التسجيل", "كفاية تسجيل", "كفاية التسجيل", "كفايه تسجيل", "كفايه التسجيل", "كفاية كده", "كفايه كده", "كفاية خلاص", "كفايه خلاص",
      "بس كده", "بس خلاص", "بس كفاية", "بس كفايه", "كده كفاية", "كده كفايه", "اوقف", "أوقف", "ايقاف", "إيقاف", "ستوب", "stop", "سيب التسجيل", "سيبي التسجيل",
      "متسجلش", "ماتسجلش", "متسجليش", "ماتسجليش", "مش عايز اسجل", "مش عاوز اسجل", "مش عايزة اسجل", "مش عاوزة اسجل",
    ];

    if (_hasAny(cmd, prayerKeywords)) {
      setState(() {
        _currentIndex = 2;
        _prayerSubView = 'times';
      });
      await _speak("تَمَّ الاِنْتِقَالُ لِمَوَاقِيتِ الصَّلَاة $_userTitle.");
      return;
    } else if (_hasAny(cmd, diaryKeywords)) {
      setState(() => _currentIndex = 1);
      await Future.delayed(const Duration(milliseconds: 300));
      final requestedDate = _parseDiaryDate(cmd);
      if (requestedDate != null) {
        if (mounted) _openDiaryPage(requestedDate);
        final dayName = DateFormat('EEEE، dd MMMM yyyy', 'ar').format(requestedDate);
        await _speak("تَمَّ فَتْحُ يَوْمِيَّةِ $dayName $_userTitle");
      } else {
        if (mounted) _openDiaryPage(DateTime.now());
        await _speak("تَمَّ فَتْحُ يَوْمِيَّةِ النَّهَارْدَة $_userTitle");
      }
      return;
    } else if (_hasAny(cmd, eventKeywords)) {
      setState(() => _currentIndex = 3);
      await _speak("تَمَّ الاِنْتِقَالُ لِلْمُنَاسَبَاتِ السَّنَوِيَّة $_userTitle.");
      return;
    } else if (_hasAny(cmd, stopRecordKeywords)) {
      if (_isRecording) {
        await _stopRecording();
        await _speak("تَمَّ إِيقَافُ التَّسْجِيل $_userTitle.");
      } else {
        await _speak("مَفِيشْ تَسْجِيل شَغَّال دِلْوَقْتِي $_userTitle.");
      }
      return;
    } else if (_hasAny(cmd, startRecordKeywords)) {
      setState(() => _currentIndex = 4);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_isRecording) {
        await _startRecording();
        await _speak("بَدَأْتْ التَّسْجِيل $_userTitle.");
      } else {
        await _speak("التَّسْجِيل شَغَّال بِالفِعْل $_userTitle.");
      }
      return;
    } else if (_hasAny(cmd, openRecorderKeywords)) {
      setState(() => _currentIndex = 4);
      await _speak("تَمَّ فَتْحُ قِسْمِ المُسَجِّل $_userTitle.");
      return;
    }

    if (isCalledByName) {
      await _speak("نَعَمْ $_userTitle! أَنَا أَسْمَعُكَ.");
    } else {
      await _speak("عُذْراً $_userTitle، لَمْ أَفْهَمِ الأَمْرَ.");
    }
    if (_isAlarmDialogOpen && !_isListening && !_isRecording) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _isAlarmDialogOpen && !_isListening && !_isRecording) _listenVoiceCommand();
      });
    }
  }

  // ══════════════════════════════════════════════════════
  // 🆕 دالة _getTasksForDate (لإظهار المنبهات المتكررة كل يوم)
  // ══════════════════════════════════════════════════════
  List<Map<String, dynamic>> _getTasksForDate(DateTime date) {
    final formattedDate = DateFormat('yyyy-MM-dd').format(date);
    final dayName = _weekDays[(date.weekday) % 7];

    return _tasks.where((t) {
      // 1. لو المهمة متسجلة بنفس اليوم ده بالظبط
      if (t['date'] == formattedDate) return true;

      // 2. لو المهمة متكررة
      final repeat = t['repeat'] as String? ?? 'مرة واحدة';
      if (repeat == 'يومي') return true;

      if (repeat == 'أسبوعي') {
        final originalDate = DateTime.tryParse(t['date'].toString());
        return originalDate != null && originalDate.weekday == date.weekday;
      }

      if (repeat == 'شهري') {
        final originalDate = DateTime.tryParse(t['date'].toString());
        return originalDate != null && originalDate.day == date.day;
      }

      if (repeat == 'مخصص') {
        final customDays = List<String>.from(t['customDays'] ?? []);
        return customDays.contains(dayName);
      }

      return false;
    }).toList();
  }

  // ══════════════════════════════════════════════════════
  // 🆕 دالة المسح الجماعي للمنبهات المتكررة
  // ══════════════════════════════════════════════════════
  Future<void> _deleteAllRecurringTasks() async {
    final recurringTasks = _tasks.where((t) => (t['repeat'] ?? 'مرة واحدة') != 'مرة واحدة').toList();
    if (recurringTasks.isEmpty) {
      await _speak("مَفِيشْ عِنْدَكْ مُنَبِّهَاتْ مُتَكَرِّرَةْ $_userTitle.");
      return;
    }
    final count = recurringTasks.length;
    for (var task in recurringTasks) {
      final alarmId = task['alarmId'] as int?;
      if (alarmId != null) {
        try { await _notifications.cancel(alarmId); } catch (_) {}
        await _cancelNativeAlarm(task['task'].toString(), customId: alarmId);
      } else {
        await _cancelNativeAlarm(task['task'].toString());
      }
    }
    setState(() => _tasks.removeWhere((t) => (t['repeat'] ?? 'مرة واحدة') != 'مرة واحدة'));
    await _saveData();
    await _speak("تَمَّ مَسْحُ $count مِنْبِهْ مُتَكَرِّرْ بِنَجَاح $_userTitle.");
  }

  Future<void> _listTodayTasks({DateTime? targetDate}) async {
    final userTitle = _userTitle;
    final target = targetDate ?? DateTime.now();
    final todayName = _weekDays[(target.weekday) % 7];

    final todayTasks = _getTasksForDate(target);
    final weeklyToday = _weeklySchedule.where((t) => t['day'] == todayName).toList();
    _sortByTime(todayTasks);
    _sortByTime(weeklyToday);

    if (todayTasks.isEmpty && weeklyToday.isEmpty) {
      final dayWord = targetDate == null ? 'النَّهَارْدَة' : 'اليَوْمَ دَهْ';
      await _speak("مَفِيشْ عِنْدَكْ مَهَامْ $dayWord $_userTitle.");
      return;
    }

    String reply = '';
    if (todayTasks.isNotEmpty) {
      final List<String> taskTexts = [];
      for (final t in todayTasks) {
        taskTexts.add("${t['task']} السَّاعَة ${t['time']}");
      }
      reply += "عِنْدَكْ ${todayTasks.length} ${todayTasks.length == 1 ? "مُهِمَّة" : "مَهَامْ"}: ${taskTexts.join("، ")}.";
    }

    if (weeklyToday.isNotEmpty) {
      if (reply.isNotEmpty) reply += " ";
      final List<String> weeklyTexts = [];
      for (final t in weeklyToday) {
        weeklyTexts.add("${t['task']} السَّاعَة ${t['time']}");
      }
      reply += "وَفِي الجَدْوَلِ الأُسْبُوعِيِّ: ${weeklyTexts.join("، ")}.";
    }

    await _speak(reply);
  }

  Future<void> _listWeeklySchedule() async {
    final userTitle = _userTitle;
    setState(() {
      _currentIndex = 0;
      _calendarSubView = 'weekly';
    });

    if (_weeklySchedule.isEmpty) {
      await _speak("الجَدْوَلُ الأُسْبُوعِيُّ فَاضِي $_userTitle.");
      return;
    }

    final Map<String, List<Map<String, dynamic>>> byDay = {};
    for (final t in _weeklySchedule) {
      final day = t['day'].toString();
      byDay.putIfAbsent(day, () => []).add(t);
    }

    final List<String> parts = [];
    for (final day in _weekDays) {
      if (!byDay.containsKey(day)) continue;
      final dayList = byDay[day]!;
      _sortByTime(dayList);
      final List<String> dayTasks = [];
      for (final t in dayList) {
        dayTasks.add("${t['task']} السَّاعَة ${t['time']}");
      }
      parts.add("يَوْمْ $day: ${dayTasks.join("، ")}");
    }

    await _speak("عِنْدَكْ فِي الجَدْوَلِ الأُسْبُوعِيِّ: ${parts.join(". ")}.");
  }

  Future<void> _listDayTasks(String day) async {
    final userTitle = _userTitle;
    final weeklyTasks = _weeklySchedule.where((t) => t['day'] == day).toList();
    _sortByTime(weeklyTasks);

    final today = DateTime.now();
    final dayIndex = _weekDays.indexOf(day);
    final todayIndex = (today.weekday) % 7;
    final daysAhead = (dayIndex - todayIndex + 7) % 7;
    final targetDate = today.add(Duration(days: daysAhead));

    final normalTasks = _getTasksForDate(targetDate);
    _sortByTime(normalTasks);

    if (weeklyTasks.isEmpty && normalTasks.isEmpty) {
      await _speak("مَفِيشْ عِنْدَكْ مَوَاعِيد يَوْمْ $day $_userTitle.");
      return;
    }

    String reply = '';
    if (weeklyTasks.isNotEmpty) {
      final List<String> texts = [];
      for (final t in weeklyTasks) {
        texts.add("${t['task']} السَّاعَة ${t['time']}");
      }
      reply += "عِنْدَكْ فِي الجَدْوَلِ الأُسْبُوعِيِّ يَوْمْ $day: ${texts.join("، ")}.";
    }

    if (normalTasks.isNotEmpty) {
      if (reply.isNotEmpty) reply += " ";
      final List<String> texts = [];
      for (final t in normalTasks) {
        texts.add("${t['task']} السَّاعَة ${t['time']}");
      }
      reply += "وَكَمَانْ عِنْدَكْ: ${texts.join("، ")}.";
    }

    await _speak(reply);
  }

// ══════════════════════════════════════════════════════
// نهاية PART 6 / 8
// ══════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════
// PART 7 / 8
// Delete/Edit/Create Alarms + Scheduling + Alarm Loop
// + _calculatePrayerTimes + الدوال الخمسة الجديدة للصلاة
// ══════════════════════════════════════════════════════

  Future<void> _deleteWeeklyTaskByVoice(String rawCommand, String cmd) async {
  final userTitle = _userTitle;
  final days = _extractWeeklyDaysFromCmd(cmd);
  final taskNameRaw = _extractWeeklyTaskName(rawCommand);
  final searchTerm = _norm(taskNameRaw);

  if (searchTerm.isEmpty && days.isNotEmpty) {
    final matches = _weeklySchedule.where((t) => days.contains(t['day'].toString())).toList();
    if (matches.isEmpty) {
      await _speak("مَفِيشْ مَوَاعِيد فِي الأَيَّامْ دِي $_userTitle.");
      return;
    }
    final count = matches.length;
    for (final task in matches) {
      final taskScheduled = DateTime.tryParse(task['scheduled']?.toString() ?? '');
      final taskHhmm = taskScheduled != null ? DateFormat('HHmm').format(taskScheduled) : '';
      final fullTitle = 'جدول_${task['day']}_${taskHhmm}_${task['task']}';
      await _cancelNativeAlarm(fullTitle);
      try { await _notifications.cancel(fullTitle.hashCode + 1000); } catch (_) {}
    }
    setState(() {
      for (final task in matches) {
        _weeklySchedule.remove(task);
      }
    });
    _saveWeeklySchedule();
    await _speak("تَمَّ مَسْحُ $count ${count == 1 ? "مَوْعِدْ" : "مَوَاعِيدْ"} مِنْ أَيَّامْ: ${days.join('، ')} $_userTitle.");
    return;
  }

  if (searchTerm.isEmpty) {
    await _speak("قُولِّي أَمْسَحْ أَنَّهِي مَوْعِدْ مِنَ الجَدْوَلْ $_userTitle.");
    return;
  }

  final matches = <Map<String, dynamic>>[];
  for (final t in _weeklySchedule) {
    if (days.isNotEmpty && !days.contains(t['day'].toString())) continue;
    final taskName = _norm(t['task'].toString());
    if (taskName.contains(searchTerm) || searchTerm.contains(taskName)) {
      matches.add(t);
    }
  }

  if (matches.isEmpty) {
    await _speak("مَفِيشْ مَوْعِدْ بِالاِسْمْ دَهْ فِي الجَدْوَلْ $_userTitle.");
    return;
  }

  if (matches.length == 1) {
    final task = matches.first;
    final taskTitle = task['task'].toString();
    final day = task['day'].toString();
    final idx = _weeklySchedule.indexOf(task);
    
    final taskScheduled = DateTime.tryParse(task['scheduled']?.toString() ?? '');
    final taskHhmm = taskScheduled != null ? DateFormat('HHmm').format(taskScheduled) : '';
    final fullTitle = 'جدول_${day}_${taskHhmm}_$taskTitle';

    setState(() => _weeklySchedule.removeAt(idx));
    _saveWeeklySchedule();
    await _cancelNativeAlarm(fullTitle);
    try { await _notifications.cancel(fullTitle.hashCode + 1000); } catch (_) {}
    await _speak("تَمَّ مَسْحُ مَوْعِدْ $taskTitle مِنْ يَوْمْ $day $_userTitle.");
  } else {
    final count = matches.length;
    for (final task in matches) {
      final taskScheduled = DateTime.tryParse(task['scheduled']?.toString() ?? '');
      final taskHhmm = taskScheduled != null ? DateFormat('HHmm').format(taskScheduled) : '';
      final fullTitle = 'جدول_${task['day']}_${taskHhmm}_${task['task']}';
      await _cancelNativeAlarm(fullTitle);
      try { await _notifications.cancel(fullTitle.hashCode + 1000); } catch (_) {}
    }
    setState(() {
      for (final task in matches) {
        _weeklySchedule.remove(task);
      }
    });
    _saveWeeklySchedule();
    await _speak("تَمَّ مَسْحُ $count مَوَاعِيدْ مِنْ أَيَّامْ: ${days.join('، ')} $_userTitle.");
  }
  }

  Future<void> _editWeeklyTaskByVoice(String rawCommand, String cmd) async {
    final userTitle = _userTitle;
    final days = _extractWeeklyDaysFromCmd(cmd);
    final taskNameRaw = _extractWeeklyTaskName(rawCommand);
    final searchTerm = _norm(taskNameRaw);

    if (searchTerm.isEmpty) {
      await _speak("قُولِّي أَعَدِّلْ أَنَّهِي مَوْعِدْ فِي الجَدْوَلْ $_userTitle.");
      return;
    }

    final matches = <Map<String, dynamic>>[];
    for (final t in _weeklySchedule) {
      if (days.isNotEmpty && !days.contains(t['day'].toString())) continue;
      final taskName = _norm(t['task'].toString());
      if (taskName.contains(searchTerm) || searchTerm.contains(taskName)) {
        matches.add(t);
      }
    }

    if (matches.isEmpty) {
      await _speak("مَفِيشْ مَوْعِدْ بِالاِسْمْ دَهْ فِي الجَدْوَلْ $_userTitle.");
      return;
    }

    if (matches.length == 1) {
      final task = matches.first;
      final idx = _weeklySchedule.indexOf(task);
      if (mounted) {
        await _editWeeklyTaskDialog(idx);
        await _speak("هَيِظْهَرْلَكْ المَوْعِدْ $_userTitle، عَدِّلْ زَيِّ مَا تُحِبْ.");
      }
    } else {
      final List<String> daysFound = [];
      for (final t in matches) {
        final d = t['day'].toString();
        if (!daysFound.contains(d)) daysFound.add(d);
      }
      await _speak("لَقِيتْ $taskNameRaw فِي أَكْتَرْ مِنْ يَوْمْ: ${daysFound.join("، ")}. قُولِّي أَنَّهِي يَوْمْ $_userTitle.");
    }
  }

  String? _parseSoundFromVoice(String cmd) {
    if (_hasAny(cmd, [
      'صوت السكرتير', 'صوت السكرتيرة', 'الافتراضي', 'صوت عادي', 'من غير نغمة',
      'صوتك', 'بدون نغمة', 'بدون صوت', 'عادي', 'صوت طبيعي', 'مفيش نغمة',
      'واقف', 'اسكت', 'صامت'
    ])) return 'secretary';

    if (_hasAny(cmd, [
      'مرعب 1', 'مرعب واحد', 'رعب 1', 'رعب واحد', 'مرعب', 'رعب', 'مخيف 1', 'مخيف واحد', 'خوف 1'
    ])) return 'raw://alarm_scary1';

    if (_hasAny(cmd, [
      'مرعب 2', 'مرعب اتنين', 'رعب 2', 'رعب اتنين', 'مخيف 2', 'مخيف اتنين', 'خوف 2', 'خوف اتنين'
    ])) return 'raw://alarm_scary2';

    if (_hasAny(cmd, [
      'ايفون', 'آيفون', 'iphone', 'ايفون 1', 'آيفون 1', 'ايفون 2', 'آيفون 2',
      'نغمة ايفون', 'رنة ايفون', 'صوت ايفون', 'تفاحة'
    ])) return 'raw://alarm_iphone';

    if (_hasAny(cmd, [
      'مشهور 1', 'مشهور واحد', 'مشهور', 'مشهورة 1', 'معروف 1', 'مشهور اوي 1'
    ])) return 'raw://alarm_famous1';

    if (_hasAny(cmd, [
      'مشهور 2', 'مشهور اتنين', 'مشهورة 2', 'معروف 2', 'مشهور اوي 2'
    ])) return 'raw://alarm_famous2';

    if (_hasAny(cmd, [
      'صحيان قوي 1', 'صحيان قوي واحد', 'قوي 1', 'الصحيان القوي 1', 'الصحيان القوي واحد',
      'صحيان 1', 'صحيان واحد', 'عالي 1', 'عالي واحد', 'صوت عالي 1', 'مزعج 1', 'الصحيان', 'صحيان', 'عالي',
      'نغمة الاستيقاظ', 'نغمة استيقاظ', 'استيقاظ', 'صوت الاستيقاظ', 'منبه الاستيقاظ', 'نغمة الصحوة'
    ])) return 'raw://alarm_loud1';

    if (_hasAny(cmd, [
      'صحيان قوي 2', 'صحيان قوي اتنين', 'قوي 2', 'الصحيان القوي 2', 'الصحيان القوي اتنين',
      'صحيان 2', 'صحيان اتنين', 'عالي 2', 'عالي اتنين', 'صوت عالي 2', 'مزعج 2'
    ])) return 'raw://alarm_loud2';

    return 'use_default';
  }

  String _getSoundName(String? uri) {
    if (uri == null) return 'صوت السكرتير';
    if (uri.contains('scary1')) return 'نغمة مرعب 1';
    if (uri.contains('scary2')) return 'نغمة مرعب 2';
    if (uri.contains('iphone')) return 'نغمة آيفون';
    if (uri.contains('famous1')) return 'نغمة مشهور 1';
    if (uri.contains('famous2')) return 'نغمة مشهور 2';
    if (uri.contains('loud1')) return 'نغمة صحيان قوي 1';
    if (uri.contains('loud2')) return 'نغمة صحيان قوي 2';
    return 'نغمة مخصصة';
  }

  Future<void> _createWeeklyAlarmFromVoice(String rawCommand, String cmd) async {
    final userTitle = _userTitle;
    final days = _extractWeeklyDaysFromCmd(cmd);
    if (days.isEmpty) {
      _pendingVoiceAction = 'weekly_day';
      _pendingRawCommand = rawCommand;
      _pendingActionTimer?.cancel();
      _pendingActionTimer = Timer(const Duration(seconds: 15), () {
        _pendingVoiceAction = null;
        _pendingRawCommand = null;
      });
      await _speak("قُولِّي أَنَّهِي يَوْمْ فِي الأُسْبُوعْ $_userTitle؟");
      _listenVoiceCommand();
      return;
    }

    final parsedHour = _parseHour(cmd);
    if (parsedHour == null) {
      _pendingVoiceAction = 'weekly_time';
      _pendingRawCommand = rawCommand;
      _pendingActionTimer?.cancel();
      _pendingActionTimer = Timer(const Duration(seconds: 15), () {
        _pendingVoiceAction = null;
        _pendingRawCommand = null;
      });
      await _speak("فِي أَيِّ سَاعَة $_userTitle؟");
      _listenVoiceCommand();
      return;
    }
    var hour = parsedHour;
    final minute = _parseMinute(cmd);
    final isEvening = _hasAny(cmd, ['مساء', 'بالليل', 'الليل', 'الظهر', 'العصر', 'المغرب', 'العشاء']);
    if (hour < 12 && isEvening) hour += 12;

    final intervalType = _parseIntervalType(cmd);

    var selectedSound = _parseSoundFromVoice(cmd);
    if (selectedSound == 'use_default') {
      final prefs = await SharedPreferences.getInstance();
      selectedSound = prefs.getString('default_weekly_sound') ?? prefs.getString('default_alarm_sound');
    } else if (selectedSound == 'secretary') {
      selectedSound = null;
    }

    String advanceReminder = 'في الموعد';
    if (_hasAny(cmd, ['قبلها بـ 5 دقائق', 'قبلها بـ 5 دقايق'])) advanceReminder = 'قبلها بـ 5 دقائق';
    else if (_hasAny(cmd, ['قبلها بـ 10 دقائق', 'قبلها بـ 10 دقايق', 'قبلها بعشر دقايق'])) advanceReminder = 'قبلها بـ 10 دقائق';
    else if (_hasAny(cmd, ['قبلها بـ 15 دقيقة', 'قبلها بربع ساعة'])) advanceReminder = 'قبلها بـ 15 دقيقة';
    else if (_hasAny(cmd, ['قبلها بـ 20 دقيقة', 'قبلها بتلت ساعة'])) advanceReminder = 'قبلها بـ 20 دقيقة';
    else if (_hasAny(cmd, ['قبلها بـ 30 دقيقة', 'قبلها بنص ساعة'])) advanceReminder = 'قبلها بـ 30 دقيقة';
    else if (_hasAny(cmd, ['قبلها بـ 45 دقيقة'])) advanceReminder = 'قبلها بـ 45 دقيقة';
    else if (_hasAny(cmd, ['قبلها بساعة'])) advanceReminder = 'قبلها بساعة';
    else if (_hasAny(cmd, ['قبلها بساعتين'])) advanceReminder = 'قبلها بساعتين';
    else if (_hasAny(cmd, ['قبلها ب 6 ساعات'])) advanceReminder = 'قبلها ب 6 ساعات';
    else if (_hasAny(cmd, ['قبلها ب 12 ساعة'])) advanceReminder = 'قبلها ب 12 ساعة';
    else if (_hasAny(cmd, ['قبلها بـ 24 ساعة', 'قبلها بيوم'])) advanceReminder = 'قبلها بـ 24 ساعة';

    String taskName = _extractWeeklyTaskName(rawCommand);
    if (taskName.isEmpty) taskName = 'موعد أسبوعي';

    final now = DateTime.now();
    final List<String> successDays = [];

    for (final day in days) {
      final dayIndex = _weekDays.indexOf(day);
      final todayIndex = (now.weekday) % 7;
      final daysAhead = (dayIndex - todayIndex + 7) % 7;
      final targetDate = now.add(Duration(days: daysAhead));
      var scheduledDateTime = DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute);

      if (scheduledDateTime.isBefore(now)) {
        scheduledDateTime = scheduledDateTime.add(const Duration(days: 7));
      }

      setState(() {
        _weeklySchedule.add({
          'day': day,
          'task': taskName,
          'time': DateFormat('hh:mm a', 'ar').format(scheduledDateTime),
          'scheduled': scheduledDateTime.toIso8601String(),
          'repeatInterval': intervalType,
          'advanceReminder': advanceReminder,
          'sound': selectedSound,
        });
      });

      if (intervalType != 'بدون تنبيه') {
        _scheduleWeeklyAlarm(taskName, day, scheduledDateTime, intervalType, advanceReminder, soundUri: selectedSound);
      }
      successDays.add(day);
    }

    _saveWeeklySchedule();

    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final periodText = hour >= 12 ? 'مَسَاءً' : 'صَبَاحاً';
    String daysText = successDays.join('، ');
    if (successDays.length == 7) daysText = "كُلِّ أَيَّامِ الأُسْبُوعْ";

    final soundText = selectedSound == null ? "بِصَوْتِ السِّكْرِتِير" : "عَلَى ${_getSoundName(selectedSound)}";

    await _speak("تَمَّتِ الإِضَافَة $_userTitle! $taskName فِي أَيَّامْ: $daysText السَّاعَة $h12 $periodText، $soundText.");
  }

  Future<void> _deleteTaskByVoice(String cmd) async {
  final userTitle = _userTitle;
  final now = DateTime.now();

  String? targetDate;
  if (_hasAny(cmd, ['النهاردة', 'النهارده', 'انهاردة', 'انهارده', 'اليوم'])) {
    targetDate = DateFormat('yyyy-MM-dd').format(now);
  } else if (_hasAny(cmd, ['بكره', 'بكرة', 'غدا', 'غداً'])) {
    targetDate = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));
  } else if (_hasAny(cmd, ['امبارح', 'امس', 'البارح'])) {
    targetDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
  } else {
    final delDays = _extractWeeklyDaysFromCmd(cmd);
    if (delDays.isNotEmpty) {
      final day = delDays.first;
      final dayIndex = _weekDays.indexOf(day);
      final todayIndex = (now.weekday) % 7;
      final daysAhead = (dayIndex - todayIndex + 7) % 7;
      final target = now.add(Duration(days: daysAhead));
      targetDate = DateFormat('yyyy-MM-dd').format(target);
    }
  }

  if (targetDate != null) {
    final matches = _tasks.where((t) => t['date'] == targetDate).toList();
    if (matches.isEmpty) {
      await _speak("مَفِيشْ مَوَاعِيد فِي اليَوْمَ دَهْ $_userTitle.");
      return;
    }
    final count = matches.length;
    
    for (final task in matches) {
      final alarmId = task['alarmId'] as int?;
      if (alarmId != null) {
        try { await _notifications.cancel(alarmId); } catch (_) {}
      }
      await _cancelNativeAlarm(task['task'].toString(), customId: alarmId);
    }
    
    setState(() {
      for (final task in matches) {
        _tasks.remove(task);
      }
    });
    _saveData();
    await _speak("تَمَّ مَسْحُ $count ${count == 1 ? "مَوْعِدْ" : "مَوَاعِيدْ"} $_userTitle.");
    return;
  }

  final nameNorm = _norm(_secretaryName);
  String searchTerm = cmd;
  final deleteWords = ['امسح', 'امسحي', 'احذف', 'احذفي', 'شيل', 'شيلي', 'الغي', 'الغى', 'الغيلي', 'مسح', 'حذف', 'كانسل', 'كنسل', 'المنبه', 'منبه', 'مواعيد', 'موعد', 'معاد', 'ميعاد'];
  for (final w in deleteWords) {
    searchTerm = searchTerm.replaceAll(_norm(w), '');
  }
  searchTerm = searchTerm.replaceAll(nameNorm, '').trim();

  if (searchTerm.isEmpty) {
    await _speak("قُولِّي أَمْسَحْ أَنَّهِي مَوْعِدْ $_userTitle");
    return;
  }

  final matches = _tasks.where((t) {
    final taskName = _norm(t['task'].toString());
    return taskName.contains(searchTerm) || searchTerm.contains(taskName);
  }).toList();

  if (matches.isEmpty) {
    await _speak("مَفِيشْ مَوْعِدْ بِالاِسْمْ دَهْ $_userTitle");
    return;
  }

  if (matches.length == 1) {
    final task = matches.first;
    final taskTitle = task['task'].toString();
    final alarmId = task['alarmId'] as int?;
    
    if (alarmId != null) {
      try { await _notifications.cancel(alarmId); } catch (_) {}
    }
    
    setState(() => _tasks.remove(task));
    _saveData();
    await _cancelNativeAlarm(taskTitle, customId: alarmId);
    await _speak("تَمَّ مَسْحُ مَوْعِدْ $taskTitle $_userTitle");
  } else {
    await _speak("لَقِيتْ ${matches.length} مَوَاعِيدْ بِالاِسْمْ دَهْ $_userTitle، حَدِّدْ أَكْتَرْ");
  }
 }

  Future<void> _editTaskByVoice(String cmd) async {
    final userTitle = _userTitle;
    final nameNorm = _norm(_secretaryName);
    String searchTerm = cmd;
    final editWords = ['عدل', 'عدلي', 'غير', 'غيري', 'بدل', 'بدلي', 'تعديل', 'تغيير'];
    for (final w in editWords) {
      searchTerm = searchTerm.replaceAll(_norm(w), '');
    }
    searchTerm = searchTerm.replaceAll(nameNorm, '').trim();

    if (searchTerm.isEmpty) {
      await _speak("قُولِّي أَعَدِّلْ أَنَّهِي مَوْعِدْ $_userTitle");
      return;
    }

    final matches = _tasks.where((t) {
      final taskName = _norm(t['task'].toString());
      return taskName.contains(searchTerm) || searchTerm.contains(taskName);
    }).toList();

    if (matches.isEmpty) {
      await _speak("مَفِيشْ مَوْعِدْ بِالاِسْمْ دَهْ $_userTitle");
      return;
    }

    if (matches.length == 1) {
      final index = _tasks.indexOf(matches.first);
      if (mounted) {
        _editTaskDialog(index);
        await _speak("هَيِظْهَرْلَكْ المَوْعِدْ $_userTitle، عَدِّلْ زَيِّ مَا تُحِبْ");
      }
    } else {
      await _speak("لَقِيتْ ${matches.length} مَوَاعِيدْ $_userTitle، حَدِّدْ أَكْتَرْ");
    }
  }

  Future<void> _createAlarmFromVoice(String rawCommand, String cmd) async {
    final userTitle = _userTitle;
    final now = DateTime.now();

    DateTime? parsedDate = _parseFullDate(cmd);
    var targetDate = parsedDate ?? now;
    var explicitDay = parsedDate != null;

    bool isSpecificWeekday = false;
    for (final day in _weekDays) {
      if (_hasAny(cmd, _dayKeywords[day] ?? [day])) {
        isSpecificWeekday = true;
        break;
      }
    }

    final parsedHour = _parseHour(cmd);
    if (parsedHour == null) {
      _pendingVoiceAction = 'alarm_time';
      _pendingRawCommand = rawCommand;
      _pendingActionTimer?.cancel();
      _pendingActionTimer = Timer(const Duration(seconds: 15), () {
        _pendingVoiceAction = null;
        _pendingRawCommand = null;
      });
      await _speak("فِي أَيِّ سَاعَة $_userTitle؟");
      _listenVoiceCommand();
      return;
    }
    var hour = parsedHour;
    final minute = _parseMinute(cmd);
    final isMorning = _hasAny(cmd, ['صباح', 'الصبح', 'فجر', 'صبح']);
    final isEvening = _hasAny(cmd, ['مساء', 'بالليل', 'الليل', 'الظهر', 'العصر', 'المغرب', 'العشاء']);
    final isNoon = cmd.contains('الظهر');
    final isWake = cmd.contains('صحيني');
    if (hour < 12) {
      if (isEvening && !(isNoon && hour >= 10)) {
        hour += 12;
      } else if (!isMorning && !isEvening && explicitDay && !isWake && hour >= 1 && hour <= 5) {
        hour += 12;
      }
    }
    var scheduled = DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute);
    if (!isMorning && !isEvening && !explicitDay && hour < 12 && scheduled.isBefore(now)) {
      final alt = scheduled.add(const Duration(hours: 12));
      if (alt.isAfter(now)) scheduled = alt;
    }

    if (scheduled.isBefore(now)) {
      if (isSpecificWeekday && explicitDay) {
        scheduled = scheduled.add(const Duration(days: 7));
      } else {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    }

    final repeatType = _parseRepeatType(cmd);
    final intervalType = _parseIntervalType(cmd);
    final customDays = _parseCustomDays(cmd);

    var selectedSound = _parseSoundFromVoice(cmd);
    if (selectedSound == 'use_default') {
      final prefs = await SharedPreferences.getInstance();
      selectedSound = prefs.getString('default_alarm_sound');
    } else if (selectedSound == 'secretary') {
      selectedSound = null;
    }

    final strip = <String>{
      'لا', 'لأ', 'لاء', 'أقصد', 'اقصد', 'يعني', 'قصدي',
      'اللي', 'الجاي', 'القادم', 'ده', 'دي', 'بعده', 'بعدها', 'بعدهم', 'بعدكم', 'بعدنا',
      'اظبطلي', 'اضبطلي', 'اظبطيلي', 'اضبطيلي', 'اظبط', 'اضبط', 'اظبطي', 'اضبطي',
      'ظبط', 'ضبط', 'ظبطي', 'ضبطي', 'ظبطلي', 'ضبطلي', 'ظبطيلي', 'ضبطيلي',
      'منبه', 'منبّه', 'المنبه',
      'فكرني', 'فكريني', 'ذكرني', 'ذكريني', 'نبهني', 'نبهيني',
      'تذكير', 'تذكيري', 'تذكيرى', 'سجل', 'سجلي', 'عندك', 'ورايا', 'ورايه',
      'عايز', 'عاوز', 'عايزة', 'عاوزة',
      'صحيني', 'صحوني', 'صحى', 'صحي', 'صحيلي', 'علمني', 'علميني',
      'حطلي', 'حطلى', 'حطيلي', 'حطني', 'حطيني',
      'اعمللي', 'اعملي', 'اعمللى', 'اعمليلي', 'اعملى',
      'دبرلي', 'دبريلي', 'دبرلى', 'دبرى',
      'رتبلي', 'رتبيلي', 'رتبلى', 'رتبى',
      'جهزلي', 'جهزيلي', 'جهزلى', 'جهزى',
      'خلي', 'خليكي', 'فاكرة', 'فاكر', 'بالك', 'خد', 'خدي',
      'افتكرني', 'افتكريني', 'ابقي', 'ابقى', 'لو سمحت', 'لو',
      'الساعه', 'ساعه', 'الساعة', 'ساعة', 'الصبح', 'صباحا', 'صباحاً', 'صبحا', 'الفجر', 'فجر',
      'مساء', 'مساءً', 'بالليل', 'الليل', 'ليلا',
      'الظهر', 'ظهرا', 'العصر', 'عصرا', 'المغرب', 'العشاء', 'العشا',
      'بكره', 'غدا', 'غداً', 'بعد', 'النهاردة', 'النهارده', 'اليوم',
      'ونص', 'وربع', 'وثلث', 'الا ربع', 'إلا ربع',
      'كل يوم', 'يومي', 'يوميا', 'يومياً', 'كل اسبوع', 'اسبوعي', 'اسبوعيا',
      'كل شهر', 'شهري', 'شهريا',
      'السبت', 'سبت', 'الاحد', 'الأحد', 'حد', 'الاتنين', 'الاثنين', 'اتنين',
      'التلات', 'الثلاثاء', 'تلات', 'الاربع', 'الأربعاء', 'اربع',
      'الخميس', 'خميس', 'الجمعه', 'الجمعة', 'جمعه', 'جمعة', 'و',
      'كل', 'عشر', 'عشره', 'عشرين', 'تلاتين', 'خمس', 'خمسه',
      'ثواني', 'ثانيه', 'ثانية', 'دقيقه', 'دقيقة', 'دقيقتين', 'دقايق',
      '10', '20', '30', '3', '5', 'يا', 'من فضلك', 'بليز', 'اني', 'ان', 'انى', 'أن',
      'على', 'علي', 'في', 'فى', 'عند', 'عندي', 'عندى',
      'يكون', 'تكون', 'يبقى', 'تبقى', 'مره', 'مرة', 'واحده', 'واحدة', 'بس', 'كفايه', 'كفاية', 'مش محتاج',
      'موعد', 'ميعاد', 'الميعاد', 'الموعد',
      'لي', 'لى', 'عليه',
      'ضيفلي', 'ضيفيلي', 'ضيف', 'ضيفي', 'أضفلي', 'اضفلي', 'أضيفلي', 'اضيفلي',
      'عايز اضيف', 'عايز أضيف', 'عايزة اضيف', 'عايزة أضيف',
      'عاوز اضيف', 'عاوز أضيف', 'عاوزة اضيف', 'عاوزة أضيف',
      'يوم السبت', 'يوم الاحد', 'يوم الأحد', 'يوم الاتنين', 'يوم الاثنين',
      'يوم التلات', 'يوم الثلاثاء', 'يوم الاربع', 'يوم الأربعاء',
      'يوم الخميس', 'يوم الجمعه', 'يوم الجمعة', 'يوم الحد',
      'بصوت', 'بنغمة', 'نغمة', 'صوت', 'مرعب', 'ايفون', 'آيفون', 'مشهور', 'صحيان', 'قوي', 'السكرتير', 'السكرتيرة', 'الافتراضي',
    };
    final nameNorm = _norm(_secretaryName);
    final kept = <String>[];
    bool hourTokenRemoved = false;
    for (final t in rawCommand.split(RegExp(r'\s+'))) {
      final n = _norm(t);
      if (n.isEmpty) continue;
      if (strip.contains(n) || n == nameNorm) continue;
      if (RegExp(r'^\d{1,2}(:\d{2})?$').hasMatch(n)) continue;
      if (!hourTokenRemoved && _hourWords.containsKey(n)) {
        hourTokenRemoved = true;
        continue;
      }
      if (_hourWords.containsKey(n)) continue;
      kept.add(t);
    }
    var cleanTitle = kept.join(' ').trim();
    if (cleanTitle.isEmpty) cleanTitle = isWake ? 'الاستيقاظ' : 'مهمة تذكيرية';
    final formattedDate = DateFormat('yyyy-MM-dd').format(scheduled);
    final formattedTime = DateFormat('hh:mm a', 'ar').format(scheduled);

    final alarmId = DateTime.now().millisecondsSinceEpoch % 1000000;

    final existingConflict = _tasks.any((t) =>
        t['date'] == formattedDate &&
        t['time'] == formattedTime);

    if (existingConflict) {
      _pendingConflictTaskData = {
        'date': formattedDate, 'task': cleanTitle, 'time': formattedTime,
        'alarm': true, 'scheduled': scheduled.toIso8601String(),
        'repeat': repeatType, 'repeatInterval': intervalType, 'customDays': customDays,
        'sound': selectedSound,
        'alarmId': alarmId,
      };
      _pendingConflictTaskIndex = null;
      _pendingVoiceAction = 'confirm_time_conflict';

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (conflictCtx) {
          _conflictDialogContext = conflictCtx;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text('⚠️ تنبيه هام', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text('فيه موعد تاني في نفس الوقت، تحب أحفظ الاتنين ولا ألغي؟', style: TextStyle(fontSize: 16)),
            actions: [
              TextButton(
                onPressed: () => _handleConflictResolution(false),
                child: const Text('إلغاء', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
                onPressed: () => _handleConflictResolution(true),
                child: const Text('حفظ الاتنين', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ).then((_) { _conflictDialogContext = null; });

      _pendingActionTimer?.cancel();
      _pendingActionTimer = Timer(const Duration(seconds: 15), () {
        if (_pendingVoiceAction == 'confirm_time_conflict') {
          _handleConflictResolution(false);
          _speak("مَعْلِشْ $_userTitle، تَمَّ إِلْغَاءُ الحِفْظِ عَشَانْ مَكَتَبْتِشْ رَدْ.");
        }
      });

      await _speak("فِيهْ مَوْعِدْ تَانِي فِي نَفْسْ الوَقْتْ $_userTitle، تِحِبْ أَحْفَظْ الاتنين ولا أَلْغِي؟");
      _listenVoiceCommand();
      return;
    }

    setState(() {
      _selectedDate = scheduled;
      _currentIndex = 0;
      _tasks.add({
        'date': formattedDate, 'task': cleanTitle, 'time': formattedTime,
        'alarm': true, 'scheduled': scheduled.toIso8601String(),
        'repeat': repeatType, 'repeatInterval': intervalType, 'customDays': customDays,
        'sound': selectedSound,
        'alarmId': alarmId,
      });
    });
    _saveData();
    _scheduleContinuousAlarm(cleanTitle, scheduled, repeatType, intervalType, customDays, soundUri: selectedSound, alarmId: alarmId);

    final h12 = scheduled.hour % 12 == 0 ? 12 : scheduled.hour % 12;
    final minuteText = scheduled.minute > 0 ? ' و ${scheduled.minute} دقيقة' : '';
    final periodText = scheduled.hour >= 12 ? 'مَسَاءً' : 'صَبَاحاً';
    String repeatText = '';
    if (repeatType != 'مرة واحدة') {
      repeatText = '، $repeatType';
      if (repeatType == 'مخصص' && customDays.isNotEmpty) {
        repeatText += ' (${customDays.join("، ")})';
      }
    }
    String intervalText = '';
    if (intervalType != 'بدون تنبيه') {
      intervalText = '، وَالتَّنْبِيهُ المُسْتَمِرُّ $intervalType';
    }
    final soundText = selectedSound == null ? "بِصَوْتِ السِّكْرِتِير" : "عَلَى ${_getSoundName(selectedSound)}";

    final dayName = DateFormat('EEEE', 'ar').format(scheduled);
    await _speak("تَمَّ التَّنْفِيذ $_userTitle! تَمَّ تَسْجِيل: $cleanTitle، يَوْمْ $dayName، السَّاعَة $h12$minuteText $periodText$repeatText$intervalText، $soundText.");
  }

  int _getIntervalSeconds(String interval) {
    switch (interval) {
      case 'مرة واحدة': return 0;
      case 'كل 10 ثواني': return 10;
      case 'كل 20 ثانية': return 20;
      case 'كل 30 ثانية': return 30;
      case 'كل دقيقة': return 60;
      case 'كل دقيقتين': return 120;
      case 'كل 3 دقايق': return 180;
      case 'كل 5 دقايق': return 300;
      case 'كل 10 دقايق': return 600;
      default: return 0;
    }
  }

  void _scheduleContinuousAlarm(
    String taskTitle,
    DateTime scheduledDateTime,
    String repeat,
    String interval,
    List<String> customDays, {
    String? soundUri,
    int? customId,
    int? customNotificationId,
    int? alarmId,
  }) {
    Duration difference = scheduledDateTime.difference(DateTime.now());
    if (difference.isNegative) return;

    int intervalSecs = _getIntervalSeconds(interval);
    _scheduleNativeAlarm(taskTitle, scheduledDateTime,
      interval: intervalSecs,
      customId: alarmId ?? customId,
      soundUri: soundUri);
    _scheduleBackgroundNotification(
      taskTitle,
      scheduledDateTime,
      repeat: repeat,
      interval: interval,
      customDays: customDays,
      soundUri: soundUri,
      customNotificationId: alarmId ?? customNotificationId,
    );

    late final Timer timer;
    timer = Timer(difference, () {
      _activeTimers.remove(timer);
      if (mounted) _startAlarmLoop(taskTitle, repeat, interval, customDays, scheduledDateTime, soundUri);
    });
    _activeTimers.add(timer);
  }

  Future<void> _scheduleNativeAlarm(
    String taskTitle,
    DateTime scheduledDateTime, {
    String prefix = 'حان الآن موعد: ',
    int interval = 0,
    int? customId,
    String? soundUri,
  }) async {
    try {
      await _nativeAlarmChannel.invokeMethod('scheduleAlarm', {
        'id': customId ?? (taskTitle.hashCode + 5000),
        'title': taskTitle,
        'timestamp': scheduledDateTime.millisecondsSinceEpoch,
        'prefix': prefix,
        'interval': interval,
        'soundUri': soundUri,
      });
    } catch (_) {}
  }

  Future<void> _cancelNativeAlarm(String taskTitle, {int? customId}) async {
    try {
      await _nativeAlarmChannel.invokeMethod('cancelAlarm', {
        'id': customId ?? (taskTitle.hashCode + 5000),
      });
      await _nativeAlarmChannel.invokeMethod('stopAlarmService');
    } catch (_) {}
  }

  void _rescheduleRepeating(String taskTitle, String repeat, String interval, List<String> customDays, DateTime lastScheduled, String? soundUri) {
    DateTime next;
    if (repeat == 'يومي') {
      next = lastScheduled.add(const Duration(days: 1));

      final taskData = _tasks.firstWhere((t) => t['task'] == taskTitle, orElse: () => {});
      if (taskData['isPrayerAlarm'] == true) {
        final prayerKey = taskData['prayerKey'] as String?;
        final offsetMinutes = taskData['prayerOffset'] as int?;

        if (prayerKey != null && offsetMinutes != null) {
          _calculatePrayerTimes(targetDate: next).then((times) {
            final timeStr = times[prayerKey] ?? '';
            if (timeStr.isNotEmpty) {
              final parts = timeStr.split(':');
              final prayerTime = DateTime(next.year, next.month, next.day, int.parse(parts[0]), int.parse(parts[1]));
              final newTarget = prayerTime.add(Duration(minutes: offsetMinutes));

              setState(() {
                final idx = _tasks.indexWhere((t) => t['task'] == taskTitle);
                if (idx != -1) {
                  _tasks[idx]['scheduled'] = newTarget.toIso8601String();
                  _tasks[idx]['time'] = DateFormat('hh:mm a', 'ar').format(newTarget);
                }
              });
              _saveData();
              final taskAlarmId = taskData['alarmId'] as int?;
              _scheduleContinuousAlarm(taskTitle, newTarget, repeat, interval, customDays, soundUri: soundUri, alarmId: taskAlarmId);
              return;
            }
          }).catchError((_) {
            final taskAlarmId = taskData['alarmId'] as int?;
            _scheduleContinuousAlarm(taskTitle, next, repeat, interval, customDays, soundUri: soundUri, alarmId: taskAlarmId);
          });
          return;
        }
      }
    } else if (repeat == 'كل يومين') {
      next = lastScheduled.add(const Duration(days: 2));
    } else if (repeat == 'كل أسبوعين') {
      next = lastScheduled.add(const Duration(days: 14));
    } else if (repeat == 'أسبوعي') {
      next = lastScheduled.add(const Duration(days: 7));
    } else if (repeat == 'شهري') {
      int nextMonth = lastScheduled.month + 1;
      int nextYear = lastScheduled.year;
      if (nextMonth > 12) {
        nextMonth = 1;
        nextYear++;
      }
      final lastDayOfNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
      final targetDay = lastScheduled.day > lastDayOfNextMonth ? lastDayOfNextMonth : lastScheduled.day;

      next = DateTime(nextYear, nextMonth, targetDay, lastScheduled.hour, lastScheduled.minute);
    } else if (repeat == 'مخصص') {
      next = lastScheduled.add(const Duration(days: 1));
      int safety = 0;
      while (safety < 14) {
        final dayName = _weekDays[(next.weekday) % 7];
        if (customDays.contains(dayName)) break;
        next = next.add(const Duration(days: 1));
        safety++;
      }
    } else {
      return;
    }

    final taskData = _tasks.firstWhere((t) => t['task'] == taskTitle, orElse: () => {});
    final taskAlarmId = taskData['alarmId'] as int?;
    _scheduleContinuousAlarm(taskTitle, next, repeat, interval, customDays, soundUri: soundUri, alarmId: taskAlarmId);
  }

  Future<void> _scheduleBackgroundNotification(
    String taskTitle,
    DateTime scheduledDateTime, {
    String repeat = 'مرة واحدة',
    String interval = 'بدون تنبيه',
    List<String> customDays = const [],
    String? soundUri,
    int? customNotificationId,
  }) async {
    final tzTime = tz.TZDateTime.from(scheduledDateTime, tz.local);

    final androidDetails = AndroidNotificationDetails(
      'secretary_alarm_bg_v6',
      'منبه السكرتير (خلفية)',
      channelDescription: 'لضمان استقرار المنبه في الخلفية',
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
      autoCancel: true,
      ongoing: false,
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
    );

    DateTimeComponents? matchComponent;
    if (repeat == 'يومي' || repeat == 'كل يومين') {
      matchComponent = DateTimeComponents.time;
    } else if (repeat == 'أسبوعي' || repeat == 'كل أسبوعين') {
      matchComponent = DateTimeComponents.dayOfWeekAndTime;
    } else if (repeat == 'شهري') {
      matchComponent = DateTimeComponents.dayOfMonthAndTime;
    }

    await _notifications.zonedSchedule(
      customNotificationId ?? (taskTitle.hashCode + 1000),
      'تنبيه هام!',
      'حان الآن موعد: $taskTitle',
      tzTime,
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchComponent,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_alarm', json.encode({
      'title': taskTitle,
      'scheduledMillis': scheduledDateTime.millisecondsSinceEpoch,
      'repeat': repeat,
      'interval': interval,
      'customDays': customDays,
      'sound': soundUri,
    }));
  }

  void _startAlarmLoop(
    String taskTitle,
    String repeat,
    String interval,
    List<String> customDays,
    DateTime scheduled,
    String? soundUri,
  ) {
    _ignoreNextWakeWordStart = false;

    if (scheduled.isBefore(DateTime.now().subtract(const Duration(minutes: 2)))) {
      return;
    }

    _activeTimers.removeWhere((timer) { timer.cancel(); return true; });
    _activeAlarmLoopTimer?.cancel();

    if (_isAlarmDialogOpen) {
      if (_activeAlarmTaskTitle == taskTitle) {
        return;
      }
      if (_alarmDialogContext != null) {
        try { Navigator.of(_alarmDialogContext!).pop(); } catch (_) {}
        _alarmDialogContext = null;
      }
      _isAlarmDialogOpen = false;
      _alarmVoiceSafetyTimer?.cancel();
      _tts.stop();
      try { _soundChannel.invokeMethod('stopPreview'); } catch (_) {}
    }

    final userTitle = _userTitle;
    final hasCustomSound = soundUri != null && soundUri.isNotEmpty && soundUri != 'default' && soundUri != 'system_alarm';
    final taskData = _tasks.firstWhere((t) => t['task'] == taskTitle, orElse: () => {});
    final alarmId = taskData['alarmId'] as int?;

    if (!hasCustomSound) {
      try { _nativeAlarmChannel.invokeMethod('stopAlarmService'); } catch (_) {}
      if (alarmId != null) {
        try { _nativeAlarmChannel.invokeMethod('cancelAlarm', {'id': alarmId}); } catch (_) {}
      }
    }
    try { _notifications.cancel(alarmId ?? (taskTitle.hashCode + 1000)); } catch (_) {}
    WakelockPlus.enable();
    HapticFeedback.vibrate();

    _isAlarmDialogOpen = true;
    _activeAlarmTitle = taskTitle;
    _activeAlarmTaskTitle = taskTitle;
    _activeAlarmScheduledTime = scheduled;
    _activeAlarmRepeat = repeat;
    _activeAlarmInterval = interval;
    _activeAlarmCustomDays = List.from(customDays);
    _activeAlarmSoundUri = soundUri;

    void speakAlert() {
  if (_isInBackground) return;
  // لو الصوت مخصص أو منبه الهاتف، التطبيق ميتكلمش
  if (!hasCustomSound && soundUri != 'system_alarm') {
    _speak("حَانَ الآنَ مَوْعِدُ: $taskTitle");
  }
  HapticFeedback.vibrate();
    }

    if (interval != 'بدون تنبيه') {
      speakAlert();
    }

    int secs = _getIntervalSeconds(interval);
    _activeAlarmLoopTimer?.cancel();
    if (secs > 0 && interval != 'مرة واحدة') {
      _activeAlarmLoopTimer = Timer.periodic(Duration(seconds: secs), (_) => speakAlert());
      _activeTimers.add(_activeAlarmLoopTimer!);
    } else {
      _activeAlarmLoopTimer = null;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (ctx) {
        _alarmDialogContext = ctx;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2A4A),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: _activeAlarmLoopTimer != null ? const AlwaysStoppedAnimation(1) : const AlwaysStoppedAnimation(0),
                    builder: (context, child) {
                      return _TalkingImage(
                        imagePath: _getSecretaryImage(_secretaryName, _settings.voiceGender, customImagePath: _settings.customImagePath),
                        isTalking: true,
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFF152238),
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.alarm_on, color: Color(0xFFC5A059), size: 26),
                          SizedBox(width: 8),
                          Text('تنبيه هام!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$userTitle،\nحَانَ الآنَ مَوْعِدُ:\n"$taskTitle"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2C3E50),
                                minimumSize: const Size(0, 50),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                _activeAlarmLoopTimer?.cancel();
                                _alarmVoiceSafetyTimer?.cancel();
                                _alarmVoiceSafetyTimer = null;
                                _tts.stop();
                                WakelockPlus.disable();
                                _isAlarmDialogOpen = false;
                                _activeAlarmTitle = null;
                                _alarmDialogContext = null;
                                try { _notifications.cancel(alarmId ?? (taskTitle.hashCode + 1000)); } catch (_) {}
                                try { _nativeAlarmChannel.invokeMethod('stopAlarmService'); } catch (_) {}
                                _cancelNativeAlarm(taskTitle, customId: alarmId);
                                SharedPreferences.getInstance().then((prefs) => prefs.remove('pending_alarm'));

                                final snoozeTime = DateTime.now().add(Duration(minutes: _settings.snoozeMinutes));
                                final snoozeTimestamp = DateTime.now().millisecondsSinceEpoch;

                                _scheduleContinuousAlarm(
                                  taskTitle,
                                  snoozeTime,
                                  'مرة واحدة',
                                  'كل 10 ثواني',
                                  [],
                                  customId: snoozeTimestamp,
                                  customNotificationId: snoozeTimestamp + 1000000,
                                  soundUri: soundUri,
                                );

                                if (repeat != 'مرة واحدة') {
                                  _rescheduleRepeating(taskTitle, repeat, interval, customDays, scheduled, soundUri);
                                }

                                Navigator.pop(ctx);
                              },
                              child: Text('تأجيل ${_settings.snoozeMinutes} د', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFC5A059),
                                minimumSize: const Size(0, 50),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () async {
                                _activeAlarmLoopTimer?.cancel();
                                _alarmVoiceSafetyTimer?.cancel();
                                _alarmVoiceSafetyTimer = null;
                                _tts.stop();
                                WakelockPlus.disable();
                                _isAlarmDialogOpen = false;
                                _activeAlarmTitle = null;
                                _alarmDialogContext = null;
                                try { await _notifications.cancel(alarmId ?? (taskTitle.hashCode + 1000)); } catch (_) {}
                                try { await _nativeAlarmChannel.invokeMethod('stopAlarmService'); } catch (_) {}
                                if (repeat == 'مرة واحدة') {
                                  final idx = _tasks.indexWhere((t) => t['task'] == taskTitle);
                                  if (idx != -1) { setState(() => _tasks.removeAt(idx)); _saveData(); }
                                  _cancelNativeAlarm(taskTitle, customId: alarmId);
                                  SharedPreferences.getInstance().then((prefs) => prefs.remove('pending_alarm'));
                                } else {
                                  _rescheduleRepeating(taskTitle, repeat, interval, customDays, scheduled, soundUri);
                                }
                                Navigator.pop(ctx);
                              },
                              child: const Text('خلاص', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) { _isAlarmDialogOpen = false; _alarmDialogContext = null; });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isAlarmDialogOpen && !_isListening && !_isRecording) {
        _listenVoiceCommand();
      }
    });

    _alarmVoiceSafetyTimer?.cancel();
    _alarmVoiceSafetyTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isAlarmDialogOpen) {
        timer.cancel();
        return;
      }
      if (_isInBackground) return;
      if (_activeAlarmTitle == null) return;

      if (!_isListening && !_starting && !_isRecording) {
        _listenVoiceCommand();
      }
    });
  }

  Future<Map<String, String>> _calculatePrayerTimes({DateTime? targetDate}) async {
    try {
      final coordinates = Coordinates(30.0444, 31.2357);
      final date = DateComponents.from(targetDate ?? DateTime.now());
      final params = CalculationMethod.egyptian.getParameters();
      params.madhab = Madhab.shafi;
      final prayerTimes = PrayerTimes(coordinates, date, params);

      final format = DateFormat('HH:mm');

      return {
        'fajr': format.format(prayerTimes.fajr.toLocal()),
        'sunrise': format.format(prayerTimes.sunrise.toLocal()),
        'dhuhr': format.format(prayerTimes.dhuhr.toLocal()),
        'asr': format.format(prayerTimes.asr.toLocal()),
        'maghrib': format.format(prayerTimes.maghrib.toLocal()),
        'isha': format.format(prayerTimes.isha.toLocal()),
      };
    } catch (e) {
      final format = DateFormat('HH:mm');
      final now = DateTime.now();
      return {'fajr': format.format(DateTime(now.year, now.month, now.day, 4, 25)), 'sunrise': format.format(DateTime(now.year, now.month, now.day, 5, 52)), 'dhuhr': format.format(DateTime(now.year, now.month, now.day, 11, 45)), 'asr': format.format(DateTime(now.year, now.month, now.day, 15, 8)), 'maghrib': format.format(DateTime(now.year, now.month, now.day, 17, 38)), 'isha': format.format(DateTime(now.year, now.month, now.day, 18, 55))};
    }
  }

  String _formatTimeForSpeech(String time24) {
    try {
      final parts = time24.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final isPm = hour >= 12;
      final h12 = hour % 12 == 0 ? 12 : hour % 12;
      String minuteText;
      if (minute == 0) minuteText = '';
      else if (minute == 15) minuteText = ' و رُبْع';
      else if (minute == 30) minuteText = ' و نُص';
      else if (minute == 45) minuteText = ' إِلَّا رُبْع';
      else minuteText = ' و $minute دَقِيقَة';
      final periodText = isPm ? 'مَسَاءً' : 'صَبَاحاً';
      return "السَّاعَة $h12$minuteText $periodText";
    } catch (_) { return time24; }
  }

  Future<void> _speakPrayerTimes({String? specificPrayer, String? name}) async {
    try {
      final times = await _calculatePrayerTimes();
      final userTitle = _userTitle;
      if (specificPrayer != null && name != null) {
        final timeStr = times[specificPrayer] ?? '';
        if (timeStr.isEmpty) {
          await _speak("مَعْلِشْ $userTitle، مَقْدَرْتِشْ أَجِيبْ مَوْعِدْ $name.");
          return;
        }
        await _speak("مَوْعِدْ $name النَّهَارْدَة ${_formatTimeForSpeech(timeStr)} $userTitle.");
      } else {
        await _speak("مَوَاقِيتُ الصَّلَاةِ النَّهَارْدَة $userTitle: "
            "الفَجْر ${_formatTimeForSpeech(times['fajr'] ?? '')}، "
            "الشُّرُوق ${_formatTimeForSpeech(times['sunrise'] ?? '')}، "
            "الظُّهْر ${_formatTimeForSpeech(times['dhuhr'] ?? '')}، "
            "العَصْر ${_formatTimeForSpeech(times['asr'] ?? '')}، "
            "المَغْرِب ${_formatTimeForSpeech(times['maghrib'] ?? '')}، "
            "العِشَاء ${_formatTimeForSpeech(times['isha'] ?? '')}.");
      }
    } catch (_) {
      await _speak("مَعْلِشْ $_userTitle، مَقْدَرْتِشْ أَجِيبْ المَوَاقِيت.");
    }
  }

  String? _parsePrayerName(String cmd) {
    final norm = _norm(cmd);
    if (_hasAny(norm, ['الفجر', 'فجر'])) return 'fajr';
    if (_hasAny(norm, ['الظهر', 'ظهر'])) return 'dhuhr';
    if (_hasAny(norm, ['العصر', 'عصر'])) return 'asr';
    if (_hasAny(norm, ['المغرب', 'مغرب'])) return 'maghrib';
    if (_hasAny(norm, ['العشاء', 'العشا', 'عشاء', 'عشا'])) return 'isha';
    if (_hasAny(norm, ['الشروق', 'شروق'])) return 'sunrise';
    return null;
  }

  int? _parsePrayerOffset(String cmd) {
  final norm = _norm(cmd);
  final isBefore = _hasAny(norm, ['قبل', 'قبلها', 'قبل ما']);
  final isAfter = _hasAny(norm, ['بعد', 'بعدها', 'بعد ما']);
  int? minutes;
  
  // 👇 التعديل هنا: بنشيك على الأجزاء (ربع، نص، تلت) الأول قبل كلمة "ساعة"
  if (_hasAny(norm, ['ساعتين وربع'])) minutes = 135;
  else if (_hasAny(norm, ['ساعتين', 'ساعتان'])) minutes = 120;
  else if (_hasAny(norm, ['ساعة وربع', 'ساعه وربع'])) minutes = 75;
  else if (_hasAny(norm, ['ساعة ونص', 'ساعة ونصف', 'ساعه ونص'])) minutes = 90;
  
  else if (_hasAny(norm, ['خمسة واربعين', 'خمسه واربعين', 'تلات تربع', '45 دقيقة', '45 دقيقه'])) minutes = 45;
  else if (_hasAny(norm, ['اربعين', '40 دقيقة', '40 دقيقه'])) minutes = 40;
  else if (_hasAny(norm, ['نص ساعة', 'نصف ساعة', 'نص ساعه', 'تلاتين', '30 دقيقة', '30 دقيقه'])) minutes = 30;
  else if (_hasAny(norm, ['تلت ساعة', 'ثلث ساعة', 'تلت ساعه', 'ثلث ساعه', 'عشرين', '20 دقيقة', '20 دقيقه'])) minutes = 20;
  
  // 👇 ضفنا كلمة (ربع) لوحدها عشان لو قال "قبل الفجر بربع"
  else if (_hasAny(norm, ['ربع ساعة', 'ربع ساعه', 'خمستاشر', 'ربع', '15 دقيقة', '15 دقيقه'])) minutes = 15;
  
  else if (_hasAny(norm, ['عشر دقايق', 'عشر دقائق', '10 دقايق', '10 دقائق'])) minutes = 10;
  else if (_hasAny(norm, ['خمس دقايق', 'خمس دقائق', '5 دقايق', '5 دقائق'])) minutes = 5;
  
  // 👇 كلمة "ساعة" لوحدها بنشيك عليها في الآخر عشان متمسحش الربع والنص
  else if (_hasAny(norm, ['ساعة', 'ساعه'])) minutes = 60; 

  if (minutes == null) return null;
  if (isBefore && !isAfter) return -minutes;
  if (isAfter && !isBefore) return minutes;
  if (isBefore && isAfter) return -minutes;
  return null;
  }

  Future<bool> _handlePrayerRelativeAlarm(String rawCommand, String cmd) async {
    final hasScheduleVerb = _hasAny(cmd, [
      'فكرني', 'فكريني', 'ذكرني', 'ذكريني', 'صحيني', 'صحوني', 'نبهني', 'نبهيني',
      'عايز تنبيه', 'عايزة تنبيه', 'عايز منبه', 'عايزة منبه', 'عايز تذكير', 'عايزة تذكير',
      'حطلي تنبيه', 'حطيلي تنبيه', 'ضيفلي تنبيه', 'ضيفيلي تنبيه',
      'حطلي منبه', 'حطيلي منبه', 'ضيفلي منبه', 'ضيفيلي منبه',
    ]);
    if (!hasScheduleVerb) return false;
    final prayerRelativeKeywords = [
      'قبل الفجر', 'قبل الظهر', 'قبل العصر', 'قبل المغرب', 'قبل العشاء', 'قبل العشا', 'قبل الشروق',
      'بعد الفجر', 'بعد الظهر', 'بعد العصر', 'بعد المغرب', 'بعد العشاء', 'بعد العشا', 'بعد الشروق',
      'قبل صلاة الفجر', 'قبل صلاة الظهر', 'قبل صلاة العصر', 'قبل صلاة المغرب', 'قبل صلاة العشاء',
      'بعد صلاة الفجر', 'بعد صلاة الظهر', 'بعد صلاة العصر', 'بعد صلاة المغرب', 'بعد صلاة العشاء',
      'قبل اذان الفجر', 'قبل اذان الظهر', 'قبل اذان العصر', 'قبل اذان المغرب', 'قبل اذان العشاء',
      'قبل أذان الفجر', 'قبل أذان الظهر', 'قبل أذان العصر', 'قبل أذان المغرب', 'قبل أذان العشاء',
    ];
    if (!_hasAny(cmd, prayerRelativeKeywords)) return false;
    final prayerKey = _parsePrayerName(cmd);
    if (prayerKey == null) return false;
    int? offsetMinutes = _parsePrayerOffset(cmd);
    if (offsetMinutes == null) offsetMinutes = -30;
    final times = await _calculatePrayerTimes();
    final timeStr = times[prayerKey] ?? '';
    if (timeStr.isEmpty) {
      await _speak("مَعْلِشْ $_userTitle، مَقْدَرْتِشْ أَعْرِفْ مَوْعِدْ الصَّلَاة.");
      return true;
    }
    final parts = timeStr.split(':');
    final now = DateTime.now();
    DateTime prayerTime = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
    DateTime target = prayerTime.add(Duration(minutes: offsetMinutes));
    if (target.isBefore(now)) {
      prayerTime = prayerTime.add(const Duration(days: 1));
      target = prayerTime.add(Duration(minutes: offsetMinutes));
    }
    final isDaily = _hasAny(cmd, ['كل يوم', 'يومي', 'يوميا', 'يومياً']);
    final repeatType = isDaily ? 'يومي' : 'مرة واحدة';
    var selectedSound = _parseSoundFromVoice(cmd);
    if (selectedSound == 'use_default') {
      final prefs = await SharedPreferences.getInstance();
      selectedSound = prefs.getString('default_alarm_sound');
    } else if (selectedSound == 'secretary') {
      selectedSound = null;
    }
    final prayerNames = {
      'fajr': 'الفَجْر', 'dhuhr': 'الظُّهْر', 'asr': 'العَصْر',
      'maghrib': 'المَغْرِب', 'isha': 'العِشَاء', 'sunrise': 'الشُّرُوق',
    };
    final prayerName = prayerNames[prayerKey] ?? '';
    final absOffset = offsetMinutes.abs();
    String offsetPhrase;
    String voiceOffsetPhrase;
    if (offsetMinutes < 0) {
      offsetPhrase = 'قبل $prayerName بـ $absOffset دقيقة';
      if (absOffset == 60) voiceOffsetPhrase = 'قَبْلَ $prayerName بِسَاعَة';
      else if (absOffset == 30) voiceOffsetPhrase = 'قَبْلَ $prayerName بِنُص سَاعَة';
      else if (absOffset == 15) voiceOffsetPhrase = 'قَبْلَ $prayerName بِرُبْع سَاعَة';
      else if (absOffset == 20) voiceOffsetPhrase = 'قَبْلَ $prayerName بِتِلْت سَاعَة';
      else voiceOffsetPhrase = 'قَبْلَ $prayerName بِـ $absOffset دَقِيقَة';
    } else {
      offsetPhrase = 'بعد $prayerName بـ $absOffset دقيقة';
      if (absOffset == 60) voiceOffsetPhrase = 'بَعْدَ $prayerName بِسَاعَة';
      else if (absOffset == 30) voiceOffsetPhrase = 'بَعْدَ $prayerName بِنُص سَاعَة';
      else if (absOffset == 15) voiceOffsetPhrase = 'بَعْدَ $prayerName بِرُبْع سَاعَة';
      else voiceOffsetPhrase = 'بَعْدَ $prayerName بِـ $absOffset دَقِيقَة';
    }
    final taskTitle = 'تذكير $offsetPhrase';
    final formattedDate = DateFormat('yyyy-MM-dd').format(target);
    final formattedTime = DateFormat('hh:mm a', 'ar').format(target);
    final alarmId = DateTime.now().millisecondsSinceEpoch % 1000000;
    setState(() {
      _tasks.add({
        'date': formattedDate, 'task': taskTitle, 'time': formattedTime,
        'alarm': true, 'scheduled': target.toIso8601String(),
        'repeat': repeatType, 'repeatInterval': 'كل 10 ثواني',
        'customDays': [], 'sound': selectedSound, 'advanceReminder': 'في الموعد',
        'isPrayerAlarm': isDaily,
        'prayerKey': prayerKey,
        'prayerOffset': offsetMinutes,
        'alarmId': alarmId,
      });
    });
    _saveData();
    _scheduleContinuousAlarm(taskTitle, target, repeatType, 'كل 10 ثواني', [], soundUri: selectedSound, alarmId: alarmId);
    final userTitle = _userTitle;
    final h12 = target.hour % 12 == 0 ? 12 : target.hour % 12;
    final periodText = target.hour >= 12 ? 'مَسَاءً' : 'صَبَاحاً';
    final isTomorrow = target.day != now.day;
    if (isDaily) {
      await _speak("تَمَام $userTitle، كُلْ يَوْمْ هَفَكَّرَكْ $voiceOffsetPhrase، وَالْمَرَّةُ الجَايَة السَّاعَة $h12 $periodText.");
    } else if (isTomorrow) {
      await _speak("تَمَام $userTitle، هَفَكَّرَكْ بُكْرَة $voiceOffsetPhrase، السَّاعَة $h12 $periodText.");
    } else {
      await _speak("تَمَام $userTitle، هَفَكَّرَكْ $voiceOffsetPhrase، السَّاعَة $h12 $periodText.");
    }
    return true;
  }

// ══════════════════════════════════════════════════════
// نهاية PART 7 / 8
// ══════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════
// PART 8 / 8 (الأخير)
// باقي دوال MainDashboard + كل الـ Widgets + _DiaryPage
// + _HijriCalendarWidget + _AdhkarCard + _TalkingImage
// + LoginScreen + PremiumScreen
// ══════════════════════════════════════════════════════

  String _formatTimeForDisplay(String time24) {
    try {
      final parts = time24.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final isPm = hour >= 12;
      final h12 = hour % 12 == 0 ? 12 : hour % 12;
      return '$h12:$minute ${isPm ? 'م' : 'ص'}';
    } catch (_) {
      return time24;
    }
  }

  Future<void> _scheduleEventReminder(Map<String, dynamic> event) async {
    try {
      final eventDate = DateTime.parse(event['eventDate'].toString());
      final reminderHour = event['reminderHour'] ?? _settings.defaultReminderHour;
      final reminderMinute = event['reminderMinute'] ?? _settings.defaultReminderMinute;
      final advanceDays = _getAdvanceDays(event['advanceReminder'] ?? 'قبلها بيوم');
      final interval = event['repeatInterval'] ?? 'مرة واحدة';
      final repeatType = event['repeatType'] ?? 'سنوي';
      final now = DateTime.now();

      final eventThisYear = DateTime(now.year, eventDate.month, eventDate.day);
      final reminderDate = eventThisYear.subtract(Duration(days: advanceDays));
      final reminderDateTime = DateTime(reminderDate.year, reminderDate.month, reminderDate.day, reminderHour, reminderMinute);

      if (reminderDateTime.isBefore(now)) return;

      await _scheduleEventNotification(event, reminderDateTime, interval, repeatType);

      final hasCustomSound = event['sound'] != null && event['sound'] != 'default';
      final eventText = (event['detail'] != null && event['detail'].toString().isNotEmpty)
          ? '${event['title']} - ${event['detail']}'
          : event['title'].toString();
      if (!hasCustomSound) {
        await _scheduleNativeAlarm(eventText, reminderDateTime, prefix: 'قربت مناسبة: ');
      }

      final diff = reminderDateTime.difference(now);

      late final Timer timer;
      timer = Timer(diff, () {
        _activeTimers.remove(timer);
        if (mounted && !_isInBackground) {
          _showEventReminder(event['title'].toString(), event['detail'].toString(), interval, hasCustomSound: hasCustomSound);
        }
      });
      _activeTimers.add(timer);
    } catch (_) {}
  }

  Future<void> _scheduleEventNotification(Map<String, dynamic> event, DateTime fireTime, String interval, String repeatType) async {
    try {
      final eventId = ('${event['title']}_${event['eventDate']}_${event['reminderHour']}_${event['reminderMinute']}').hashCode & 0x7FFFFFFF;
      final tzTime = tz.TZDateTime.from(fireTime, tz.local);

      final prefs = await SharedPreferences.getInstance();
      final finalSound = event['sound'] ?? prefs.getString('default_event_sound');

      final androidDetails = AndroidNotificationDetails(
        'event_channel_v1', 'تنبيهات المناسبات',
        channelDescription: 'تنبيهات المناسبات السنوية',
        importance: Importance.max, priority: Priority.max,
        playSound: true,
        sound: _getNotificationSound(finalSound),
        enableVibration: true,
        category: AndroidNotificationCategory.alarm,
        autoCancel: false, ongoing: true,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
      );

      final notificationBody = (event['detail'] != null && event['detail'].toString().isNotEmpty)
          ? 'قربت مناسبة: ${event['title']} - ${event['detail']}'
          : 'قربت مناسبة: ${event['title']}';

      DateTimeComponents? matchComponent;
      if (repeatType == 'أسبوعي') matchComponent = DateTimeComponents.dayOfWeekAndTime;
      else if (repeatType == 'شهري') matchComponent = DateTimeComponents.dayOfMonthAndTime;
      else matchComponent = DateTimeComponents.dateAndTime;

      await _notifications.zonedSchedule(
        eventId, '🎉 تذكير بمناسبة', notificationBody,
        tzTime, NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchComponent,
      );

      await prefs.setString('pending_event_announce', json.encode({
        'title': event['title'], 'detail': event['detail'],
        'interval': interval, 'scheduledMillis': fireTime.millisecondsSinceEpoch,
        'hasCustomSound': finalSound != null && finalSound != 'default',
      }));
    } catch (_) {}
  }

  int _getAdvanceDays(String advanceReminder) {
    switch (advanceReminder) {
      case 'في نفس اليوم': return 0;
      case 'قبلها بيوم': return 1;
      case 'قبلها بـ 3 أيام': return 3;
      case 'قبلها بأسبوع': return 7;
      case 'قبلها بـ 10 أيام': return 10;
      case 'قبلها بشهر': return 30;
      default: return 1;
    }
  }

  Future<void> _showEventReminder(String title, String detail, String interval, {bool hasCustomSound = false}) async {
    if (_eventDialogShowing) return;
    _eventDialogShowing = true;
    _eventAnnouncing = true;

    HapticFeedback.vibrate();
    WakelockPlus.enable();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_event_announce');
    } catch (_) {}

    void speakAlert() {
      if (!hasCustomSound) {
        _speak("تَنْبِيه: قَرَبِتْ مُنَاسَبَة $title. $detail");
      }
      HapticFeedback.vibrate();
    }

    if (interval != 'بدون تنبيه' && !hasCustomSound) speakAlert();

    _eventRepeatTimer?.cancel();
    int secs = _getIntervalSeconds(interval);
    if (secs > 0 && interval != 'مرة واحدة' && !hasCustomSound) {
      _eventRepeatTimer = Timer.periodic(Duration(seconds: secs), (_) => speakAlert());
    }

    if (!mounted) {
      _eventDialogShowing = false;
      _eventAnnouncing = false;
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2A4A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.celebration, color: Color(0xFFC5A059), size: 30), SizedBox(width: 10), Text('تذكير بمناسبة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
        content: Text('قَرَبِتْ مُنَاسَبَة: $title\n$detail', style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC5A059)),
            onPressed: () async {
              _eventRepeatTimer?.cancel();
              _tts.stop();
              WakelockPlus.disable();
              _eventAnnouncing = false;
              _eventDialogShowing = false;

              await _notifications.cancel(title.hashCode + detail.hashCode);
              try { await _nativeAlarmChannel.invokeMethod('stopAlarmService'); } catch (_) {}
              _cancelNativeAlarm('مناسبة: $title');
              Navigator.pop(ctx);
            },
            child: const Text('تمام', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _deleteTask(int index) {
    final task = _tasks[index];
    final taskTitle = task['task'].toString();
    final alarmId = task['alarmId'] as int?;

    if (alarmId != null) {
      try { _notifications.cancel(alarmId); } catch (_) {}
      _cancelNativeAlarm(taskTitle, customId: alarmId);
    } else {
      _cancelNativeAlarm(taskTitle);
    }

    setState(() => _tasks.removeAt(index));
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الموعد نهائياً')));
  }

  void _deleteWeeklyTask(int index) {
  final task = _weeklySchedule[index];
  final taskTitle = task['task'].toString();
  final day = task['day'].toString();
  final scheduled = DateTime.tryParse(task['scheduled']?.toString() ?? '');
  final hhmm = scheduled != null ? DateFormat('HHmm').format(scheduled) : '';
  final fullTitle = 'جدول_${day}_${hhmm}_$taskTitle';

  setState(() => _weeklySchedule.removeAt(index));
  _saveWeeklySchedule();
  _cancelNativeAlarm(fullTitle);
  try { _notifications.cancel(fullTitle.hashCode + 1000); } catch (_) {}
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف الموعد من $day')));
  }

  Future<void> _deleteAllWeeklyTasks() async {
  final userTitle = _userTitle;
  if (_weeklySchedule.isEmpty) {
    await _speak("الجَدْوَلُ الأُسْبُوعِيُّ فَاضِي أَصْلًا $_userTitle.");
    return;
  }
  final count = _weeklySchedule.length;
  for (final task in List.from(_weeklySchedule)) {
    final taskTitle = task['task'].toString();
    final day = task['day'].toString();
    final scheduled = DateTime.tryParse(task['scheduled']?.toString() ?? '');
    final hhmm = scheduled != null ? DateFormat('HHmm').format(scheduled) : '';
    final fullTitle = 'جدول_${day}_${hhmm}_$taskTitle';
    
    await _cancelNativeAlarm(fullTitle);
    try { await _notifications.cancel(fullTitle.hashCode + 1000); } catch (_) {}
  }
  setState(() => _weeklySchedule.clear());
  _saveWeeklySchedule();
  await _speak("تَمَّ مَسْحُ $count ${count == 1 ? "مَوْعِدْ" : "مَوَاعِيدْ"} مِنَ الجَدْوَلِ الأُسْبُوعِيِّ $_userTitle.");
  }
  
  void _openSettingsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: _settings,
          ttsVolume: _ttsVolume,
          currentSecretaryName: _secretaryName,
          currentIsUserMale: _isUserMale,
          isProUser: _isProUser,
          onAuthChanged: () {
  _checkProStatus();
  setState(() {});
},
          onUpgrade: () { // 👈
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => PremiumScreen(
              onActivated: () {
                setState(() => _isProUser = true);
              }
            )));
          },
          onSave: (hour, minute, voiceLevel, greeting, adhan, ttsVol, showLock, shakeMode, voiceGender, defaultInterval, customWakeWord, wakeWordMode, wakeWordTrigger, muteBeep, useOverlayAlarm, isKidsMode, customGreeting, tahajjudAlertEnabled, isDarkMode, customImagePath, stopRecordMode, snoozeMinutes, diaryLockEnabled, diaryPin, diarySecurityQuestion, diarySecurityAnswer) async {
            setState(() {
              _settings.defaultReminderHour = hour;
              _settings.defaultReminderMinute = minute;
              _settings.voiceLevel = voiceLevel;
              _settings.greetingEnabled = greeting;
              _settings.adhanAlertEnabled = adhan;
              _ttsVolume = ttsVol;
              _settings.showAboveLockScreen = showLock;
              _settings.shakeMode = shakeMode;
              _settings.muteBeep = muteBeep;
              _settings.voiceGender = voiceGender;
              _settings.defaultInterval = defaultInterval;
              _settings.customWakeWord = customWakeWord;
              _settings.wakeWordMode = wakeWordMode;
              _settings.wakeWordTrigger = wakeWordTrigger;
              _settings.useOverlayAlarm = useOverlayAlarm;
              _settings.isKidsMode = isKidsMode;
              _settings.customGreeting = customGreeting;
              _settings.tahajjudAlertEnabled = tahajjudAlertEnabled;
              _settings.isDarkMode = isDarkMode;
              _settings.customImagePath = customImagePath;
              _settings.stopRecordMode = stopRecordMode;
              _settings.snoozeMinutes = snoozeMinutes;
              _settings.diaryLockEnabled = diaryLockEnabled;
              _settings.diaryPin = diaryPin;
              _settings.diarySecurityQuestion = diarySecurityQuestion;
              _settings.diarySecurityAnswer = diarySecurityAnswer;
            });
            widget.onThemeChanged(isDarkMode);

            await _saveSettings();
            final prefs = await SharedPreferences.getInstance();
            _settings.salatAlaNabiEnabled = prefs.getBool('salat_ala_nabi_enabled') ?? false;
            _settings.salatAlaNabiInterval = prefs.getString('salat_ala_nabi_interval') ?? 'كل ساعة';
            _settings.customUserTitle = prefs.getString('custom_user_title') ?? '';
            _settings.customSecTitle = prefs.getString('custom_sec_title') ?? '';
            _scheduleSalatAlaNabi();

            Future.delayed(const Duration(milliseconds: 100), () async {
              try { _scheduleAdhan30Days(); } catch (_) {}
            });

            try { await _configureVoice(skipGreeting: true); } catch (_) {}

            try {
              if (showLock) {
                await _lockScreenChannel.invokeMethod('enableShowWhenLocked');
              } else {
                await _lockScreenChannel.invokeMethod('disableShowWhenLocked');
              }

              if (_settings.wakeWordMode == 'off') {
                try { await _wakeWordChannel.invokeMethod('stopWakeWord'); } catch (_) {}
              } else {
                try { await _wakeWordChannel.invokeMethod('startWakeWord'); } catch (_) {}
              }

              _initShakeDetector();
            } catch (_) {}
          },
          onSaveSecretary: (name, voiceGender) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('secretary_name', name);
            await prefs.setString('voice_gender', voiceGender);
            if (mounted) {
              setState(() {
                _secretaryName = name;
                _settings.voiceGender = voiceGender;
              });
            }
            Future.delayed(const Duration(milliseconds: 300), () {
              try { _configureVoice(skipGreeting: true); } catch (_) {}
            });
          },
        ),
      ),
    );
  }

  void _addNewTaskDialog() {
    _showTaskDialog();
  }

  void _editTaskDialog(int index) {
    _showTaskDialog(taskIndex: index);
  }

  Future<void> _showTaskDialog({int? taskIndex}) async {
    final prefs = await SharedPreferences.getInstance();
    final defaultSound = prefs.getString('default_alarm_sound');

    Map<String, dynamic>? existingTask;
    if (taskIndex != null) {
      existingTask = _tasks[taskIndex];
    }

    TextEditingController taskCtrl = TextEditingController(
      text: existingTask?['task']?.toString() ?? '',
    );
    TimeOfDay selectedTime = TimeOfDay.now();
    if (existingTask != null) {
      try {
        final t = DateFormat('hh:mm a', 'ar').parse(existingTask['time'].toString());
        selectedTime = TimeOfDay(hour: t.hour, minute: t.minute);
      } catch (_) {}
    }
    String selectedRepeat = existingTask?['repeat'] ?? 'مرة واحدة';
    String selectedInterval = existingTask?['repeatInterval'] ?? _settings.defaultInterval;
    String selectedAdvanceReminder = existingTask?['advanceReminder'] ?? 'في الموعد';
    List<String> selectedDays = List<String>.from(existingTask?['customDays'] ?? []);
    String? selectedSound = existingTask?['sound'] ?? defaultSound ?? (_isProUser ? null : 'system_alarm');
    final List<String> repeatOptions = ['مرة واحدة', 'يومي', 'كل يومين', 'أسبوعي', 'كل أسبوعين', 'شهري', 'مخصص'];
    final List<String> intervalOptions = ['بدون تنبيه', 'مرة واحدة', 'كل 10 ثواني', 'كل 20 ثانية', 'كل 30 ثانية', 'كل دقيقة', 'كل دقيقتين', 'كل 3 دقايق', 'كل 5 دقايق', 'كل 10 دقايق'];
    final List<String> advanceOptions = ['في الموعد', 'قبلها بـ 5 دقائق', 'قبلها بـ 10 دقائق', 'قبلها بـ 15 دقيقة', 'قبلها بـ 30 دقيقة', 'قبلها بساعة', 'قبلها ب 6 ساعات', 'قبلها ب 12 ساعة', 'قبلها بـ 24 ساعة'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(taskIndex == null ? 'إضافة موعد جديد' : 'تعديل الموعد',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: taskCtrl, decoration: const InputDecoration(labelText: 'تفاصيل المهمة')),
                const SizedBox(height: 15),
                if (selectedInterval != 'بدون تنبيه') ...[
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('الوقت: ${selectedTime.format(context)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(icon: const Icon(Icons.access_time, color: Color(0xFFC5A059)), label: const Text('تحديد'), onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: selectedTime);
                      if (t != null) setStateSB(() => selectedTime = t);
                    }),
                  ]),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedAdvanceReminder,
                    decoration: const InputDecoration(labelText: 'التذكير المسبق', border: OutlineInputBorder()),
                    items: advanceOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (val) => setStateSB(() => selectedAdvanceReminder = val ?? 'في الموعد'),
                  ),
                  const Divider(),
                  const Align(alignment: Alignment.centerRight, child: Text('التكرار:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedRepeat,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: repeatOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (val) => setStateSB(() => selectedRepeat = val ?? 'مرة واحدة'),
                  ),
                  if (selectedRepeat == 'مخصص') ...[
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerRight, child: Text('اختر الأيام:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    const SizedBox(height: 5),
                    Wrap(spacing: 5, runSpacing: 5, children: _weekDays.map((day) {
                      final isSelected = selectedDays.contains(day);
                      return FilterChip(
                        label: Text(day, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
                        selected: isSelected,
                        selectedColor: const Color(0xFF1B2A4A),
                        onSelected: (v) => setStateSB(() {
                          if (v) selectedDays.add(day);
                          else selectedDays.remove(day);
                        }),
                      );
                    }).toList()),
                  ],
                ],
                const Divider(),
                const Align(alignment: Alignment.centerRight, child: Text('التنبيه المستمر:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedInterval,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: intervalOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (val) => setStateSB(() => selectedInterval = val ?? _settings.defaultInterval),
                ),
                const Divider(),
                      Row(children: [
        const Icon(Icons.music_note, color: Color(0xFF1B2A4A)),
        const SizedBox(width: 8),
        const Text('🎵 الصوت:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            selectedSound == null || selectedSound == 'default' 
                ? 'الافتراضي' 
                : (selectedSound == 'system_alarm' ? 'منبه الهاتف' : 'مخصص'), 
            style: const TextStyle(fontSize: 13)
          )
        ),
        TextButton(
          onPressed: () async {
            final result = await showDialog<String>(
              context: context,
              builder: (_) => SoundPickerDialog(currentUri: selectedSound, voiceGender: _settings.voiceGender, isProUser: _isProUser),
            );
            if (result != null) {
              setStateSB(() => selectedSound = result == 'default' ? null : result);
            }
          },
          child: const Text('اختيار'),
        ),
      ]),
    ],
  ),
),
                
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () {
                if (taskCtrl.text.isNotEmpty) {
                  int advanceMins = _getAdvanceMinutes(selectedAdvanceReminder);
                  final scheduledDateTime = DateTime(
                    _selectedDate.year, _selectedDate.month, _selectedDate.day,
                    selectedTime.hour, selectedTime.minute,
                  ).subtract(Duration(minutes: advanceMins));

                  if (scheduledDateTime.isBefore(DateTime.now())) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ الموعد فات! اختر وقت مستقبلي'), backgroundColor: Colors.red));
                    return;
                  }

                  final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
                  final formattedTime = selectedTime.format(context);
                  final newAlarmId = taskIndex == null ? DateTime.now().millisecondsSinceEpoch % 1000000 : (existingTask?['alarmId'] as int? ?? DateTime.now().millisecondsSinceEpoch % 1000000);

                  if (taskIndex == null) {
                    setState(() {
                      _tasks.add({
                        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
                        'task': taskCtrl.text,
                        'time': selectedInterval == 'بدون تنبيه' ? 'بدون تنبيه' : selectedTime.format(context),
                        'alarm': selectedInterval != 'بدون تنبيه',
                        'scheduled': scheduledDateTime.toIso8601String(),
                        'repeat': selectedRepeat,
                        'repeatInterval': selectedInterval,
                        'customDays': selectedDays,
                        'sound': selectedSound,
                        'advanceReminder': selectedAdvanceReminder,
                        'alarmId': newAlarmId,
                      });
                    });
                  } else {
                    final oldAlarmId = existingTask?['alarmId'] as int?;
                    if (oldAlarmId != null) {
                      try { _notifications.cancel(oldAlarmId); } catch (_) {}
                      _cancelNativeAlarm(existingTask!['task'].toString(), customId: oldAlarmId);
                    }

                    setState(() {
                      _tasks[taskIndex] = {
                        'date': existingTask!['date'],
                        'task': taskCtrl.text,
                        'time': selectedInterval == 'بدون تنبيه' ? 'بدون تنبيه' : selectedTime.format(context),
                        'alarm': selectedInterval != 'بدون تنبيه',
                        'scheduled': scheduledDateTime.toIso8601String(),
                        'repeat': selectedRepeat,
                        'repeatInterval': selectedInterval,
                        'customDays': selectedDays,
                        'sound': selectedSound,
                        'advanceReminder': selectedAdvanceReminder,
                        'alarmId': newAlarmId,
                      };
                    });
                  }
                  _saveData();
                  if (selectedInterval != 'بدون تنبيه') {
                    _scheduleContinuousAlarm(
                      taskCtrl.text,
                      scheduledDateTime,
                      selectedRepeat,
                      selectedInterval,
                      selectedDays,
                      soundUri: selectedSound,
                      alarmId: newAlarmId,
                    );
                  }
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addWeeklyTaskDialog(String day) async { await _showWeeklyTaskDialog(day: day); }

  Future<void> _editWeeklyTaskDialog(int index) async {
    final task = _weeklySchedule[index];
    await _showWeeklyTaskDialog(day: task['day'].toString(), taskIndex: index);
  }

  Future<void> _showWeeklyTaskDialog({required String day, int? taskIndex}) async {
    final prefs = await SharedPreferences.getInstance();
    final defaultSound = prefs.getString('default_weekly_sound') ?? prefs.getString('default_alarm_sound');

    Map<String, dynamic>? existingTask;
    if (taskIndex != null) {
      existingTask = _weeklySchedule[taskIndex];
    }

    TextEditingController taskCtrl = TextEditingController(
      text: existingTask?['task']?.toString() ?? '',
    );
    TimeOfDay selectedTime = TimeOfDay.now();
    if (existingTask != null) {
      try {
        final t = DateFormat('hh:mm a', 'ar').parse(existingTask['time'].toString());
        selectedTime = TimeOfDay(hour: t.hour, minute: t.minute);
      } catch (_) {}
    }
    String selectedInterval = existingTask?['repeatInterval'] ?? _settings.defaultInterval;
    String selectedAdvanceReminder = existingTask?['advanceReminder'] ?? 'في الموعد';
    String? selectedSound = existingTask?['sound'] ?? defaultSound ?? (_isProUser ? null : 'system_alarm');
    final List<String> intervalOptions = ['بدون تنبيه', 'مرة واحدة', 'كل 10 ثواني', 'كل 20 ثانية', 'كل 30 ثانية', 'كل دقيقة', 'كل دقيقتين', 'كل 3 دقايق', 'كل 5 دقايق', 'كل 10 دقايق'];
    final List<String> advanceOptions = ['في الموعد', 'قبلها بـ 5 دقائق', 'قبلها بـ 10 دقائق', 'قبلها بـ 15 دقيقة', 'قبلها بـ 20 دقيقة', 'قبلها بـ 30 دقيقة', 'قبلها بـ 45 دقيقة', 'قبلها بساعة', 'قبلها بساعتين', 'قبلها ب 6 ساعات', 'قبلها ب 12 ساعة', 'قبلها بـ 24 ساعة'];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(
            taskIndex == null ? 'إضافة موعد ليوم $day' : 'تعديل موعد $day',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: taskCtrl, decoration: const InputDecoration(labelText: 'تفاصيل المهمة')),
                const SizedBox(height: 15),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('الوقت: ${selectedTime.format(context)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(icon: const Icon(Icons.access_time, color: Color(0xFFC5A059)), label: const Text('تحديد'), onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: selectedTime);
                    if (t != null) setStateSB(() => selectedTime = t);
                  }),
                ]),
                const Divider(),
                const Align(alignment: Alignment.centerRight, child: Text('التذكير المسبق:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedAdvanceReminder,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: advanceOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (val) => setStateSB(() => selectedAdvanceReminder = val ?? 'في الموعد'),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const Align(alignment: Alignment.centerRight, child: Text('التنبيه المستمر:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedInterval,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: intervalOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (val) => setStateSB(() => selectedInterval = val ?? _settings.defaultInterval),
                ),
                const Divider(),
                Row(children: [
  const Icon(Icons.music_note, color: Color(0xFF1B2A4A)),
  const SizedBox(width: 8),
  const Text('🎵 الصوت:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
  const SizedBox(width: 8),
  Expanded(
    child: Text(
      selectedSound == null || selectedSound == 'default' 
          ? 'الافتراضي' 
          : (selectedSound == 'system_alarm' ? 'منبه الهاتف' : 'مخصص'), 
      style: const TextStyle(fontSize: 13)
    )
  ),
  TextButton(
    onPressed: () async {
      final result = await showDialog<String>(
        context: context,
        builder: (_) => SoundPickerDialog(currentUri: selectedSound, voiceGender: _settings.voiceGender, isProUser: _isProUser),
      );
      if (result != null) {
        setStateSB(() => selectedSound = result == 'default' ? null : result);
      }
    },
    child: const Text('اختيار'),
  ),
]),
                
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () {
                if (taskCtrl.text.isNotEmpty) {
                  final now = DateTime.now();
                  final dayIndex = _weekDays.indexOf(day);
                  final todayIndex = (now.weekday) % 7;
                  final daysAhead = (dayIndex - todayIndex + 7) % 7;
                  final targetDate = now.add(Duration(days: daysAhead));
                  final scheduledDateTime = DateTime(
                    targetDate.year, targetDate.month, targetDate.day,
                    selectedTime.hour, selectedTime.minute,
                  );

                  if (scheduledDateTime.isBefore(DateTime.now())) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ الموعد فات! اختر وقت مستقبل'), backgroundColor: Colors.red));
                    return;
                  }

                  if (taskIndex == null) {
                    setState(() {
                      _weeklySchedule.add({
                        'day': day,
                        'task': taskCtrl.text,
                        'time': selectedTime.format(context),
                        'scheduled': scheduledDateTime.toIso8601String(),
                        'repeatInterval': selectedInterval,
                        'advanceReminder': selectedAdvanceReminder,
                        'sound': selectedSound,
                      });
                    });
                  } else {
                    setState(() {
                      _weeklySchedule[taskIndex] = {
                        'day': day,
                        'task': taskCtrl.text,
                        'time': selectedTime.format(context),
                        'scheduled': scheduledDateTime.toIso8601String(),
                        'repeatInterval': selectedInterval,
                        'advanceReminder': selectedAdvanceReminder,
                        'sound': selectedSound,
                      };
                    });
                  }
                  _saveWeeklySchedule();
                  if (selectedInterval != 'بدون تنبيه') {
                    _scheduleWeeklyAlarm(
                      taskCtrl.text,
                      day,
                      scheduledDateTime,
                      selectedInterval,
                      selectedAdvanceReminder,
                      soundUri: selectedSound,
                    );
                  }
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _addSpecialEventDialog() {
    _showEventDialog();
  }

  void _editSpecialEventDialog(int index) {
    _showEventDialog(eventIndex: index);
  }

  Future<void> _showEventDialog({int? eventIndex}) async {
    final prefs = await SharedPreferences.getInstance();
    final defaultEventSound = prefs.getString('default_event_sound');

    Map<String, dynamic>? existingEvent;
    if (eventIndex != null) {
      existingEvent = _specialEvents[eventIndex];
    }

    TextEditingController titleCtrl = TextEditingController(text: existingEvent?['title']?.toString() ?? '');
    TextEditingController detailCtrl = TextEditingController(text: existingEvent?['detail']?.toString() ?? '');
    TextEditingController phoneCtrl = TextEditingController(text: existingEvent?['phone']?.toString() ?? '');
    String selectedAdvanceReminder = existingEvent?['advanceReminder'] ?? 'قبلها بيوم';
    String selectedInterval = existingEvent?['repeatInterval'] ?? 'مرة واحدة';
    String selectedRepeatType = existingEvent?['repeatType'] ?? 'سنوي';
    String? selectedSound = existingEvent?['sound'] ?? defaultEventSound ?? (_isProUser ? null : 'system_alarm');
    DateTime selectedEventDate = DateTime.now();
    if (existingEvent != null) {
      try {
        selectedEventDate = DateTime.parse(existingEvent['eventDate'].toString());
      } catch (_) {}
    }
    TimeOfDay reminderTime = TimeOfDay(
      hour: existingEvent?['reminderHour'] ?? _settings.defaultReminderHour,
      minute: existingEvent?['reminderMinute'] ?? _settings.defaultReminderMinute,
    );

    final List<String> reminderOptions = ['في نفس اليوم', 'قبلها بيوم', 'قبلها بـ 3 أيام', 'قبلها بأسبوع', 'قبلها بـ 10 أيام', 'قبلها بشهر'];
    final List<String> intervalOptions = ['بدون تنبيه', 'مرة واحدة', 'كل 10 ثواني', 'كل 20 ثانية', 'كل 30 ثانية', 'كل دقيقة', 'كل دقيقتين', 'كل 3 دقايق', 'كل 5 دقايق', 'كل 10 دقايق'];
    final List<String> repeatTypeOptions = ['سنوي', 'شهري', 'أسبوعي'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(eventIndex == null ? 'إضافة مناسبة' : 'تعديل المناسبة',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'اسم المناسبة')),
                const SizedBox(height: 10),
                TextField(controller: detailCtrl, decoration: const InputDecoration(labelText: 'التفاصيل/الاسم')),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'رقم التليفون (اختياري)'),
                ),
                const SizedBox(height: 15),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('التاريخ: ${DateFormat('yyyy/MM/dd').format(selectedEventDate)}'),
                  trailing: const Icon(Icons.calendar_today, color: Color(0xFF1B2A4A)),
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: selectedEventDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (picked != null) setStateSB(() => selectedEventDate = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('وقت التذكير: ${DateFormat('hh:mm a', 'ar').format(DateTime(2024, 1, 1, reminderTime.hour, reminderTime.minute))}'),
                  trailing: const Icon(Icons.access_time, color: Color(0xFF1B2A4A)),
                  onTap: () async {
                    final picked = await showTimePicker(context: context, initialTime: reminderTime);
                    if (picked != null) setStateSB(() => reminderTime = picked);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedAdvanceReminder,
                  decoration: const InputDecoration(labelText: 'التذكير المسبق', border: OutlineInputBorder()),
                  items: reminderOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                  onChanged: (val) => setStateSB(() => selectedAdvanceReminder = val ?? selectedAdvanceReminder),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedInterval,
                  decoration: const InputDecoration(labelText: 'التنبيه المستمر', border: OutlineInputBorder()),
                  items: intervalOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                  onChanged: (val) => setStateSB(() => selectedInterval = val ?? 'مرة واحدة'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRepeatType,
                  decoration: const InputDecoration(labelText: 'نوع التكرار', border: OutlineInputBorder()),
                  items: repeatTypeOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                  onChanged: (val) => setStateSB(() => selectedRepeatType = val ?? 'سنوي'),
                ),
                const Divider(),
                Row(children: [
  const Icon(Icons.music_note, color: Color(0xFF1B2A4A)),
  const SizedBox(width: 8),
  const Text('🎵 الصوت:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
  const SizedBox(width: 8),
  Expanded(
    child: Text(
      selectedSound == null || selectedSound == 'default' 
          ? 'الافتراضي' 
          : (selectedSound == 'system_alarm' ? 'منبه الهاتف' : 'مخصص'), 
      style: const TextStyle(fontSize: 13)
    )
  ),
  TextButton(
    onPressed: () async {
      final result = await showDialog<String>(
        context: context,
        builder: (_) => SoundPickerDialog(currentUri: selectedSound, voiceGender: _settings.voiceGender, isProUser: _isProUser),
      );
      if (result != null) {
        setStateSB(() => selectedSound = result == 'default' ? null : result);
      }
    },
    child: const Text('اختيار'),
  ),
]),

              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  final newEvent = {
                    'title': titleCtrl.text,
                    'detail': detailCtrl.text.isEmpty ? 'مناسبة سنوية' : detailCtrl.text,
                    'phone': phoneCtrl.text,
                    'advanceReminder': selectedAdvanceReminder,
                    'eventDate': selectedEventDate.toIso8601String(),
                    'reminderHour': reminderTime.hour,
                    'reminderMinute': reminderTime.minute,
                    'repeatInterval': selectedInterval,
                    'repeatType': selectedRepeatType,
                    'sound': selectedSound,
                  };
                  if (eventIndex == null) {
  setState(() => _specialEvents.add(newEvent));
} else {
  final oldEventText = (existingEvent!['detail'] != null && existingEvent['detail'].toString().isNotEmpty)
      ? '${existingEvent['title']} - ${existingEvent['detail']}'
      : existingEvent['title'].toString();
  _cancelNativeAlarm(oldEventText);
  setState(() => _specialEvents[eventIndex] = newEvent);
                  }
                  _sortByTime(_specialEvents);
                  _saveData();
                  _scheduleEventReminder(newEvent);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeviceBlocked) {
  return Scaffold(
    backgroundColor: const Color(0xFF1B2A4A),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.devices_other, size: 80, color: Colors.redAccent),
            const SizedBox(height: 20),
            const Text(
              'لقد وصلت للحد الأقصى للأجهزة المسموح بها لهذا الحساب (3 أجهزة).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'للاستمرار، يرجى إزالة أحد الأجهزة الأخرى من القائمة أدناه.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC5A059),
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.settings, color: Colors.black),
              label: const Text('إدارة الأجهزة المتصلة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              onPressed: () => _showManageDevicesDialog(context),
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => LoginScreen()),
                    (route) => false,
                  );
                }
              },
              child: const Text('تسجيل الخروج', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    ),
  );
    }
    final List<Widget> screens = [
      _buildCalendarTab(),
      _buildDiariesTab(),
      _buildPrayerTimesTab(),
      _buildSpecialEventsTab(),
      _buildRecorderTab(),
    ];

    Widget? fab;
    if (_isRecording) {
      fab = FloatingActionButton.extended(
        onPressed: _stopRecording,
        backgroundColor: Colors.red,
        icon: const Icon(Icons.stop, color: Colors.white),
        label: Text('إيقاف التسجيل (${_formatDuration(_recordingDuration)})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      );
    } else if (_currentIndex == 0 && _calendarSubView == 'calendar') {
      fab = FloatingActionButton.extended(
        onPressed: _addNewTaskDialog,
        backgroundColor: const Color(0xFF1B2A4A),
        icon: const Icon(Icons.add, color: Color(0xFFC5A059)),
        label: const Text('إضافة موعد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      );
    } else if (_currentIndex == 3) {
      fab = FloatingActionButton.extended(
        onPressed: _addSpecialEventDialog,
        backgroundColor: const Color(0xFF1B2A4A),
        icon: const Icon(Icons.card_giftcard, color: Color(0xFFC5A059)),
        label: const Text('إضافة مناسبة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B2A4A),
        foregroundColor: Colors.white,
        elevation: 3,
        title: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFC5A059),
            child: ClipOval(
              child: _settings.customImagePath != null
                  ? Image.file(File(_settings.customImagePath!), width: 44, height: 44, fit: BoxFit.cover)
                  : Image.asset(_getSecretaryImage(_secretaryName, _settings.voiceGender), width: 44, height: 44, fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: (c, e, s) => const Icon(Icons.face_3, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$_secTitle: $_secretaryName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Text('هز الهاتف للتحدث', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ]),
        actions: [
          // 👇 أيقونة التاج للبرو
          if (!_isProUser)
            IconButton(
              icon: const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
              tooltip: 'الترقية للنسخة البرو',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => PremiumScreen(
                  onActivated: () => setState(() => _isProUser = true),
                )));
              },
            ),
          IconButton(
            icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? Colors.redAccent : const Color(0xFFC5A059)),
            onPressed: _isRecording ? null : _listenVoiceCommand,
          ),
          IconButton(icon: const Icon(Icons.settings, color: Color(0xFFC5A059)), onPressed: _openSettingsScreen),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: ValueKey<int>(_currentIndex), child: screens[_currentIndex]),
      ),
      floatingActionButton: fab,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            _isHijriView = false;
          });
        },
        selectedItemColor: const Color(0xFF1B2A4A),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'التقويم'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'يومياتي'),
          BottomNavigationBarItem(icon: Icon(Icons.access_time_filled), label: 'الصلاة'),
          BottomNavigationBarItem(icon: Icon(Icons.stars), label: 'المناسبات'),
          BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'المسجل'),
        ],
      ),
    );
  }

  Widget _buildCalendarTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _calendarSubView = 'calendar'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _calendarSubView == 'calendar' ? const Color(0xFF1B2A4A) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_month, color: _calendarSubView == 'calendar' ? const Color(0xFFC5A059) : Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Text('التقويم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _calendarSubView == 'calendar' ? Colors.white : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _calendarSubView = 'weekly'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _calendarSubView == 'weekly' ? const Color(0xFF1B2A4A) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.view_week, color: _calendarSubView == 'weekly' ? const Color(0xFFC5A059) : Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Text('الجدول الأسبوعي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _calendarSubView == 'weekly' ? Colors.white : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _calendarSubView == 'calendar' ? _buildCalendarAndTasksTab() : _buildWeeklyScheduleView(),
        ),
      ],
    );
  }

  Widget _buildWeeklyScheduleView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF2C3E50)], begin: Alignment.topRight, end: Alignment.bottomLeft),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📆 الجدول الأسبوعي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 5),
                Text('اضغط على أي يوم لعرض مواعيده وإضافتها', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.3),
            itemCount: _weekDays.length,
            itemBuilder: (ctx, i) {
              final day = _weekDays[i];
              final dayTasks = _weeklySchedule.where((t) => t['day'] == day).toList();
              return InkWell(
                onTap: () => _openDayView(day),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFC5A059), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(day, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFC5A059))),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: dayTasks.isEmpty ? Colors.grey.shade200 : const Color(0xFFC5A059),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            dayTasks.isEmpty ? 'فاضي' : '${dayTasks.length} ${dayTasks.length == 1 ? "موعد" : "مواعيد"}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dayTasks.isEmpty ? Colors.grey.shade700 : Colors.black),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openDayView(String day) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setStateInner) {
            final dayTasks = _weeklySchedule.where((t) => t['day'] == day).toList();
            _sortByTime(dayTasks);
            return Scaffold(
              appBar: AppBar(
                title: Text('مواعيد يوم $day', style: const TextStyle(fontWeight: FontWeight.bold)),
                backgroundColor: const Color(0xFF1B2A4A),
                foregroundColor: Colors.white,
              ),
              body: dayTasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy, size: 80, color: Colors.grey.shade400),
                          const SizedBox(height: 15),
                          Text('مفيش مواعيد في يوم $day', style: const TextStyle(color: Colors.grey, fontSize: 15)),
                          const SizedBox(height: 25),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            icon: const Icon(Icons.add, color: Color(0xFFC5A059)),
                            label: const Text('إضافة موعد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              await _addWeeklyTaskDialog(day);
                              setStateInner(() {});
                            },
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: dayTasks.length,
                      itemBuilder: (ctx, i) {
                        final task = dayTasks[i];
                        final globalIndex = _weeklySchedule.indexOf(task);
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: const Border(right: BorderSide(color: Color(0xFFC5A059), width: 5)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.alarm, color: Color(0xFFC5A059)),
                            title: Text(task['task'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            subtitle: Text('${task['time']} • ${task['repeatInterval']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () async {
                                    await _editWeeklyTaskDialog(globalIndex);
                                    setStateInner(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () async {
                                    _deleteWeeklyTask(globalIndex);
                                    setStateInner(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              floatingActionButton: dayTasks.isNotEmpty
                  ? FloatingActionButton.extended(
                      onPressed: () async {
                        await _addWeeklyTaskDialog(day);
                        setStateInner(() {});
                      },
                      backgroundColor: const Color(0xFF1B2A4A),
                      icon: const Icon(Icons.add, color: Color(0xFFC5A059)),
                      label: const Text('إضافة موعد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }

  Widget _buildCalendarAndTasksTab() {
    String formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String currentTime = DateFormat('hh:mm a', 'ar').format(DateTime.now());
    var dayTasks = _getTasksForDate(_selectedDate);
    if (_showOnlyRecurring) {
      dayTasks = dayTasks.where((t) => (t['repeat'] ?? 'مرة واحدة') != 'مرة واحدة').toList();
    }
    _sortByTime(dayTasks);
    String userTitle = _userTitle;
    return SingleChildScrollView(
      child: Column(children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF2C3E50)], begin: Alignment.topRight, end: Alignment.bottomLeft),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            Container(
              width: 70, height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFC5A059), width: 2),
                image: DecorationImage(
                  image: _settings.customImagePath != null ? FileImage(File(_settings.customImagePath!)) as ImageProvider : AssetImage(_getSecretaryImage(_secretaryName, _settings.voiceGender)),
                  fit: BoxFit.cover, alignment: Alignment.topCenter,
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مرحباً بك $userTitle! 👋', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('الوقت: $currentTime', style: const TextStyle(fontSize: 13, color: Color(0xFFC5A059), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('📳 هُز الهاتف أو نادِ باسم $_secTitle.', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
          ]),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              _isHijriView = !_isHijriView;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _isHijriView
                  ? const Color(0xFFC5A059).withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isHijriView
                    ? const Color(0xFFC5A059)
                    : Colors.grey.withOpacity(0.5),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('dd MMMM yyyy', 'ar').format(_selectedDate),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _isHijriView ? Colors.black87 : const Color(0xFF1B2A4A),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '|',
                  style: TextStyle(
                    fontSize: 16,
                    color: _isHijriView ? Colors.black87 : const Color(0xFF1B2A4A),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getHijriDate(_selectedDate),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _isHijriView ? const Color(0xFFC5A059) : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC5A059), width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
          ),
          child: _isHijriView
              ? _HijriCalendarWidget(
                  selectedDate: _selectedDate,
                  onDateChanged: (d) => setState(() => _selectedDate = d),
                )
              : CalendarDatePicker(
                  key: ValueKey(formattedDate),
                  initialDate: _selectedDate,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2030),
                  onDateChanged: (d) => setState(() => _selectedDate = d),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('كل المهام', style: TextStyle(fontSize: 12)),
                selected: !_showOnlyRecurring,
                onSelected: (val) => setState(() => _showOnlyRecurring = false),
              ),
              const SizedBox(width: 10),
              ChoiceChip(
                label: const Text('🔄 المتكررة فقط', style: TextStyle(fontSize: 12)),
                selected: _showOnlyRecurring,
                onSelected: (val) => setState(() => _showOnlyRecurring = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('جدول أعمال اليوم:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
              Chip(label: Text('${dayTasks.length} مواعيد', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1B2A4A)),
            ],
          ),
        ),
        dayTasks.isEmpty
            ? Container(
                padding: const EdgeInsets.all(30),
                child: Column(children: [
                  Icon(Icons.event_note, size: 50, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  const Text('لا توجد مواعيد', style: TextStyle(color: Colors.grey, fontSize: 14))
                ]))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dayTasks.length,
                itemBuilder: (ctx, i) {
                  final repeatType = dayTasks[i]['repeat'] ?? 'مرة واحدة';
                  IconData leadingIcon = Icons.alarm;
                  Color leadingColor = const Color(0xFFC5A059);

                  if (repeatType == 'يومي') { leadingIcon = Icons.loop; leadingColor = Colors.blue; }
                  else if (repeatType == 'كل يومين') { leadingIcon = Icons.loop; leadingColor = Colors.lightBlue; }
                  else if (repeatType == 'أسبوعي') { leadingIcon = Icons.date_range; leadingColor = Colors.green; }
                  else if (repeatType == 'كل أسبوعين') { leadingIcon = Icons.date_range; leadingColor = Colors.lightGreen; }
                  else if (repeatType == 'شهري') { leadingIcon = Icons.calendar_month; leadingColor = Colors.purple; }
                  else if (repeatType == 'مخصص') { leadingIcon = Icons.event_repeat; leadingColor = Colors.orange; }

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(right: BorderSide(color: leadingColor, width: 5)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5)],
                    ),
                    child: ListTile(
                      leading: Icon(leadingIcon, color: leadingColor),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              dayTasks[i]['task'].toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (repeatType != 'مرة واحدة')
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: leadingColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: leadingColor.withOpacity(0.5)),
                              ),
                              child: Text(
                                repeatType,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: leadingColor),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text('${dayTasks[i]['time']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          dayTasks[i]['alarm'] == true ? const Icon(Icons.notifications_active, color: Colors.redAccent) : const Icon(Icons.notifications_off, color: Colors.grey),
                          IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _editTaskDialog(_tasks.indexOf(dayTasks[i]))),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteTask(_tasks.indexOf(dayTasks[i]))),
                        ],
                      ),
                    ),
                  );
                },
              ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildDiariesTab() {
    return SingleChildScrollView(
      child: Column(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFF1B2A4A), borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('📖 مفكرة اليوميات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    SizedBox(height: 5),
                    Text('اختر أي يوم لفتح صفحة التدوين.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 30),
                tooltip: 'مسح كل اليوميات',
                onPressed: () async {
                  // 👇 التعديل: التحقق من الباسورد
                  if (_settings.diaryLockEnabled && _settings.diaryPin.isNotEmpty) {
                    final unlocked = await _showDiaryPinDialog();
                    if (!unlocked) return;
                  }
                  
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      title: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                          SizedBox(width: 8),
                          Text('مسح كل اليوميات', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        ],
                      ),
                      content: const Text('هل أنت متأكد أنك تريد مسح كل اليوميات المسجلة في التطبيق نهائياً؟ لا يمكن التراجع عن هذا الإجراء.', style: TextStyle(fontSize: 16)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إلغاء', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () async {
                            setState(() {
                              _diaries.clear();
                            });
                            await _saveData();
                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم مسح كل اليوميات بنجاح'), backgroundColor: Colors.green),
                              );
                            }
                          },
                          child: const Text('مسح الكل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC5A059), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
          ),
          child: CalendarDatePicker(
            initialDate: _diaryDate,
            firstDate: DateTime(2024),
            lastDate: DateTime(2030),
            onDateChanged: (selectedDay) {
              setState(() => _diaryDate = selectedDay);
              _openDiaryPage(selectedDay);
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A), minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            icon: const Icon(Icons.edit_note, color: Color(0xFFC5A059)),
            label: const Text('فتح يومية اليوم', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => _openDiaryPage(_diaryDate),
          ),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildPrayerTimesTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _prayerSubView = 'times'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _prayerSubView == 'times' ? const Color(0xFF1B2A4A) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.access_time_filled, color: _prayerSubView == 'times' ? const Color(0xFFC5A059) : Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Text('المواقيت', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _prayerSubView == 'times' ? Colors.white : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _prayerSubView = 'adhkar'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _prayerSubView == 'adhkar' ? const Color(0xFF1B2A4A) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.menu_book, color: _prayerSubView == 'adhkar' ? const Color(0xFFC5A059) : Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Text('الأذكار', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _prayerSubView == 'adhkar' ? Colors.white : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _prayerSubView = 'tasbeeh'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _prayerSubView == 'tasbeeh' ? const Color(0xFF1B2A4A) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app, color: _prayerSubView == 'tasbeeh' ? const Color(0xFFC5A059) : Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Text('التسبيح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _prayerSubView == 'tasbeeh' ? Colors.white : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _prayerSubView == 'times'
              ? _buildPrayerTimesList()
              : _prayerSubView == 'adhkar'
                  ? _buildAdhkarList()
                  : _buildTasbeehCounter(),
        ),
      ],
    );
  }

  Widget _buildPrayerTimesList() {
    return FutureBuilder<Map<String, String>>(
      future: _calculatePrayerTimes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final times = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _prayerCard('الفجر', _formatTimeForDisplay(times['fajr']!), Icons.wb_twilight),
            _prayerCard('الشروق', _formatTimeForDisplay(times['sunrise']!), Icons.wb_sunny_outlined),
            _prayerCard('الظهر', _formatTimeForDisplay(times['dhuhr']!), Icons.wb_sunny),
            _prayerCard('العصر', _formatTimeForDisplay(times['asr']!), Icons.filter_drama),
            _prayerCard('المغرب', _formatTimeForDisplay(times['maghrib']!), Icons.nights_stay_outlined),
            _prayerCard('العشاء', _formatTimeForDisplay(times['isha']!), Icons.nights_stay),
          ],
        );
      },
    );
  }

  Widget _buildTasbeehCounter() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF2C3E50)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text('إجمالي التسبيح', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              Text('$_tasbeehCount', style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold, color: Color(0xFFC5A059))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () async {
                      setState(() {
                        _tasbeehCount++;
                      });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('tasbeeh_count', _tasbeehCount);
                      HapticFeedback.lightImpact();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        color: Color(0xFFC5A059),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.black, size: 36),
                    ),
                  ),
                  const SizedBox(width: 60),
                  GestureDetector(
                    onTap: () async {
                      setState(() {
                        _tasbeehCount = 0;
                        _tasbeehSubCounts.clear();
                      });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('tasbeeh_count', 0);
                      for (var item in _tasbeehItems) {
                        await prefs.setInt('tasbeeh_${item['key']}', 0);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                      ),
                      child: const Icon(Icons.refresh, color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._tasbeehItems.map((item) {
          final key = item['key']!;
          final text = item['text']!;
          final count = _tasbeehSubCounts[key] ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC5A059).withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'تصفير هذا العداد',
                    onPressed: () async {
                      setState(() {
                        _tasbeehCount -= (_tasbeehSubCounts[key] ?? 0);
                        if (_tasbeehCount < 0) _tasbeehCount = 0;
                        _tasbeehSubCounts[key] = 0;
                      });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('tasbeeh_$key', 0);
                      await prefs.setInt('tasbeeh_count', _tasbeehCount);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF1B2A4A), borderRadius: BorderRadius.circular(20)),
                  child: Text('$count', style: const TextStyle(color: Color(0xFFC5A059), fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Color(0xFFC5A059), size: 30),
                  onPressed: () async {
                    setState(() {
                      _tasbeehSubCounts[key] = count + 1;
                      _tasbeehCount++;
                    });
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('tasbeeh_$key', _tasbeehSubCounts[key]!);
                    await prefs.setInt('tasbeeh_count', _tasbeehCount);
                  },
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(50)),
          icon: const Icon(Icons.refresh, color: Colors.white),
          label: const Text('تصفير كل العدادات', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: () async {
            setState(() { _tasbeehCount = 0; _tasbeehSubCounts = {}; });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('tasbeeh_count', 0);
            for (var item in _tasbeehItems) {
              await prefs.setInt('tasbeeh_${item['key']}', 0);
            }
          },
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _isTasbeehMode ? Colors.green : const Color(0xFF1B2A4A),
            minimumSize: const Size.fromHeight(50),
          ),
          icon: Icon(_isTasbeehMode ? Icons.mic : Icons.mic_none, color: Colors.white),
          label: Text(
            _isTasbeehMode ? 'إيقاف وضع التسبيح الصوتي' : 'تشغيل وضع التسبيح الصوتي',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onPressed: () {
            setState(() {
              _isTasbeehMode = !_isTasbeehMode;
              if (_isTasbeehMode) _isAdhkarMode = false;
            });
            if (_isTasbeehMode) { _listenVoiceCommand(); } else { _speech.stop(); }
          },
        ),
      ],
    );
  }

  Widget _buildAdhkarList() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: Color(0xFFC5A059),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFFC5A059),
            tabs: [
              Tab(text: 'الصباح'),
              Tab(text: 'المساء'),
              Tab(text: 'النوم'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAdhkarSectionList(_morningAdhkarList, 'الصباح'),
                _buildAdhkarSectionList(_eveningAdhkarList, 'المساء'),
                _buildAdhkarSectionList(_sleepAdhkarList, 'النوم'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isAdhkarMode ? Colors.green : const Color(0xFF1B2A4A),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(_isAdhkarMode ? Icons.mic : Icons.mic_none, color: Colors.white),
              label: Text(
                _isAdhkarMode ? 'إيقاف وضع الأذكار الصوتي' : 'تشغيل وضع الأذكار الصوتي',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                setState(() {
                  _isAdhkarMode = !_isAdhkarMode;
                  if (_isAdhkarMode) _isTasbeehMode = false;
                });
                if (_isAdhkarMode) { _listenVoiceCommand(); } else { _speech.stop(); }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdhkarSectionList(List<Map<String, dynamic>> adhkarList, String title) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('أذكار $title', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2A4A))),
              TextButton.icon(
                onPressed: () {
                  setState(() { for (var item in adhkarList) { _adhkarCounts.remove(item['text']); } });
                  _saveAdhkarCounts();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إعادة أذكار $title'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)));
                },
                icon: const Icon(Icons.refresh, color: Colors.redAccent, size: 20),
                label: const Text('إعادة', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: adhkarList.length,
            itemBuilder: (ctx, i) {
              final text = adhkarList[i]['text'];
              _adhkarCounts.putIfAbsent(text, () => adhkarList[i]['count']);

              return _AdhkarCard(
                text: text,
                count: _adhkarCounts[text] ?? 0,
                onDecrement: () {
                  setState(() {
                    if ((_adhkarCounts[text] ?? 0) > 0) {
                      _adhkarCounts[text] = (_adhkarCounts[text] ?? 0) - 1;
                    }
                  });
                  _saveAdhkarCounts();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _prayerCard(String title, String time, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFC5A059)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        trailing: Text(time, style: const TextStyle(color: Color(0xFFC5A059), fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSpecialEventsTab() {
    final sortedEvents = List<Map<String, dynamic>>.from(_specialEvents);
    _sortByTime(sortedEvents);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('المناسبات والتنبيهات:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC5A059))),
        const SizedBox(height: 10),
        InkWell(
          onTap: _addSpecialEventDialog,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const ListTile(
              leading: Icon(Icons.cake, color: Colors.pink, size: 32),
              title: Text('أعياد الميلاد (اضغط للإضافة)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('تنبيهات مسبقة'),
              trailing: Icon(Icons.add_circle, color: Color(0xFFC5A059)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('قائمة المناسبات:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC5A059))),
        const SizedBox(height: 10),
        if (sortedEvents.isEmpty)
          Container(
            padding: const EdgeInsets.all(30),
            child: Column(children: [
              Icon(Icons.stars, size: 50, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              const Text('لا توجد مناسبات', style: TextStyle(color: Colors.grey, fontSize: 14))
            ]),
          )
        else
          ...sortedEvents.asMap().entries.map((entry) {
            final i = _specialEvents.indexOf(entry.value);
            final e = entry.value;
            final eventDate = DateTime.tryParse(e['eventDate'] ?? '') ?? DateTime.now();
            final now = DateTime.now();
            final thisYear = DateTime(now.year, eventDate.month, eventDate.day);
            final nextYear = DateTime(now.year + 1, eventDate.month, eventDate.day);
            final nextOccurrence = thisYear.isAfter(now) ? thisYear : nextYear;
            final remaining = _formatRemaining(nextOccurrence);
final rH = e['reminderHour'] ?? 18;
final rM = e['reminderMinute'] ?? 0;
final reminderTime = DateFormat('hh:mm a', 'en').format(DateTime(2024, 1, 1, rH, rM)).replaceAll('PM', 'م').replaceAll('AM', 'ص');
final repeatInterval = e['repeatInterval'] ?? 'مرة واحدة';
            final repeatType = e['repeatType'] ?? 'سنوي';
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: ListTile(
                leading: const Icon(Icons.stars, color: Color(0xFFC5A059), size: 28),
                title: Text(e['title'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${e['detail']} • ${DateFormat('yyyy/MM/dd').format(eventDate)}\nالتذكير: ${e['advanceReminder']} الساعة $reminderTime • $remaining\nالتكرار: $repeatType | التنبيه: $repeatInterval'),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _editSpecialEventDialog(i)),
                    IconButton(
  icon: const Icon(Icons.delete_outline, color: Colors.red),
  onPressed: () {
    final eventText = (e['detail'] != null && e['detail'].toString().isNotEmpty)
        ? '${e['title']} - ${e['detail']}'
        : e['title'].toString();
    _cancelNativeAlarm(eventText);
    setState(() => _specialEvents.removeAt(i));
    _saveData();
  },
),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildRecorderTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF0F172A)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC5A059), width: 1.5),
            ),
            child: Column(
              children: [
                Icon(_isRecording ? Icons.fiber_manual_record : Icons.mic, color: _isRecording ? Colors.redAccent : const Color(0xFFC5A059), size: 40),
                const SizedBox(height: 10),
                Text(_isRecording ? 'جاري التسجيل...' : 'اضغط للتسجيل', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_formatDuration(_recordingDuration), style: const TextStyle(color: Color(0xFFC5A059), fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : const Color(0xFFC5A059),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record, color: _isRecording ? Colors.white : Colors.black),
                  label: Text(_isRecording ? 'إيقاف التسجيل' : 'بدء التسجيل', style: TextStyle(color: _isRecording ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('التسجيلات المحفوظة:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC5A059))),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _recordings.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic_none, size: 60, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        const Text('لا توجد تسجيلات', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _recordings.length,
                    itemBuilder: (ctx, i) {
                      final rec = _recordings[i];
                      final path = rec['path'].toString();
                      final isPlaying = _currentlyPlayingPath == path;
                      String dateText = '';
                      try {
                        dateText = DateFormat('yyyy/MM/dd - HH:mm').format(DateTime.parse(rec['createdAt'].toString()));
                      } catch (_) {}
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isPlaying ? const Color(0xFFC5A059) : Colors.grey.shade300, width: isPlaying ? 2 : 1),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: IconButton(
                                icon: Icon(isPlaying ? Icons.stop_circle : Icons.play_circle_fill, color: const Color(0xFFC5A059), size: 32),
                                onPressed: () => _playRecording(path),
                              ),
                              title: Text(rec['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text('المدة: ${rec['duration']}\n$dateText', style: const TextStyle(fontSize: 12)),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.share, color: Colors.green, size: 22), onPressed: () => _shareRecording(path)),
                                  IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 22), onPressed: () => _renameRecording(i)),
                                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22), onPressed: () => _deleteRecording(i)),
                                ],
                              ),
                            ),
                            if (isPlaying)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Column(children: [
                                  Slider(
                                    value: _currentPosition.inSeconds.toDouble().clamp(0, _currentDuration.inSeconds.toDouble()),
                                    min: 0,
                                    max: _currentDuration.inSeconds > 0 ? _currentDuration.inSeconds.toDouble() : 1,
                                    activeColor: const Color(0xFFC5A059),
                                    onChanged: (val) { _audioPlayer.seek(Duration(seconds: val.toInt())); },
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_formatDuration(_currentPosition), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      Text(_formatDuration(_currentDuration), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    const Icon(Icons.volume_up, size: 20, color: Color(0xFFC5A059)),
                                    Expanded(
                                      child: Slider(
                                        value: _playbackVolume,
                                        min: 0.0, max: 1.0,
                                        activeColor: const Color(0xFFC5A059),
                                        onChanged: (val) {
                                          setState(() => _playbackVolume = val);
                                          _audioPlayer.setVolume(val);
                                          _saveSettings();
                                        },
                                      ),
                                    ),
                                    Text('${(_playbackVolume * 100).toInt()}%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ]),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text('السرعة:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 8),
                                      ...[0.5, 1.0, 1.5, 2.0].map((speed) {
                                        final isSelected = _playbackSpeed == speed;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 3),
                                          child: ChoiceChip(
                                            label: Text('${speed}x', style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
                                            selected: isSelected,
                                            selectedColor: const Color(0xFF1B2A4A),
                                            onSelected: (v) {
                                              setState(() => _playbackSpeed = speed);
                                              _audioPlayer.setPlaybackRate(speed);
                                              _saveSettings();
                                            },
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                ]),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showDiaryPinDialog() async {
    final pinController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.lock, color: Colors.blue), SizedBox(width: 8), Text('قفل اليوميات')]),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'أدخل كلمة السر', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'forgot'), child: const Text('نسيت كلمة السر؟', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, pinController.text), child: const Text('دخول')),
        ],
      ),
    );

    if (result == 'cancel' || result == null) return false;

    if (result == 'forgot') {
      final answerController = TextEditingController();
      final q = _settings.diarySecurityQuestion.isEmpty ? 'لا يوجد سؤال أمان' : _settings.diarySecurityQuestion;
      final answerResult = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('استعادة كلمة السر'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(q, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(controller: answerController, decoration: const InputDecoration(labelText: 'الإجابة', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (_norm(answerController.text.trim()) == _norm(_settings.diarySecurityAnswer.trim()) && _settings.diarySecurityAnswer.isNotEmpty) {
                  Navigator.pop(ctx, 'success');
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('إجابة خاطئة!'), backgroundColor: Colors.red));
                }
              },
              child: const Text('تحقق'),
            ),
          ],
        ),
      );

      if (answerResult == 'success') {
        setState(() {
          _settings.diaryLockEnabled = false;
          _settings.diaryPin = '';
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('diary_lock_enabled', false);
        await prefs.setString('diary_pin', '');
        return true;
      }
      return false;
    }

    if (result == _settings.diaryPin) return true;

     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة السر غير صحيحة'), backgroundColor: Colors.red));
    return false;
  }

  Future<void> _openDiaryPage(DateTime date) async {
    if (_settings.diaryLockEnabled && _settings.diaryPin.isNotEmpty && !_voiceDiaryAuthTemp) {
      final bool unlocked = await _showDiaryPinDialog();
      if (!unlocked) return;
    }
    _voiceDiaryAuthTemp = false;
    _openDiaryPageInternal(date);
  }

  void _openDiaryPageInternal(DateTime date) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    final data = _diaries[key] ?? {'text': '', 'todos': [], 'images': [], 'audio': null};
    if (data['todos'] == null) data['todos'] = [];
    if (data['images'] == null) data['images'] = [];
    Navigator.push(context, MaterialPageRoute(builder: (_) => _DiaryPage(
      date: date,
      initialData: data,
      onSave: (d, dData) async {
        final k = DateFormat('yyyy-MM-dd').format(d);
        setState(() => _diaries[k] = dData);
        await _saveData();
      },
      onClearAll: () async {
        setState(() {
          _diaries.clear();
        });
        await _saveData();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم مسح كل اليوميات بنجاح'), backgroundColor: Colors.green),
          );
        }
      },
    )));
  }

  void _handleConflictResolution(bool save) {
    _pendingActionTimer?.cancel();
    _pendingVoiceAction = null;
    final taskData = _pendingConflictTaskData;
    final taskIdx = _pendingConflictTaskIndex;
    _pendingConflictTaskData = null;
    _pendingConflictTaskIndex = null;

    if (_conflictDialogContext != null) {
      Navigator.pop(_conflictDialogContext!);
      _conflictDialogContext = null;
    }

    if (save && taskData != null) {
      setState(() {
        if (taskIdx == null) { _tasks.add(taskData); } else { _tasks[taskIdx] = taskData; }
      });
      _saveData();
      if (taskData['repeatInterval'] != 'بدون تنبيه') {
        _scheduleContinuousAlarm(
          taskData['task'], DateTime.parse(taskData['scheduled']),
          taskData['repeat'], taskData['repeatInterval'],
          List<String>.from(taskData['customDays'] ?? []), soundUri: taskData['sound'],
          alarmId: taskData['alarmId'] as int?,
        );
      }
      _speak("تَمَّ حِفْظُ المَوْعِدَيْنِ $_userTitle.");
    } else {
      _speak("تَمَام $_userTitle، تَمَّ إِلْغَاءُ الحِفْظِ.");
    }
  }

  void _handleTasbeehResult(String rawText) {
    final norm = _norm(rawText);
    final matches = [
      {'key': 'subhan_adada', 'text': _norm('سبحان الله وبحمده عدد خلقه ورضا نفسه وزنة عرشه ومداد كلماته')},
      {'key': 'subhan_bihamdih_azim', 'text': _norm('سبحان الله وبحمده سبحان الله العظيم')},
      {'key': 'subhan_azim', 'text': _norm('سبحان الله العظيم')},
      {'key': 'subhan_bihamdih', 'text': _norm('سبحان الله وبحمده')},
      {'key': 'subhan', 'text': _norm('سبحان الله')},
      {'key': 'astaghfirullah', 'text': _norm('استغفر الله')},
      {'key': 'salah_ala_nabi', 'text': _norm('اللهم صل على سيدنا محمد')},
      {'key': 'alhamdulillah', 'text': _norm('الحمد لله')},
      {'key': 'allahu_akbar', 'text': _norm('الله اكبر')},
      {'key': 'la_ilaha_illallah', 'text': _norm('لا اله الا الله')},
    ];

    String remaining = norm;
    final counts = <String, int>{};

    for (var m in matches) {
      final text = m['text']!;
      final key = m['key']!;
      int idx = 0, cnt = 0;
      while ((idx = remaining.indexOf(text, idx)) != -1) {
        cnt++;
        remaining = remaining.replaceRange(idx, idx + text.length, ' ' * text.length);
        idx += text.length;
      }
      if (cnt > 0) counts[key] = (counts[key] ?? 0) + cnt;
    }

    if (counts.isEmpty) return;
    setState(() {
      for (var entry in counts.entries) {
        _tasbeehSubCounts[entry.key] = (_tasbeehSubCounts[entry.key] ?? 0) + entry.value;
        _tasbeehCount += entry.value;
      }
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('tasbeeh_count', _tasbeehCount);
      for (var entry in counts.entries) {
        prefs.setInt('tasbeeh_${entry.key}', _tasbeehSubCounts[entry.key] ?? 0);
      }
    });
  }

  void _handleAdhkarResult(String rawText) {
    String norm = _norm(rawText);
    if (norm.trim().isEmpty) return;

    final adhkarPriorityList = [
      {'text': _morningAdhkarList[0]['text'] as String, 'keywords': ['اصبحنا واصبح الملك لله', 'اصبحنا واصبح الملك']},
      {'text': _morningAdhkarList[1]['text'] as String, 'keywords': ['اللهم بك اصبحنا وبك امسينا', 'اللهم بك اصبحنا']},
      {'text': _morningAdhkarList[2]['text'] as String, 'keywords': ['انت ربي لا اله الا انت خلقتني', 'انت ربي لا اله الا انت']},
      {'text': _morningAdhkarList[3]['text'] as String, 'keywords': ['سبحان الله وبحمده']},
      {'text': _eveningAdhkarList[0]['text'] as String, 'keywords': ['امسينا وامسى الملك لله', 'امسينا وامسى الملك']},
      {'text': _eveningAdhkarList[1]['text'] as String, 'keywords': ['اللهم بك امسينا وبك اصبحنا', 'اللهم بك امسينا']},
      {'text': _eveningAdhkarList[2]['text'] as String, 'keywords': ['اعوذ بكلمات الله التامات', 'اعوذ بكلمات الله']},
      {'text': _eveningAdhkarList[3]['text'] as String, 'keywords': ['بسم الله الذي لا يضر', 'الذي لا يضر مع اسمه']},
      {'text': _sleepAdhkarList[0]['text'] as String, 'keywords': ['باسمك اللهم اموت واحيا']},
      {'text': _sleepAdhkarList[1]['text'] as String, 'keywords': ['قني عذابك يوم تبعث']},
      {'text': _sleepAdhkarList[2]['text'] as String, 'keywords': ['سبحان الله']},
      {'text': _sleepAdhkarList[3]['text'] as String, 'keywords': ['الحمد لله']},
      {'text': _sleepAdhkarList[4]['text'] as String, 'keywords': ['الله اكبر']},
    ];

    bool anyFound = false;
    final List<String> messages = [];

    while (norm.trim().isNotEmpty) {
      String? matchedText;
      String? matchedKeyword;

      for (var adhkar in adhkarPriorityList) {
        for (var keyword in adhkar['keywords'] as List<String>) {
          final normKeyword = _norm(keyword);
          if (normKeyword.isEmpty) continue;
          if (norm.contains(normKeyword)) {
            matchedText = adhkar['text'] as String;
            matchedKeyword = normKeyword;
            break;
          }
        }
        if (matchedText != null) break;
      }

      if (matchedText != null && matchedKeyword != null) {
        int count = 0;
        int index = 0;
        while ((index = norm.indexOf(matchedKeyword, index)) != -1) {
          count++;
          norm = norm.replaceRange(index, index + matchedKeyword.length, ' ' * matchedKeyword.length);
        }

        if (count > 0) {
          int currentCount = _adhkarCounts[matchedText] ?? 0;

          if (currentCount > 0) {
            int newCount = currentCount - count;
            if (newCount < 0) newCount = 0;

            _adhkarCounts[matchedText] = newCount;

            if (newCount > 0) {
              messages.add("تَمَّ تَسْجِيلُ الذِّكْرِ $count مَرَّات. البَاقِي: $newCount");
            } else {
              messages.add("أَكْمَلْتَ الذِّكْرَ $_userTitle، بَارَكَ اللهُ فِيك.");
            }
          } else {
            messages.add("لَقَدْ أَكْمَلْتَ هَذَا الذِّكْرَ $_userTitle.");
          }
          anyFound = true;
        }
      } else {
        break;
      }
    }

    if (anyFound) {
      if (mounted) setState(() {});
      _saveAdhkarCounts();
      if (messages.isNotEmpty) _speak(messages.join(' '));
    } else {
      _speak("لَمْ أَتَعَرَّفْ عَلَى الذِّكْرِ، يُرْجَى الإِعَادَة.");
    }
  }
}

// ══════════════════════════════════════════════════════
// _AdhkarCard
// ══════════════════════════════════════════════════════
class _AdhkarCard extends StatelessWidget {
  final String text;
  final int count;
  final VoidCallback onDecrement;

  const _AdhkarCard({required this.text, required this.count, required this.onDecrement});

  @override
  Widget build(BuildContext context) {
    final isDone = count == 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDone ? Colors.green.withOpacity(0.1) : Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDone ? Colors.green : Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(fontSize: 16, height: 1.6)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDone ? Colors.green : const Color(0xFF1B2A4A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: isDone ? null : onDecrement,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDone) const Icon(Icons.check, color: Colors.white, size: 18),
                    if (isDone) const SizedBox(width: 5),
                    Text(
                      isDone ? 'تم' : 'التكرار: $count',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// _TalkingImage
// ══════════════════════════════════════════════════════
class _TalkingImage extends StatefulWidget {
  final String imagePath;
  final bool isTalking;
  const _TalkingImage({required this.imagePath, required this.isTalking});
  @override
  State<_TalkingImage> createState() => _TalkingImageState();
}

class _TalkingImageState extends State<_TalkingImage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _animation = Tween(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.isTalking) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _TalkingImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTalking && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isTalking && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      alignment: Alignment.bottomCenter,
      child: widget.imagePath.startsWith('http') || widget.imagePath.startsWith('assets')
          ? Image.asset(
              widget.imagePath,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              errorBuilder: (c, e, s) => const Icon(Icons.person, size: 100, color: Colors.white54),
            )
          : Image.file(
              File(widget.imagePath),
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              errorBuilder: (c, e, s) => const Icon(Icons.person, size: 100, color: Colors.white54),
            ),
    );
  }
}

// ══════════════════════════════════════════════════════
// _DiaryPage
// ══════════════════════════════════════════════════════
class _DiaryPage extends StatefulWidget {
  final DateTime date;
  final Map<String, dynamic> initialData;
  final Future<void> Function(DateTime, Map<String, dynamic>) onSave;
  final VoidCallback onClearAll;

  const _DiaryPage({required this.date, required this.initialData, required this.onSave, required this.onClearAll});

  @override
  State<_DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<_DiaryPage> {
  static _DiaryPageState? activeInstance;
  List<Map<String, dynamic>> _entries = [];
  late TextEditingController diaryCtrl;
  final TextEditingController _quickTextCtrl = TextEditingController();
  StreamSubscription? _voiceSub;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker = ImagePicker();

  bool _isRecordingNow = false;
  String? _currentlyPlayingPath;

  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  double _playbackVolume = 1.0;
  double _playbackSpeed = 1.0;

  final FocusNode _diaryFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _diarySpeech = stt.SpeechToText();
  bool _isDictating = false;

  @override
  void initState() {
    super.initState();
    activeInstance = this;
    diaryCtrl = TextEditingController(text: widget.initialData['text'] ?? '');
    _loadData();
    _voiceSub = _diaryVoiceStream.stream.listen(_handleVoiceCommand);
  }

  void _loadData() {
    final data = widget.initialData;
    if (data['entries'] != null) {
      _entries = List<Map<String, dynamic>>.from(data['entries']);
      for (var e in _entries) {
        if (e['time'] is String) { e['time'] = DateTime.parse(e['time']); }
      }
    } else {
      if (data['todos'] != null) {
        for (var t in data['todos']) {
          _entries.add({'type': 'todo', 'content': t['text'], 'done': t['done'] ?? false, 'time': widget.date});
        }
      }
      if (data['images'] != null) {
        for (var img in data['images']) {
          _entries.add({'type': 'image', 'content': img, 'time': widget.date});
        }
      }
      if (data['audio'] != null) {
        _entries.add({'type': 'audio', 'content': data['audio'], 'time': widget.date});
      }
    }
    if (data['text'] != null && data['text'].toString().trim().isNotEmpty) {
      _entries.insert(0, {'type': 'text', 'content': data['text'], 'time': widget.date});
      diaryCtrl.clear();
    }
    _sortEntries();
  }

  void _sortEntries() {
    _entries.sort((a, b) {
      bool aDone = a['type'] == 'todo' && a['done'] == true;
      bool bDone = b['type'] == 'todo' && b['done'] == true;
      if (aDone && !bDone) return 1;
      if (!aDone && bDone) return -1;
      return (a['time'] as DateTime).compareTo(b['time'] as DateTime);
    });
  }

  String getReadableText() {
    String result = "";
    if (diaryCtrl.text.isNotEmpty) result += "النَّص: ${diaryCtrl.text}. ";
    if (_entries.isNotEmpty) {
      result += "المُحْتَوَيَاتْ: ";
      for (var e in _entries) {
        if (e['type'] == 'todo') result += "${e['content']}, ";
        if (e['type'] == 'image') result += "صورة, ";
        if (e['type'] == 'audio') result += "تسجيل صوتي, ";
      }
    }
    return result;
  }

  void _handleVoiceCommand(Map<String, dynamic> cmd) {
    if (!mounted) return;
    final action = cmd['action'];
    if (action == 'add_todo') {
      setState(() {
        _entries.add({'type': 'todo', 'content': cmd['text'] ?? 'مهمة', 'done': false, 'time': DateTime.now()});
        _sortEntries();
      });
    } else if (action == 'mark_done') {
      final idx = (cmd['index'] as int?) ?? 0;
      int todoCount = 0;
      for (int i = 0; i < _entries.length; i++) {
        if (_entries[i]['type'] == 'todo') {
          if (todoCount == idx) {
            setState(() { _entries[i]['done'] = true; _sortEntries(); });
            break;
          }
          todoCount++;
        }
      }
    } else if (action == 'add_image') {
      _showImageSource();
    } else if (action == 'record_audio') {
      _toggleRecording();
    } else if (action == 'clear_all') {
      setState(() { diaryCtrl.clear(); _entries.clear(); });
    } else if (action == 'delete_last_task') {
      setState(() {
        final lastTaskIndex = _entries.lastIndexWhere((e) => e['type'] == 'todo');
        if (lastTaskIndex != -1) _entries.removeAt(lastTaskIndex);
      });
    } else if (action == 'edit_task') {
      final idx = (cmd['index'] as int?) ?? 0;
      int todoCount = 0;
      for (int i = 0; i < _entries.length; i++) {
        if (_entries[i]['type'] == 'todo') {
          if (todoCount == idx) { _editEntryDialog(i); break; }
          todoCount++;
        }
      }
    } else if (action == 'edit_task_by_number') {
      final idx = (cmd['index'] as int?) ?? 0;
      final newText = cmd['text'] as String?;
      int todoCount = 0;
      for (int i = 0; i < _entries.length; i++) {
        if (_entries[i]['type'] == 'todo') {
          if (todoCount == idx) {
            if (newText != null && newText.isNotEmpty) {
              setState(() { _entries[i]['content'] = newText; });
            } else { _editEntryDialog(i); }
            break;
          }
          todoCount++;
        }
      }
    } else if (action == 'unmark_done') {
      final idx = (cmd['index'] as int?) ?? 0;
      int todoCount = 0;
      for (int i = 0; i < _entries.length; i++) {
        if (_entries[i]['type'] == 'todo') {
          if (todoCount == idx) {
            setState(() { _entries[i]['done'] = false; _sortEntries(); });
            break;
          }
          todoCount++;
        }
      }
    } else if (action == 'add_text_note') {
      final text = (cmd['text'] as String?) ?? '';
      if (text.isEmpty) return;
      setState(() {
        _entries.add({'type': 'text', 'content': text, 'time': DateTime.now()});
        _sortEntries();
      });
    } else if (action == 'start_recording') {
      if (!_isRecordingNow) _startRecording();
    } else if (action == 'stop_recording') {
      if (_isRecordingNow) _stopRecording();
    }
  }

  Future<void> _save() async {
    final safeEntries = _entries.map((e) {
      final map = Map<String, dynamic>.from(e);
      if (map['time'] is DateTime) { map['time'] = (map['time'] as DateTime).toIso8601String(); }
      return map;
    }).toList();
    final newData = {'text': diaryCtrl.text, 'entries': safeEntries};
    await widget.onSave(widget.date, newData);
    if (mounted) Navigator.pop(context);
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.text_fields, color: Color(0xFF1B2A4A)),
              title: const Text('كتابة نص', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _addText(); },
            ),
            ListTile(
              leading: const Icon(Icons.check_box, color: Color(0xFF1B2A4A)),
              title: const Text('إضافة مهام', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _addTasks(); },
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate, color: Color(0xFF1B2A4A)),
              title: const Text('إضافة صورة', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _showImageSource(); },
            ),
            ListTile(
              leading: const Icon(Icons.mic, color: Color(0xFF1B2A4A)),
              title: const Text('تسجيل صوتي', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _startRecording(); },
            ),
          ],
        ),
      ),
    );
  }

  void _addQuickText() {
    final text = _quickTextCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _entries.add({'type': 'text', 'content': text, 'time': DateTime.now()});
        _sortEntries();
      });
      _quickTextCtrl.clear();
      _diaryFocusNode.unfocus();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _addText() {
    TextEditingController ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة نص لليوميات', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl, maxLines: null, minLines: 3, autofocus: true,
          decoration: const InputDecoration(hintText: 'اكتب هنا...', border: OutlineInputBorder())
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() {
                  _entries.add({'type': 'text', 'content': ctrl.text.trim(), 'time': DateTime.now()});
                  _sortEntries();
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addTasks() {
    TextEditingController ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مهام'),
        content: TextField(
          controller: ctrl, maxLines: null, minLines: 3,
          decoration: const InputDecoration(hintText: 'مهمة 1\nمهمة 2...')
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final lines = ctrl.text.split('\n').where((l) => l.trim().isNotEmpty);
              if (lines.isNotEmpty) {
                setState(() {
                  for (var line in lines) {
                    _entries.add({'type': 'todo', 'content': line.trim(), 'done': false, 'time': DateTime.now()});
                  }
                  _sortEntries();
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showImageSource() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF1B2A4A)),
              title: const Text('التقاط صورة'),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? img = await _picker.pickImage(source: ImageSource.camera);
                if (img != null) _addImageToEntries(img.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF1B2A4A)),
              title: const Text('من المعرض'),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? img = await _picker.pickImage(source: ImageSource.gallery);
                if (img != null) _addImageToEntries(img.path);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addImageToEntries(String path) {
    setState(() {
      _entries.add({'type': 'image', 'content': path, 'time': DateTime.now()});
      _sortEntries();
    });
  }

  Future<void> _showRecordingNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'recording_channel_v1',
      'تسجيل الصوت',
      channelDescription: 'يظهر أثناء تسجيل الصوت',
      importance: Importance.low, priority: Priority.low,
      ongoing: true, autoCancel: false, showWhen: false,
      actions: [
        AndroidNotificationAction('stop_recording', 'إيقاف التسجيل', showsUserInterface: true, cancelNotification: true)
      ],
    );
    await _notifications.show(9999, 'جاري التسجيل...', 'اضغط لإيقاف التسجيل', NotificationDetails(android: androidDetails));
  }

  void stopRecordingByVoice() {
    if (_isRecordingNow) {
      _stopRecording();
    }
  }

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/diary_rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      setState(() => _isRecordingNow = true);
      _showRecordingNotification();
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecordingNow) {
      final p = await _recorder.stop();
      setState(() {
        _isRecordingNow = false;
        if (p != null) {
          _entries.add({'type': 'audio', 'content': p, 'time': DateTime.now()});
          _sortEntries();
        }
      });
    } else {
      if (await _recorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/diary_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: path);
        setState(() => _isRecordingNow = true);
        _showRecordingNotification();
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecordingNow) return;
    setState(() => _isRecordingNow = false);
    await _notifications.cancel(9999);
    final path = await _recorder.stop();
    setState(() {
      _isRecordingNow = false;
      if (path != null) {
        _entries.add({'type': 'audio', 'content': path, 'time': DateTime.now()});
        _sortEntries();
      }
    });
  }

  Future<void> _playAudio(String path) async {
    if (_currentlyPlayingPath == path) {
      await _audioPlayer.stop();
      await _positionSub?.cancel();
      await _durationSub?.cancel();
      setState(() {
        _currentlyPlayingPath = null;
        _currentPosition = Duration.zero;
        _currentDuration = Duration.zero;
      });
    } else {
      await _audioPlayer.stop();
      await _positionSub?.cancel();
      await _durationSub?.cancel();

      _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _currentPosition = pos);
      });
      _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
        if (mounted) setState(() => _currentDuration = dur);
      });

      await _audioPlayer.setVolume(_playbackVolume);
      await _audioPlayer.setPlaybackRate(_playbackSpeed);
      await _audioPlayer.play(DeviceFileSource(path));
      setState(() => _currentlyPlayingPath = path);

      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _currentlyPlayingPath = null;
            _currentPosition = Duration.zero;
            _currentDuration = Duration.zero;
          });
        }
      });
    }
  }

  Future<void> _shareAudio(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await Share.shareXFiles([XFile(path)], text: 'تسجيل صوتي من اليوميات');
      }
    } catch (_) {}
  }

  Future<void> _toggleDictation() async {
    if (_isDictating) {
      await _diarySpeech.stop(); setState(() => _isDictating = false); return;
    }
    bool available = await _diarySpeech.initialize(
      onStatus: (status) { if (status == 'done' || status == 'notListening') { if (mounted) setState(() => _isDictating = false); } },
    );
    if (available) {
      setState(() => _isDictating = true);
      await _diarySpeech.listen(
        localeId: "ar-EG",
        onResult: (val) { if (val.finalResult) { setState(() { _quickTextCtrl.text += ' ${val.recognizedWords}'; }); } },
      );
    }
  }

  void _editEntryDialog(int entryIndex) {
    if (entryIndex < 0 || entryIndex >= _entries.length) return;
    TextEditingController ctrl = TextEditingController(text: _entries[entryIndex]['content'].toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(_entries[entryIndex]['type'] == 'todo' ? 'تعديل المهمة' : 'تعديل الملاحظة', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: ctrl, maxLines: null, decoration: const InputDecoration(hintText: 'النص الجديد...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() { _entries[entryIndex]['content'] = ctrl.text.trim(); });
              }
              Navigator.pop(ctx);
            },
            child: const Text('حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  int deleteTaskByName(String name) {
    final nameLower = name.trim().toLowerCase();
    if (nameLower.isEmpty) return 0;
    final before = _entries.length;
    setState(() {
      _entries.removeWhere((e) =>
          e['type'] == 'todo' &&
          e['content'].toString().toLowerCase().contains(nameLower));
    });
    return before - _entries.length;
  }

  @override
  void dispose() {
    if (activeInstance == this) activeInstance = null;
    _voiceSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    diaryCtrl.dispose();
    _quickTextCtrl.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    _diaryFocusNode.dispose();
    _scrollController.dispose();
    _diarySpeech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B2A4A),
        foregroundColor: Colors.white,
        title: const Text('تدوين اليوميات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Color(0xFFC5A059)),
            onPressed: () async {
              String text = 'يوميات ${DateFormat('dd/MM/yyyy', 'ar').format(widget.date)}\n\n';
              if (diaryCtrl.text.isNotEmpty) text += '${diaryCtrl.text}\n\n';
              List<XFile> filesToShare = [];
              for (var e in _entries) {
                if (e['type'] == 'text') text += '${e['content']}\n';
                if (e['type'] == 'todo') text += '${e['done'] ? '✅' : '⏳'} ${e['content']}\n';
                if (e['type'] == 'image') {
                  final path = e['content'].toString();
                  if (File(path).existsSync()) {
                    filesToShare.add(XFile(path));
                    text += '📷 صورة مرفقة\n';
                  }
                }
                if (e['type'] == 'audio') {
                  final path = e['content'].toString();
                  if (File(path).existsSync()) {
                    filesToShare.add(XFile(path));
                    text += '🎤 تسجيل صوتي\n';
                  }
                }
              }
              try {
                if (filesToShare.isNotEmpty) {
                  await Share.shareXFiles(filesToShare, text: text);
                } else {
                  await Share.share(text);
                }
              } catch (err) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('حدث خطأ أثناء المشاركة: $err'), backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            tooltip: 'مسح اليومية الحالية',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  title: const Text('مسح اليومية', style: TextStyle(fontWeight: FontWeight.bold)),
                  content: const Text('هل أنت متأكد أنك تريد مسح كل محتويات هذه اليومية؟ لا يمكن التراجع عن هذا الإجراء.', style: TextStyle(fontSize: 16)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () async {
                        setState(() {
                          diaryCtrl.clear();
                          _entries.clear();
                        });
                        final newData = {'text': '', 'entries': []};
                        await widget.onSave(widget.date, newData);
                        if (mounted) Navigator.pop(ctx);
                      },
                      child: const Text('مسح', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.check, color: Color(0xFFC5A059)), onPressed: _save),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity, padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12),
                  border: const Border(right: BorderSide(color: Color(0xFFC5A059), width: 4))
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('اليوم: ${DateFormat('EEEE', 'ar').format(widget.date)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFC5A059))),
                  const SizedBox(height: 4),
                  Text('التاريخ: ${DateFormat('dd MMMM yyyy', 'ar').format(widget.date)} | ${_getHijriDate(widget.date)}', style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodySmall?.color, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quickTextCtrl,
                      focusNode: _diaryFocusNode,
                      decoration: InputDecoration(
                        hintText: 'اكتب أو تحدث لإضافة ملاحظة...',
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _addQuickText(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: _isDictating ? Colors.red : const Color(0xFF1B2A4A),
                    child: IconButton(
                      icon: Icon(Icons.mic, color: _isDictating ? Colors.white : const Color(0xFFC5A059), size: 20),
                      onPressed: _toggleDictation,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF1B2A4A),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFFC5A059), size: 20),
                      onPressed: _addQuickText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  children: [
                    ..._entries.asMap().entries.map((mapEntry) {
                      final int originalIndex = mapEntry.key;
                      final entry = mapEntry.value;
                      int todoNumber = 0;
                      for (int j = 0; j <= originalIndex; j++) {
                        if (_entries[j]['type'] == 'todo') todoNumber++;
                      }
                      final timeStr = DateFormat('hh:mm a', 'ar').format(entry['time']);

                      if (entry['type'] == 'text') {
                        return Card(
                          color: Theme.of(context).cardColor,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry['content'], style: const TextStyle(fontSize: 16, height: 1.5)),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                      onPressed: () {
                                        final originalIdx = _entries.indexOf(entry);
                                        _editEntryDialog(originalIdx);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                      onPressed: () => setState(() { _entries.remove(entry); }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (entry['type'] == 'todo') {
                        return Card(
                          color: entry['done'] ? Colors.green.withOpacity(0.1) : Theme.of(context).cardColor,
                          child: ListTile(
                            leading: Checkbox(
                              value: entry['done'],
                              activeColor: Colors.green,
                              onChanged: (v) {
                                setState(() {
                                  entry['done'] = v;
                                  _sortEntries();
                                });
                              },
                            ),
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFC5A059),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('#$todoNumber', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(entry['content'], style: TextStyle(decoration: entry['done'] ? TextDecoration.lineThrough : null)),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                  onPressed: () {
                                    final originalIdx = _entries.indexOf(entry);
                                    _editEntryDialog(originalIdx);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                  onPressed: () => setState(() { _entries.remove(entry); }),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (entry['type'] == 'image') {
                        return Card(
                          color: Theme.of(context).cardColor,
                          clipBehavior: Clip.antiAlias,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  insetPadding: const EdgeInsets.all(10),
                                  child: InteractiveViewer(
                                    panEnabled: true,
                                    boundaryMargin: const EdgeInsets.all(20),
                                    minScale: 0.5,
                                    maxScale: 4,
                                    child: Image.file(File(entry['content']), fit: BoxFit.contain),
                                  ),
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Image.file(File(entry['content']), width: double.infinity, fit: BoxFit.fitWidth),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('وقت الإضافة: $timeStr', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                        onPressed: () => setState(() { _entries.remove(entry); }),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (entry['type'] == 'audio') {
                        final isPlaying = _currentlyPlayingPath == entry['content'];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isPlaying ? const Color(0xFFC5A059) : Colors.grey.shade300, width: isPlaying ? 2 : 1),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                leading: IconButton(
                                  icon: Icon(isPlaying ? Icons.stop_circle : Icons.play_circle_fill, color: const Color(0xFFC5A059), size: 32),
                                  onPressed: () => _playAudio(entry['content']),
                                ),
                                title: const Text('تسجيل صوتي', style: TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('وقت التسجيل: $timeStr', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.share, color: Colors.green, size: 22), onPressed: () => _shareAudio(entry['content'])),
                                    IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 22), onPressed: () => setState(() { _entries.remove(entry); })),
                                  ],
                                ),
                              ),
                              if (isPlaying)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Column(
                                    children: [
                                      Slider(
                                        value: _currentPosition.inSeconds.toDouble().clamp(0, _currentDuration.inSeconds.toDouble()),
                                        min: 0,
                                        max: _currentDuration.inSeconds > 0 ? _currentDuration.inSeconds.toDouble() : 1,
                                        activeColor: const Color(0xFFC5A059),
                                        onChanged: (val) { _audioPlayer.seek(Duration(seconds: val.toInt())); },
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(_formatDuration(_currentPosition), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                          Text(_formatDuration(_currentDuration), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.volume_up, size: 20, color: Color(0xFFC5A059)),
                                          Expanded(
                                            child: Slider(
                                              value: _playbackVolume,
                                              min: 0.0, max: 1.0,
                                              activeColor: const Color(0xFFC5A059),
                                              onChanged: (val) {
                                                setState(() => _playbackVolume = val);
                                                _audioPlayer.setVolume(val);
                                              },
                                            ),
                                          ),
                                          Text('${(_playbackVolume * 100).toInt()}%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text('السرعة:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          const SizedBox(width: 8),
                                          ...[0.5, 1.0, 1.5, 2.0].map((speed) {
                                            final isSelected = _playbackSpeed == speed;
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 3),
                                              child: ChoiceChip(
                                                label: Text('${speed}x', style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
                                                selected: isSelected,
                                                selectedColor: const Color(0xFF1B2A4A),
                                                onSelected: (v) {
                                                  setState(() => _playbackSpeed = speed);
                                                  _audioPlayer.setPlaybackRate(speed);
                                                },
                                              ),
                                            );
                                          }).toList(),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      }

                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _isRecordingNow
          ? FloatingActionButton.extended(
              onPressed: _stopRecording,
              backgroundColor: Colors.red,
              icon: const Icon(Icons.stop, color: Colors.white),
              label: const Text('إيقاف التسجيل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : FloatingActionButton(
              onPressed: _showAddMenu,
              backgroundColor: const Color(0xFF1B2A4A),
              child: const Icon(Icons.add, color: Color(0xFFC5A059), size: 30),
            ),
    );
  }
}

// ══════════════════════════════════════════════════════
// _HijriCalendarWidget
// ══════════════════════════════════════════════════════
class _HijriCalendarWidget extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  const _HijriCalendarWidget({required this.selectedDate, required this.onDateChanged});
  @override
  State<_HijriCalendarWidget> createState() => _HijriCalendarWidgetState();
}

class _HijriCalendarWidgetState extends State<_HijriCalendarWidget> {
  late HijriCalendar _currentHijriDate;

  @override
  void initState() {
    super.initState();
    _currentHijriDate = HijriCalendar.fromDate(widget.selectedDate);
  }

  void _changeMonth(int offset) {
    try {
      setState(() {
        DateTime currentFirstGregorian = _currentHijriDate.hijriToGregorian(_currentHijriDate.hYear, _currentHijriDate.hMonth, 1);
        DateTime newGregorian = currentFirstGregorian.add(Duration(days: offset * 30));
        HijriCalendar intermediateHijri = HijriCalendar.fromDate(newGregorian);
        DateTime exactFirstGregorian = intermediateHijri.hijriToGregorian(intermediateHijri.hYear, intermediateHijri.hMonth, 1);
        _currentHijriDate = HijriCalendar.fromDate(exactFirstGregorian);
      });
    } catch (_) {}
  }

  void _showMonthYearPicker() {
    showDialog(
      context: context,
      builder: (context) {
        int tempYear = _currentHijriDate.hYear;
        int tempMonth = _currentHijriDate.hMonth;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('اختر الشهر والسنة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
              content: SizedBox(
                width: double.maxFinite, height: 400,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFFC5A059)), onPressed: () => setDialogState(() => tempYear--)),
                        Text('$tempYear هـ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.chevron_right, color: Color(0xFFC5A059)), onPressed: () => setDialogState(() => tempYear++)),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.5),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          final h = HijriCalendar();
                          h.hDay = 1;
                          h.hYear = tempYear;
                          h.hMonth = index + 1;
                          final isSelected = (index + 1) == tempMonth;
                          return InkWell(
                            onTap: () { setDialogState(() { tempMonth = index + 1; }); },
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFC5A059) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isSelected ? const Color(0xFFC5A059) : Colors.grey.shade300)
                              ),
                              alignment: Alignment.center,
                              child: Text(h.getLongMonthName(), style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : Colors.black87)),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
                  onPressed: () {
                    try {
                      DateTime firstOfTarget = HijriCalendar().hijriToGregorian(tempYear, tempMonth, 1);
                      setState(() {
                        _currentHijriDate = HijriCalendar.fromDate(firstOfTarget);
                      });
                      Navigator.pop(context);
                    } catch (_) {}
                  },
                  child: const Text('موافق', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    int daysInMonth = _currentHijriDate.lengthOfMonth;
    DateTime firstDayOfMonth = _currentHijriDate.hijriToGregorian(_currentHijriDate.hYear, _currentHijriDate.hMonth, 1);
    int firstDayWeekday = firstDayOfMonth.weekday;
    int startOffset = (firstDayWeekday + 1) % 7;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF1B2A4A)), onPressed: () => _changeMonth(-1)),
              InkWell(
                onTap: _showMonthYearPicker,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Text('${_currentHijriDate.getLongMonthName()} ${_currentHijriDate.hYear} هـ', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF1B2A4A)),
                  ]),
                ),
              ),
              IconButton(icon: const Icon(Icons.chevron_right, color: Color(0xFF1B2A4A)), onPressed: () => _changeMonth(1)),
            ],
          ),
        ),
        Row(
          children: ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج']
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 15)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final double cellWidth = constraints.maxWidth / 7;
            const double cellHeight = 45.0;
            return Wrap(
              children: List.generate(startOffset + daysInMonth, (index) {
                if (index < startOffset) {
                  return SizedBox(width: cellWidth, height: cellHeight);
                }
                int day = index - startOffset + 1;
                HijriCalendar hDay = HijriCalendar();
                hDay.hDay = 1;
                hDay.hYear = _currentHijriDate.hYear;
                hDay.hMonth = _currentHijriDate.hMonth;
                hDay.hDay = day;
                DateTime gDate = hDay.hijriToGregorian(hDay.hYear, hDay.hMonth, hDay.hDay);
                bool isSelected = gDate.year == widget.selectedDate.year &&
                                  gDate.month == widget.selectedDate.month &&
                                  gDate.day == widget.selectedDate.day;
                bool isToday = gDate.year == DateTime.now().year &&
               gDate.month == DateTime.now().month &&
               gDate.day == DateTime.now().day;
                return SizedBox(
                  width: cellWidth,
                  height: cellHeight,
                  child: Center(
                    child: InkWell(
                      onTap: () => widget.onDateChanged(gDate),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
  shape: BoxShape.circle,
  color: isSelected ? const Color(0xFF1B2A4A) : null,
  border: isToday && !isSelected ? Border.all(color: const Color(0xFF1B2A4A), width: 1.5) : null, // 👈 التعديل هنا
),
                        alignment: Alignment.center,
                        child: Text('$day', style: TextStyle(
                          fontSize: 17,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black,
                        )),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════
// 🎉 LoginScreen
// ══════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  final bool startInRegisterMode; // 👈 ضيف السطر ده
  const LoginScreen({super.key, this.startInRegisterMode = false}); // 👈 وعدل الكونستراكتور

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  DateTime? _dob;
  
  late bool _isLogin;
  bool _isLoading = false;
  
  @override
void initState() {
  super.initState();
  _isLogin = !widget.startInRegisterMode;
}

  Future<void> _submit() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    if (!_isLogin && (_nameCtrl.text.isEmpty || _dob == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال الاسم وتاريخ الميلاد'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      } else {
        UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(), 
          password: _passCtrl.text.trim()
        );
        
        if (cred.user != null) {
          await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
            'name': _nameCtrl.text.trim(),
            'dob': _dob!.toIso8601String(),
            'email': _emailCtrl.text.trim(),
            'isPro': false,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          
          await cred.user!.updateDisplayName(_nameCtrl.text.trim());
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: ${e.toString().split(']').last.trim()}'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  Future<void> _signInWithGoogle() async {
  setState(() => _isLoading = true);
  try {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    UserCredential userCred = await FirebaseAuth.instance.signInWithCredential(credential);

    if (userCred.additionalUserInfo?.isNewUser ?? false) {
      await FirebaseFirestore.instance.collection('users').doc(userCred.user!.uid).set({
        'name': googleUser.displayName ?? 'مستخدم',
        'dob': '',
        'email': googleUser.email,
        'isPro': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (mounted) Navigator.pop(context, true);
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في تسجيل الدخول بجوجل: $e'), backgroundColor: Colors.red));
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFF1B2A4A),
    appBar: AppBar(
      title: Text(_isLogin ? 'تسجيل الدخول' : 'إنشاء حساب جديد', 
        style: const TextStyle(color: Color(0xFFC5A059), fontWeight: FontWeight.bold)
      ), 
      backgroundColor: Colors.transparent, elevation: 0,
      iconTheme: const IconThemeData(color: Color(0xFFC5A059)),
    ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.account_circle, size: 100, color: Color(0xFFC5A059)),
            const SizedBox(height: 30),
            
            if (!_isLogin) ...[
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'الاسم بالكامل',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true, fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 15),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime(2000),
                    firstDate: DateTime(1940),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _dob = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'تاريخ الميلاد',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true, fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  child: Text(
                    _dob == null ? 'اختر التاريخ' : DateFormat('yyyy/MM/dd').format(_dob!),
                    style: TextStyle(color: _dob == null ? Colors.white38 : Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 15),
            ],

            TextField(
              controller: _emailCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'البريد الإلكتروني',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true, fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true, fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC5A059), minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: _isLoading ? null : _submit,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : Text(_isLogin ? 'دخول' : 'إنشاء الحساب', style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 15),
ElevatedButton.icon(
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    minimumSize: const Size.fromHeight(50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  icon: Image.network('https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg', height: 24),
  label: const Text('تسجيل الدخول باستخدام جوجل', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
  onPressed: _isLoading ? null : _signInWithGoogle,
),
const SizedBox(height: 5),
            TextButton(
              onPressed: () => setState(() {
                _isLogin = !_isLogin;
                _nameCtrl.clear();
                _dob = null;
              }), 
              child: Text(_isLogin ? 'ليس لديك حساب؟ سجل الآن' : 'لديك حساب؟ سجل دخول', style: const TextStyle(color: Color(0xFFC5A059)))
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// 🎉 PremiumScreen
// ══════════════════════════════════════════════════════
class PremiumScreen extends StatefulWidget {
  final VoidCallback onActivated;
  const PremiumScreen({super.key, required this.onActivated});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  void _activateCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen()));
        setState(() => _isLoading = false);
        return;
      }

      final firestore = FirebaseFirestore.instance;
      final codeRef = firestore.collection('activation_codes').doc(code);
      final userRef = firestore.collection('users').doc(user.uid);

      await firestore.runTransaction((transaction) async {
        DocumentSnapshot codeSnap = await transaction.get(codeRef);
        if (!codeSnap.exists) throw 'INVALID';
        bool isUsed = codeSnap.get('isUsed') ?? false;
        if (isUsed) throw 'ALREADY_USED';

        transaction.update(codeRef, {'isUsed': true, 'usedBy': user.email});
        transaction.set(userRef, {'isPro': true, 'email': user.email}, SetOptions(merge: true));
      });

      const storage = FlutterSecureStorage();
      await storage.write(key: 'is_pro_user', value: 'true');

      widget.onActivated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 مبروك! تم تفعيل النسخة البرو بنجاح.'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (!mounted) return;
      String msg = '❌ حدث خطأ، تأكد من الإنترنت.';
      if (e == 'INVALID') msg = '❌ كود التفعيل غير صحيح.';
      if (e == 'ALREADY_USED') msg = '❌ هذا الكود مستخدم من قبل.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 👇 دالة جديدة للـ Bullet Points
  Widget _buildBulletPoint(String title, String examples) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(examples, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFC5A059).withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, color: const Color(0xFFC5A059), size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
  title: const Text('النسخة البرو 👑', style: TextStyle(color: Color(0xFFC5A059), fontWeight: FontWeight.bold)), // 👈 اللون الذهبي
  backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
  iconTheme: const IconThemeData(color: Color(0xFFC5A059)), // 👈 لون سهم الرجوع
),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFFC5A059), Color(0xFFE8C07B)]),
                  boxShadow: [BoxShadow(color: const Color(0xFFC5A059).withOpacity(0.4), blurRadius: 20, spreadRadius: 5)],
                ),
                child: const Icon(Icons.workspace_premium, size: 70, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            const Text('ارتقِ بتجربتك مع السكرتير الشخصي', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 10),
            const Text('ادفع مرة واحدة فقط، واستمتع بكل المميزات مدى الحياة!', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Color(0xFFC5A059), fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            // 👇 كارت المميزات الجديد
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2A4A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFC5A059).withOpacity(0.3), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Icon(Icons.record_voice_over, color: Color(0xFFC5A059), size: 30),
    SizedBox(width: 10),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('أكثر من 80 أمر صوتي ذكي', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 5),
          Text('(تحكم كامل في التطبيق باستخدام الصوت)', style: TextStyle(color: Color(0xFFC5A059), fontSize: 14, fontWeight: FontWeight.bold)),
          SizedBox(height: 2),
          Text('يدعم أكثر من 1200 مفردة مختلفة ولهجة مصرية', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    ),
  ],
),
                  const SizedBox(height: 10),
                  const Text(
                    'مش محتاج تلمس الشاشة. نادي "يا سكرتير" وتحدث معه كأنه إنسان حقيقي — ينفذ أوامرك ويرد عليك:',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 15),
                  _buildBulletPoint('🗓️ إدارة المواعيد والمنبهات:', ' "فكرني بكرة 8 الصبح"، "عدل الموعد لـ 9"، "امسح منبهات النهاردة".'),
                  _buildBulletPoint('🗣️ التحكم في المنبه بالصوت:', ' "وقف المنبه"، "صحيت"، "أجله 10 دقايق"، "فكرني بعد نص ساعة".'),
                  _buildBulletPoint('🕌 مواقيت الصلاة والأذان:', ' "امتى أذان الفجر؟"، "فاضل كام على العصر؟"، "فكرني قبل المغرب بنص ساعة".'),
                  _buildBulletPoint('📝 اليوميات والمهام:', ' "اكتب في يومياتي إني خلصت الشغل"، "ضيف مهمة جديدة"، "اقرا يومية امبارح".'),
                  _buildBulletPoint('📅 الجدول الأسبوعي:', ' "ضيف موعد يوم السبت 5 العصر"، "عندي ايه بكرة؟"، "الغي جدول النهاردة".'),
                  _buildBulletPoint('⚙️ تغيير الإعدادات بصوتك:', ' "غير اسمك لـ أحمد"، "خلي صوتك أسرع"، "فعل الوضع الليلي"، "غير نغمة المنبه".'),
                  _buildBulletPoint('📿 التسبيح والأذكار:', ' "سبحان الله 33 مرة"، "العداد كام؟"، "صفري التسبيح"، "وضع الأذكار".'),
                  _buildBulletPoint('🗣️ محادثة وردود ذكية:', ' "إزيك؟"، "قولي نكتة"، "قولي لغز"، "انت مين؟"، "ادعيلي"، "بحبك"، "أنا تعبان"، "قوليلي الساعة كام".'),
                  const Divider(color: Colors.white24, height: 30),
                  _buildFeatureRow(Icons.vibration, 'تشغيل الهز', 'نادي السكرتير بهز الهاتف'),
_buildFeatureRow(Icons.mic_external_on, 'النداء الدائم', 'نادي السكرتير بصوتك في أي وقت'),
                  _buildFeatureRow(Icons.vibration, 'إيقاف التسجيل بالهز', 'تحكم سريع أثناء تسجيل الصوتيات'),
                  _buildFeatureRow(Icons.alarm, 'إيقاف وتأجيل المنبه بالصوت', 'تحكم كامل في المنبه حتى لو إيدك مشغولة'),
                  _buildFeatureRow(Icons.music_note, 'نغمات حصرية للمنبهات', 'أصوات مرعب، آيفون، وصحيان قوي تناسب جميع الاحتياجات'),
                  _buildFeatureRow(Icons.face, 'تخصيص السكرتير', 'غير الاسم والصورة حسب ذوقك'),
                  _buildFeatureRow(Icons.lock, 'قفل اليوميات السري', 'أمان تام لخصوصيتك بكلمة سر'),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(color: const Color(0xFFC5A059), borderRadius: BorderRadius.circular(50)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('50', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black)),
                  SizedBox(width: 5),
                  Text('ج.م / مدى الحياة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                ],
              ),
            ),
            const SizedBox(height: 30),
            // 👇 زرار الواتساب بـ FaIcon
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                minimumSize: const Size.fromHeight(55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 30),
              label: const Text('للطلب وشراء كود التفعيل (اضغط هنا)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: () async {
                // 👇 غيّر الرقم لرقمك لو مختلف
                final Uri url = Uri.parse('https://wa.me/201032491766?text=أهلاً، أريد شراء كود تفعيل النسخة البرو لتطبيق سكرتيري');
                try {
                  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                    throw 'Could not launch';
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تأكد من وجود تطبيق واتساب'), backgroundColor: Colors.red));
                  }
                }
              },
            ),
            const SizedBox(height: 30),
            const Row(children: [Expanded(child: Divider(color: Colors.white24)), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('لديك كود بالفعل؟', style: TextStyle(color: Colors.white54))), Expanded(child: Divider(color: Colors.white24))]),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'أدخل الكود هنا (PRO-XXXX)',
                hintStyle: const TextStyle(color: Colors.white38, letterSpacing: 1),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFFC5A059).withOpacity(0.5))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5A059), width: 2)),
              ),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC5A059),
                minimumSize: const Size.fromHeight(55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isLoading ? null : _activateCode,
              child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.black) 
                  : const Text('تفعيل النسخة البرو الآن', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen())),
              icon: const Icon(Icons.login, color: Colors.white54),
              label: const Text('تسجيل الدخول / تغيير الحساب', style: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// 🎉 نهاية الملف بالكامل
// ══════════════════════════════════════════════════════
