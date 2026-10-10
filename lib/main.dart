import 'dart:async';
import 'dart:convert';
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

// ─── متغيرات عامة ───
final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
const String _secretaryImagePath = 'assets/IMG-20261009-WA7583.jpg';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  tz.initializeTimeZones();
  await _initNotifications();

  final prefs = await SharedPreferences.getInstance();
  bool isFirstTime = prefs.getBool('is_first_time') ?? true;
  String? secretaryName = prefs.getString('secretary_name');
  bool? isUserMale = prefs.getBool('is_user_male');

  runApp(SecretaryApp(
    isFirstTime: isFirstTime,
    savedName: secretaryName,
    savedIsUserMale: isUserMale,
  ));
}

Future<void> _initNotifications() async {
  const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: androidInit);
  await _notifications.initialize(initSettings);
}

// ─── أدوات تطبيع النص العربي ───
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

// ─── إعدادات التطبيق ───
class AppSettings {
  int defaultReminderHour;
  int defaultReminderMinute;
  String voiceLevel; // 'عالي', 'متوسط', 'منخفض'
  bool greetingEnabled;

  AppSettings({
    this.defaultReminderHour = 18,
    this.defaultReminderMinute = 0,
    this.voiceLevel = 'عالي',
    this.greetingEnabled = true,
  });

  double get speechRate {
    switch (voiceLevel) {
      case 'منخفض':
        return 0.35;
      case 'متوسط':
        return 0.42;
      default:
        return 0.48;
    }
  }

  double get speechVolume {
    switch (voiceLevel) {
      case 'منخفض':
        return 0.4;
      case 'متوسط':
        return 0.7;
      default:
        return 1.0;
    }
  }
}

// ─── التطبيق ───
class SecretaryApp extends StatelessWidget {
  final bool isFirstTime;
  final String? savedName;
  final bool? savedIsUserMale;

  const SecretaryApp({super.key, required this.isFirstTime, this.savedName, this.savedIsUserMale});

  @override
  Widget build(BuildContext context) {
    Widget homeScreen;
    if (isFirstTime) {
      homeScreen = const TermsAndPermissionsScreen();
    } else {
      homeScreen = MainDashboard(
        secretaryName: savedName ?? 'سارة',
        isUserMale: savedIsUserMale ?? true,
      );
    }
    return MaterialApp(
      title: 'السكرتير الذكي',
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
      ),
      home: homeScreen,
    );
  }
}

// 1. شاشة الاتفاقية والأذونات
class TermsAndPermissionsScreen extends StatefulWidget {
  const TermsAndPermissionsScreen({super.key});
  @override
  State<TermsAndPermissionsScreen> createState() => _TermsAndPermissionsScreenState();
}

class _TermsAndPermissionsScreenState extends State<TermsAndPermissionsScreen> {
  bool _agreed = false;

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.notification.request();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SetupSecretaryScreen()));
    }
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
            const Text('مرحباً بك في نظام السكرتير الشخصي الذكي', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
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
                      Text('يتطلب تشغيل السكرتير الذكي الأذونات التالية:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      Text('• المايكروفون: للاستجابة عند الهز أو المناداة باسم السكرتير.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 5),
                      Text('• التنبيهات والإشعارات: لإطلاق المنبه الصوتي والتذكير المسبق بالمناسبات.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 5),
                      Text('• مستشعرات الحركة: للتعرف على هز الجهاز وتفعيل المساعد مباشرة.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 15),
                      Text('جميع البيانات محفوظة بأمان محلياً على جهازك.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
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
              onPressed: _agreed ? _requestPermissions : null,
              child: const Text('متابعة وإعطاء الأذونات', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}

// 2. شاشة إعداد السكرتيرة
class SetupSecretaryScreen extends StatefulWidget {
  const SetupSecretaryScreen({super.key});
  @override
  State<SetupSecretaryScreen> createState() => _SetupSecretaryScreenState();
}

class _SetupSecretaryScreenState extends State<SetupSecretaryScreen> {
  String _userGender = 'male';
  final TextEditingController _nameController = TextEditingController(text: 'سارة');

  final List<String> _femaleNames = ['سارة', 'مريم', 'ندى', 'نور', 'ياسمين'];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim().isEmpty ? 'سارة' : _nameController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_time', false);
    await prefs.setString('secretary_name', name);
    await prefs.setBool('is_user_male', _userGender == 'male');

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainDashboard(secretaryName: name, isUserMale: _userGender == 'male'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحديد هويّة السكرتيرة'),
        backgroundColor: const Color(0xFF1B2A4A),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFC5A059), width: 4),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
                  image: const DecorationImage(
                    image: AssetImage(_secretaryImagePath),
                    fit: BoxFit.cover,
                    alignment: Alignment(0, -0.4),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              const Text('صوت السكرتيرة (سيدة)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
              const SizedBox(height: 20),
              const Divider(),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('نوع المستخدم (صاحب الهاتف):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('ذكر (يا فندم)'),
                      value: 'male',
                      groupValue: _userGender,
                      onChanged: (v) => setState(() => _userGender = v ?? 'male'),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('أنثى (يا أستاذة)'),
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
                child: Text('اختر اسماً أو اكتب اسماً مخصصاً:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8.0,
                children: _femaleNames.map((name) {
                  return ActionChip(
                    label: Text(name),
                    backgroundColor: _nameController.text == name ? const Color(0xFFC5A059) : Colors.grey.shade200,
                    labelStyle: TextStyle(
                      color: _nameController.text == name ? Colors.black : Colors.black87,
                      fontWeight: _nameController.text == name ? FontWeight.bold : FontWeight.normal,
                    ),
                    onPressed: () {
                      setState(() {
                        _nameController.text = name;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'اسم السكرتيرة',
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

// 3. اللوحة الرئيسية
class MainDashboard extends StatefulWidget {
  final String secretaryName;
  final bool isUserMale;

  const MainDashboard({super.key, required this.secretaryName, this.isUserMale = true});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _starting = false;
  bool _isListening = false;
  int _currentIndex = 0;
  DateTime _selectedDate = DateTime.now();
  DateTime _diaryDate = DateTime.now();
  DateTime? _lastShake;

  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _specialEvents = [];
  Map<String, String> _diaries = {};
  AppSettings _settings = AppSettings();

  final List<Timer> _activeTimers = [];
  StreamSubscription? _accelerometerSub;

  String get _userTitle => widget.isUserMale ? "يا فندم" : "يا أستاذة";

  @override
  void initState() {
    super.initState();
    _loadData();
    _configureVoice();
    _initSpeech();
    _initShakeDetector();
  }

  Future<void> _initSpeech() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted && _isListening) {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (mounted) setState(() => _isListening = false);
        },
      );
    } catch (_) {
      _speechReady = false;
    }
  }

  void _initShakeDetector() {
    _accelerometerSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      double gX = event.x / 9.81;
      double gY = event.y / 9.81;
      double gZ = event.z / 9.81;
      double gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

      if (gForce > 2.2) {
        final now = DateTime.now();
        if (_lastShake != null && now.difference(_lastShake!) < const Duration(seconds: 3)) return;
        _lastShake = now;
        if (!_isListening && !_starting) _listenVoiceCommand();
      }
    });
  }

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
            _scheduleContinuousAlarm(t['task'].toString(), dt, t['repeat'] ?? 'مرة واحدة', t['repeatInterval'] ?? 'كل 5 دقايق');
          }
        }
      }
    }

    String? eventsString = prefs.getString('saved_events');
    if (eventsString != null) {
      setState(() {
        _specialEvents = List<Map<String, dynamic>>.from(json.decode(eventsString));
      });
    } else {
      setState(() {
        _specialEvents = [];
      });
    }

    String? diariesString = prefs.getString('saved_diaries');
    if (diariesString != null) {
      setState(() {
        _diaries = Map<String, String>.from(json.decode(diariesString));
      });
    }

    // تحميل الإعدادات
    _settings.defaultReminderHour = prefs.getInt('default_reminder_hour') ?? 18;
    _settings.defaultReminderMinute = prefs.getInt('default_reminder_minute') ?? 0;
    _settings.voiceLevel = prefs.getString('voice_level') ?? 'عالي';
    _settings.greetingEnabled = prefs.getBool('greeting_enabled') ?? true;
    setState(() {});
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_tasks', json.encode(_tasks));
    await prefs.setString('saved_events', json.encode(_specialEvents));
    await prefs.setString('saved_diaries', json.encode(_diaries));
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_reminder_hour', _settings.defaultReminderHour);
    await prefs.setInt('default_reminder_minute', _settings.defaultReminderMinute);
    await prefs.setString('voice_level', _settings.voiceLevel);
    await prefs.setBool('greeting_enabled', _settings.greetingEnabled);
  }

  @override
  void dispose() {
    _accelerometerSub?.cancel();
    for (var timer in _activeTimers) {
      timer.cancel();
    }
    _tts.stop();
    _speech.cancel();
    super.dispose();
  }

  // 🔊 إعداد الصوت والترحيب
  Future<void> _configureVoiceAndGreet() async {
    await _tts.setLanguage("ar-SA");
    await _tts.setPitch(1.20);
    await _tts.setSpeechRate(_settings.speechRate);
    await _tts.setVolume(_settings.speechVolume);

    if (_settings.greetingEnabled) {
      String greetingText = "أهلاً بك $_userTitle. أنا سكرتيرتك ${widget.secretaryName}، هُز الهاتف في أي وقت لأكون في خدمتك.";
      await _tts.speak(greetingText);
    }
  }

  Future<void> _configureVoice() async {
    await _tts.setLanguage("ar-SA");
    await _tts.setPitch(1.20);
    await _tts.setSpeechRate(_settings.speechRate);
    await _tts.setVolume(_settings.speechVolume);
    _configureVoiceAndGreet();
  }

  Future<void> _speak(String text) async {
    await _tts.setSpeechRate(_settings.speechRate);
    await _tts.setVolume(_settings.speechVolume);
    await _tts.speak(text);
  }

  Future<void> _listenVoiceCommand() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (_starting) return;
    _starting = true;

    try {
      if (!_speechReady) await _initSpeech();
      if (!_speechReady) {
        await _speak("لا أستطيع الوصول للميكروفون $_userTitle. تأكد من إذن المايكروفون.");
        return;
      }

      await _tts.stop();
      if (mounted) setState(() => _isListening = true);

      await _speech.listen(
        localeId: "ar_AE",
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 4),
        onResult: (val) {
          if (val.finalResult) {
            if (mounted) setState(() => _isListening = false);
            _processSmartVoiceCommand(val.recognizedWords);
          }
        },
      );
    } finally {
      _starting = false;
    }
  }

  // 🧠 معالجة الأوامر
  Future<void> _processSmartVoiceCommand(String rawCommand) async {
    final userTitle = _userTitle;
    final cmd = _norm(rawCommand);
    final nameNorm = _norm(widget.secretaryName);

    bool isCalledByName = cmd.contains(nameNorm) || cmd.contains('يا سكرتير');

    final alarmKeywords = ["منبه", "فكرني", "ذكرني", "تذكير", "سجل عندك", "ورايا", "صحيني"];
    if (_hasAny(cmd, alarmKeywords)) {
      await _createAlarmFromVoice(rawCommand, cmd);
      return;
    }

    final prayerKeywords = ["صلوات", "صلاة", "مواقيت", "اذان", "أذان"];
    final diaryKeywords = ["يوميات", "مفكرة", "تدوين", "خواطر"];
    final eventKeywords = ["مناسبات", "مناسبة", "عيد", "ذكرى"];

    if (_hasAny(cmd, prayerKeywords)) {
      setState(() => _currentIndex = 2);
      await _speak("تم الانتقال لمواقيت الصلاة $userTitle.");
      return;
    } else if (_hasAny(cmd, diaryKeywords)) {
      setState(() => _currentIndex = 1);
      await _speak("تم فتح قسم اليوميات $userTitle.");
      return;
    } else if (_hasAny(cmd, eventKeywords)) {
      setState(() => _currentIndex = 3);
      await _speak("تم الانتقال للمناسبات السنوية $userTitle.");
      return;
    }

    if (isCalledByName) {
      await _speak("نعم $userTitle! أنا أسمعك، كيف يمكنني مساعدتك؟");
    } else {
      await _speak("عذراً $userTitle، لم أفهم الأمر. من فضلك أعد المحاولة.");
    }
  }

  Future<void> _createAlarmFromVoice(String rawCommand, String cmd) async {
    final userTitle = _userTitle;
    final now = DateTime.now();
    var targetDate = now;
    var explicitDay = false;
    var afterTomorrow = false;

    if (cmd.contains('بعد بكره') || cmd.contains('بعد غد')) {
      targetDate = now.add(const Duration(days: 2));
      explicitDay = true;
      afterTomorrow = true;
    } else if (cmd.contains('بكره') || cmd.contains('غدا')) {
      targetDate = now.add(const Duration(days: 1));
      explicitDay = true;
    }

    final parsedHour = _parseHour(cmd);
    if (parsedHour == null) {
      await _speak("في أي ساعة $userTitle؟ قل مثلاً: فكرني الساعة خمسة.");
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
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final strip = <String>{
      'اظبطلي', 'اضبطلي', 'اظبط', 'اضبط', 'ظبط', 'منبه', 'علي', 'الساعه', 'ساعه',
      'فكرني', 'ذكرني', 'تذكير', 'سجل', 'عندك', 'اني', 'ان', 'ورايا', 'عايز', 'عاوز',
      'صحيني', 'بكره', 'غدا', 'الصبح', 'صباحا', 'صبحا', 'مساء', 'بالليل', 'الليل',
      'ونص', 'وربع', 'وثلث', 'يا', 'لو', 'سمحت',
    };
    final nameNorm = _norm(widget.secretaryName);
    final kept = <String>[];
    for (final t in rawCommand.split(RegExp(r'\s+'))) {
      final n = _norm(t);
      if (n.isEmpty) continue;
      if (strip.contains(n) || n == nameNorm) continue;
      if (afterTomorrow && n == 'بعد') continue;
      if (RegExp(r'^\d{1,2}(:\d{2})?$').hasMatch(n)) continue;
      if (_hourWords.containsKey(n)) continue;
      kept.add(t);
    }
    var cleanTitle = kept.join(' ').trim();
    if (cleanTitle.isEmpty) cleanTitle = isWake ? 'الاستيقاظ' : 'مهمة تذكيرية';

    final formattedDate = DateFormat('yyyy-MM-dd').format(scheduled);
    final formattedTime = DateFormat('hh:mm a', 'ar').format(scheduled);

    setState(() {
      _selectedDate = scheduled;
      _currentIndex = 0;
      _tasks.add({
        'date': formattedDate,
        'task': cleanTitle,
        'time': formattedTime,
        'alarm': true,
        'scheduled': scheduled.toIso8601String(),
        'repeat': 'مرة واحدة',
        'repeatInterval': 'كل 5 دقايق',
      });
    });

    _saveData();
    _scheduleContinuousAlarm(cleanTitle, scheduled, 'مرة واحدة', 'كل 5 دقايق');

    final h12 = scheduled.hour % 12 == 0 ? 12 : scheduled.hour % 12;
    final minuteText = scheduled.minute > 0 ? ' و ${scheduled.minute} دقيقة' : '';
    final periodText = scheduled.hour >= 12 ? 'مساءً' : 'صباحاً';

    await _speak("تم التنفيذ $userTitle! تم تسجيل: $cleanTitle، في تمام الساعة $h12$minuteText $periodText.");
  }

  int _getIntervalSeconds(String interval) {
    switch (interval) {
      case 'كل دقيقة':
        return 60;
      case 'كل دقيقتين':
        return 120;
      case 'كل 3 دقايق':
        return 180;
      case 'كل 5 دقايق':
        return 300;
      case 'كل 10 دقايق':
        return 600;
      case 'مرة واحدة':
        return 0;
      default:
        return 300;
    }
  }

  void _scheduleContinuousAlarm(String taskTitle, DateTime scheduledDateTime, String repeat, String interval) {
    Duration difference = scheduledDateTime.difference(DateTime.now());
    if (difference.isNegative) return;

    _scheduleBackgroundNotification(taskTitle, scheduledDateTime);

    Timer timer = Timer(difference, () {
      if (mounted) _startAlarmLoop(taskTitle, repeat, interval);
    });
    _activeTimers.add(timer);
  }

  Future<void> _scheduleBackgroundNotification(String taskTitle, DateTime scheduledDateTime) async {
    final tzTime = tz.TZDateTime.from(scheduledDateTime, tz.local);
    const androidDetails = AndroidNotificationDetails(
      'secretary_alarm',
      'منبه السكرتير',
      channelDescription: 'تنبيهات المواعيد',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    await _notifications.zonedSchedule(
      taskTitle.hashCode,
      'تنبيه هام!',
      'حان الآن موعد: $taskTitle',
      tzTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  void _startAlarmLoop(String taskTitle, String repeat, String interval) {
    final userTitle = _userTitle;
    WakelockPlus.enable();
    HapticFeedback.vibrate();

    void speakAlert() {
      _speak("حان الآن موعد: $taskTitle");
      HapticFeedback.vibrate();
    }

    speakAlert();

    int secs = _getIntervalSeconds(interval);
    Timer? loopTimer;
    if (secs > 0 && repeat != 'مرة واحدة') {
      loopTimer = Timer.periodic(Duration(seconds: secs), (_) {
        speakAlert();
      });
      _activeTimers.add(loopTimer);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2A4A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.alarm_on, color: Color(0xFFC5A059), size: 30),
            SizedBox(width: 10),
            Text('تنبيه هام ومباشر!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '$userTitle، حان الآن موعد:\n"$taskTitle"',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC5A059)),
            onPressed: () {
              loopTimer?.cancel();
              _tts.stop();
              WakelockPlus.disable();
              Navigator.pop(ctx);
            },
            child: const Text('خلاص (إيقاف التنبيه)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _deleteTask(int index) {
    setState(() {
      _tasks.removeAt(index);
    });
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف الموعد وإلغاء منبهه')),
    );
  }

  // ⚙️ شاشة الإعدادات
  void _openSettingsScreen() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
            children: [
              Icon(Icons.settings, color: Color(0xFF1B2A4A), size: 28),
              SizedBox(width: 10),
              Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // وقت التذكير الافتراضي
                const Text('وقت التذكير الافتراضي للمناسبات:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_settings.defaultReminderHour.toString().padLeft(2, '0')}:${_settings.defaultReminderMinute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A)),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.access_time, color: Color(0xFFC5A059)),
                      label: const Text('تغيير'),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: _settings.defaultReminderHour, minute: _settings.defaultReminderMinute),
                        );
                        if (t != null) {
                          setStateSB(() {
                            _settings.defaultReminderHour = t.hour;
                            _settings.defaultReminderMinute = t.minute;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const Divider(),
                // مستوى الصوت
                const Text('مستوى الصوت:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _settings.voiceLevel,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: ['عالي', 'متوسط', 'منخفض']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (val) {
                    setStateSB(() {
                      _settings.voiceLevel = val ?? 'عالي';
                    });
                  },
                ),
                const Divider(),
                // الترحيب
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('الجملة الترحيبية عند البدء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  value: _settings.greetingEnabled,
                  activeColor: const Color(0xFF1B2A4A),
                  onChanged: (v) {
                    setStateSB(() {
                      _settings.greetingEnabled = v;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () async {
                await _saveSettings();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حفظ الإعدادات')),
                );
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // 🎁 إضافة مناسبة
  void _addSpecialEventDialog() {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController detailCtrl = TextEditingController();
    String selectedAdvanceReminder = 'قبلها بيوم';
    DateTime selectedEventDate = DateTime.now();
    TimeOfDay reminderTime = TimeOfDay(
      hour: _settings.defaultReminderHour,
      minute: _settings.defaultReminderMinute,
    );

    final List<String> reminderOptions = [
      'في نفس اليوم',
      'قبلها بيوم',
      'قبلها بـ 3 أيام',
      'قبلها بأسبوع',
      'قبلها بـ 10 أيام',
      'قبلها بشهر'
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('إضافة مناسبة خاصة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'اسم المناسبة (عيد ميلاد/زواج)')),
                const SizedBox(height: 10),
                TextField(controller: detailCtrl, decoration: const InputDecoration(labelText: 'التفاصيل أو اسم الشخص')),
                const SizedBox(height: 15),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('تاريخ المناسبة: ${DateFormat('yyyy/MM/dd').format(selectedEventDate)}'),
                  trailing: const Icon(Icons.calendar_today, color: Color(0xFF1B2A4A)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedEventDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setStateSB(() => selectedEventDate = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('وقت التذكير: ${reminderTime.format(context)}'),
                  trailing: const Icon(Icons.access_time, color: Color(0xFF1B2A4A)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: reminderTime,
                    );
                    if (picked != null) setStateSB(() => reminderTime = picked);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedAdvanceReminder,
                  decoration: const InputDecoration(labelText: 'موعد التذكير المسبق', border: OutlineInputBorder()),
                  items: reminderOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                  onChanged: (val) => setStateSB(() => selectedAdvanceReminder = val ?? selectedAdvanceReminder),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  setState(() {
                    _specialEvents.add({
                      'title': titleCtrl.text,
                      'detail': detailCtrl.text.isEmpty ? 'مناسبة سنوية' : detailCtrl.text,
                      'advanceReminder': selectedAdvanceReminder,
                      'eventDate': selectedEventDate.toIso8601String(),
                      'reminderHour': reminderTime.hour,
                      'reminderMinute': reminderTime.minute,
                    });
                  });
                  _saveData();
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ المناسبة', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _addNewTaskDialog() {
    TextEditingController taskCtrl = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    bool setAlarm = true;
    String selectedRepeat = 'مرة واحدة';
    String selectedInterval = 'كل 5 دقايق';

    final List<String> repeatOptions = ['مرة واحدة', 'يومي', 'أسبوعي', 'شهري', 'مخصص'];
    final List<String> intervalOptions = ['مرة واحدة', 'كل دقيقة', 'كل دقيقتين', 'كل 3 دقايق', 'كل 5 دقايق', 'كل 10 دقايق'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('إضافة موعد جديد', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: taskCtrl,
                  decoration: const InputDecoration(labelText: 'تفاصيل المهمة / الموعد'),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الوقت: ${selectedTime.format(context)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      icon: const Icon(Icons.access_time, color: Color(0xFFC5A059)),
                      label: const Text('تحديد', style: TextStyle(color: Color(0xFF1B2A4A))),
                      onPressed: () async {
                        TimeOfDay? t = await showTimePicker(context: context, initialTime: selectedTime);
                        if (t != null) setStateSB(() => selectedTime = t);
                      },
                    )
                  ],
                ),
                const Divider(),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('التكرار:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedRepeat,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: repeatOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (val) => setStateSB(() => selectedRepeat = val ?? 'مرة واحدة'),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('التنبيه المستمر:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedInterval,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: intervalOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (val) => setStateSB(() => selectedInterval = val ?? 'كل 5 دقايق'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل التنبيه الصوتي'),
                  value: setAlarm,
                  activeColor: const Color(0xFF1B2A4A),
                  onChanged: (v) => setStateSB(() => setAlarm = v ?? false),
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () {
                if (taskCtrl.text.isNotEmpty) {
                  DateTime scheduledDateTime = DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  );

                  setState(() {
                    _tasks.add({
                      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
                      'task': taskCtrl.text,
                      'time': selectedTime.format(context),
                      'alarm': setAlarm,
                      'scheduled': scheduledDateTime.toIso8601String(),
                      'repeat': selectedRepeat,
                      'repeatInterval': selectedInterval,
                    });
                  });

                  _saveData();

                  if (setAlarm) {
                    _scheduleContinuousAlarm(taskCtrl.text, scheduledDateTime, selectedRepeat, selectedInterval);
                  }

                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ الموعد', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _openDiaryPage(DateTime date) {
    String formattedDateKey = DateFormat('yyyy-MM-dd').format(date);
    String dayName = DateFormat('EEEE', 'ar').format(date);
    String fullDateFormatted = DateFormat('dd MMMM yyyy', 'ar').format(date);

    TextEditingController diaryCtrl = TextEditingController(text: _diaries[formattedDateKey] ?? '');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B2A4A),
            foregroundColor: Colors.white,
            title: const Text('تدوين اليوميات'),
            actions: [
              IconButton(
                icon: const Icon(Icons.check, color: Color(0xFFC5A059), size: 28),
                onPressed: () {
                  setState(() {
                    _diaries[formattedDateKey] = diaryCtrl.text;
                  });
                  _saveData();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حفظ اليومية بنجاح!')),
                  );
                },
              )
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F9),
                    borderRadius: BorderRadius.circular(12),
                    border: const Border(right: BorderSide(color: Color(0xFFC5A059), width: 4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('اليوم: $dayName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
                      const SizedBox(height: 4),
                      Text('التاريخ: $fullDateFormatted', style: const TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: TextField(
                    controller: diaryCtrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                    decoration: const InputDecoration(
                      hintText: 'اكتب يومياتك وأفكارك هنا بكل حرية...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      _buildCalendarAndTasksTab(),
      _buildDiariesTab(),
      _buildPrayerTimesTab(),
      _buildSpecialEventsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B2A4A),
        foregroundColor: Colors.white,
        elevation: 3,
        title: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFC5A059),
              child: ClipOval(
                child: Image.asset(
                  _secretaryImagePath,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.3),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('السكرتيرة: ${widget.secretaryName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Text('هز الهاتف للتحدث مع السكرتيرة', style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? Colors.redAccent : const Color(0xFFC5A059)),
            onPressed: _listenVoiceCommand,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFFC5A059)),
            onPressed: _openSettingsScreen,
          ),
        ],
      ),
      body: screens[_currentIndex],
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _addNewTaskDialog,
              backgroundColor: const Color(0xFF1B2A4A),
              icon: const Icon(Icons.add, color: Color(0xFFC5A059)),
              label: const Text('إضافة موعد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : (_currentIndex == 3
              ? FloatingActionButton.extended(
                  onPressed: _addSpecialEventDialog,
                  backgroundColor: const Color(0xFF1B2A4A),
                  icon: const Icon(Icons.card_giftcard, color: Color(0xFFC5A059)),
                  label: const Text('إضافة مناسبة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              : null),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: const Color(0xFF1B2A4A),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'التقويم والمهام'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'يومياتي'),
          BottomNavigationBarItem(icon: Icon(Icons.access_time_filled), label: 'مواقيت الصلاة'),
          BottomNavigationBarItem(icon: Icon(Icons.stars), label: 'المناسبات'),
        ],
      ),
    );
  }

  Widget _buildCalendarAndTasksTab() {
    String formattedSelectedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String currentTimeStr = DateFormat('hh:mm a', 'ar').format(DateTime.now());
    var dayTasks = _tasks.where((t) => t['date'] == formattedSelectedDate).toList();
    String userTitle = _userTitle;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B2A4A), Color(0xFF2C3E50)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFC5A059), width: 2),
                    image: const DecorationImage(
                      image: AssetImage(_secretaryImagePath),
                      fit: BoxFit.cover,
                      alignment: Alignment(0, -0.3),
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
                      Text('الوقت الحالي: $currentTimeStr', style: const TextStyle(fontSize: 13, color: Color(0xFFC5A059), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('📳 هُز الهاتف في أي وقت أو نادِ باسم السكرتيرة.', style: TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8EE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC5A059), width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
            ),
            child: CalendarDatePicker(
              key: ValueKey(formattedSelectedDate),
              initialDate: _selectedDate,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
              onDateChanged: (d) => setState(() => _selectedDate = d),
            ),
          ),
          const SizedBox(height: 15),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('جدول أعمال اليوم:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
                Chip(
                  label: Text('${dayTasks.length} مواعيد', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  backgroundColor: const Color(0xFF1B2A4A),
                ),
              ],
            ),
          ),
          dayTasks.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      Icon(Icons.event_note, size: 50, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text('لا توجد مواعيد مسجلة لهذا اليوم', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: dayTasks.length,
                  itemBuilder: (ctx, i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: const Border(right: BorderSide(color: Color(0xFFC5A059), width: 5)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5)],
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.alarm, color: Color(0xFF1B2A4A)),
                      title: Text(dayTasks[i]['task'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      subtitle: Text('الموعد: ${dayTasks[i]['time']} • ${dayTasks[i]['repeat'] ?? 'مرة واحدة'} • ${dayTasks[i]['repeatInterval'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          dayTasks[i]['alarm'] == true
                              ? const Icon(Icons.notifications_active, color: Colors.redAccent)
                              : const Icon(Icons.notifications_off, color: Colors.grey),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteTask(_tasks.indexOf(dayTasks[i])),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDiariesTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2A4A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📖 مفكرة اليوميات الخاصة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 5),
                Text('اختر أي يوم من التقويم لفتح صفحة التدوين البيضاء.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC5A059), width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
            ),
            child: CalendarDatePicker(
              initialDate: _diaryDate,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
              onDateChanged: (selectedDay) {
                setState(() {
                  _diaryDate = selectedDay;
                });
                _openDiaryPage(selectedDay);
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B2A4A),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.edit_note, color: Color(0xFFC5A059)),
              label: const Text('فتح يومية اليوم المحدد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () => _openDiaryPage(_diaryDate),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPrayerTimesTab() {
    return FutureBuilder<Map<String, String>>(
      future: _calculatePrayerTimes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final times = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF0F172A)]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFC5A059), width: 1.5),
              ),
              child: const Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.access_time_filled, color: Color(0xFFC5A059), size: 22),
                      SizedBox(width: 8),
                      Text('مواقيت الصلاة اليوم', style: TextStyle(color: Color(0xFFC5A059), fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            _prayerCard('الفجر', times['fajr']!, Icons.wb_twilight),
            _prayerCard('الشروق', times['sunrise']!, Icons.wb_sunny_outlined),
            _prayerCard('الظهر', times['dhuhr']!, Icons.wb_sunny),
            _prayerCard('العصر', times['asr']!, Icons.filter_drama),
            _prayerCard('المغرب', times['maghrib']!, Icons.nights_stay_outlined),
            _prayerCard('العشاء', times['isha']!, Icons.nights_stay),
          ],
        );
      },
    );
  }

  Future<Map<String, String>> _calculatePrayerTimes() async {
    try {
      final coordinates = Coordinates(30.0444, 31.2357);
      final date = DateComponents.from(DateTime.now());
      final params = CalculationMethod.egyptian.getParameters();
      params.madhab = Madhab.shafi;
      final prayerTimes = PrayerTimes(coordinates, date, params);

      final format = DateFormat('hh:mm a', 'ar');
      return {
        'fajr': format.format(prayerTimes.fajr),
        'sunrise': format.format(prayerTimes.sunrise),
        'dhuhr': format.format(prayerTimes.dhuhr),
        'asr': format.format(prayerTimes.asr),
        'maghrib': format.format(prayerTimes.maghrib),
        'isha': format.format(prayerTimes.isha),
      };
    } catch (e) {
      final format = DateFormat('hh:mm a', 'ar');
      final now = DateTime.now();
      return {
        'fajr': format.format(DateTime(now.year, now.month, now.day, 4, 25)),
        'sunrise': format.format(DateTime(now.year, now.month, now.day, 5, 52)),
        'dhuhr': format.format(DateTime(now.year, now.month, now.day, 11, 45)),
        'asr': format.format(DateTime(now.year, now.month, now.day, 15, 8)),
        'maghrib': format.format(DateTime(now.year, now.month, now.day, 17, 38)),
        'isha': format.format(DateTime(now.year, now.month, now.day, 18, 55)),
      };
    }
  }

  Widget _prayerCard(String title, String time, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1B2A4A)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
        trailing: Text(time, style: const TextStyle(color: Color(0xFF1B2A4A), fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSpecialEventsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('أقسام المناسبات والتنبيهات المسبقة:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
        const SizedBox(height: 10),
        InkWell(
          onTap: _addSpecialEventDialog,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const ListTile(
              leading: Icon(Icons.cake, color: Colors.pink, size: 32),
              title: Text('أعياد الميلاد (اضغط للإضافة)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('تنبيهات مسبقة قبل الموعد بيوم أو أسبوع أو شهر'),
              trailing: Icon(Icons.add_circle, color: Color(0xFF1B2A4A)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('قائمة المناسبات المسجلة:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
        const SizedBox(height: 10),
        if (_specialEvents.isEmpty)
          Container(
            padding: const EdgeInsets.all(30),
            child: Column(
              children: [
                Icon(Icons.stars, size: 50, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                const Text('لا توجد مناسبات مسجلة بعد', style: TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          )
        else
          ..._specialEvents.map((e) {
            final eventDate = DateTime.tryParse(e['eventDate'] ?? '') ?? DateTime.now();
            final now = DateTime.now();
            final thisYear = DateTime(now.year, eventDate.month, eventDate.day);
            final nextYear = DateTime(now.year + 1, eventDate.month, eventDate.day);
            final nextOccurrence = thisYear.isAfter(now) ? thisYear : nextYear;
            final daysLeft = nextOccurrence.difference(now).inDays;
            final reminderTime = '${(e['reminderHour'] ?? 18).toString().padLeft(2, '0')}:${(e['reminderMinute'] ?? 0).toString().padLeft(2, '0')}';
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
                subtitle: Text('${e['detail']} • ${DateFormat('yyyy/MM/dd').format(eventDate)}\nالتذكير: ${e['advanceReminder'] ?? "قبلها بيوم"} الساعة $reminderTime • فاضل $daysLeft يوم'),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _specialEvents.remove(e);
                    });
                    _saveData();
                  },
                ),
              ),
            );
          }),
      ],
    );
  }
}
