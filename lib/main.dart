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

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

final FlutterTts _appTts = FlutterTts();

const List<String> _weekDays = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];

const MethodChannel _lockScreenChannel = MethodChannel('com.example.secretary_app/lock_screen');

const Map<String, String> _maleNamesMap = {
  'محمد': 'assets/mohamed.jpg',
  'أحمد': 'assets/ahmed.jpg',
  'علي': 'assets/ali.jpg',
  'عمر': 'assets/omar.jpg',
  'يوسف': 'assets/youssef.jpg',
};

const Map<String, String> _femaleNamesMap = {
  'سارة': 'assets/secretary.jpg',
  'مريم': 'assets/maryam.jpg',
  'ندى': 'assets/nada.jpg',
  'نور': 'assets/noor.jpg',
  'ياسمين': 'assets/yasmine.jpg',
};

const String _defaultMaleImage = 'assets/mohamed.jpg';
const String _defaultFemaleImage = 'assets/secretary.jpg';

String _getSecretaryImage(String name, String voiceGender) {
  if (_maleNamesMap.containsKey(name)) return _maleNamesMap[name]!;
  if (_femaleNamesMap.containsKey(name)) return _femaleNamesMap[name]!;
  return voiceGender == 'ذكر' ? _defaultMaleImage : _defaultFemaleImage;
}

List<String> _getNamesForGender(String voiceGender) {
  return voiceGender == 'ذكر' ? _maleNamesMap.keys.toList() : _femaleNamesMap.keys.toList();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  tz.initializeTimeZones();
  await _initNotifications();

  try {
    await _appTts.setLanguage("ar-EG");
    await Future.delayed(const Duration(milliseconds: 200));
  } catch (_) {}

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
  await _notifications.initialize(initSettings);
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

class AppSettings {
  int defaultReminderHour;
  int defaultReminderMinute;
  String voiceLevel;
  bool greetingEnabled;
  bool adhanAlertEnabled;
  bool showAboveLockScreen;
  bool shakeInBackgroundEnabled;
  String voiceGender;
  String defaultInterval;

  AppSettings({
    this.defaultReminderHour = 18,
    this.defaultReminderMinute = 0,
    this.voiceLevel = 'عالي',
    this.greetingEnabled = true,
    this.adhanAlertEnabled = true,
    this.showAboveLockScreen = false,
    this.shakeInBackgroundEnabled = true,
    this.voiceGender = 'ذكر',
    this.defaultInterval = 'كل 10 ثواني',
  });

  double get speechRate {
    switch (voiceLevel) {
      case 'منخفض': return 0.35;
      case 'متوسط': return 0.42;
      default: return 0.48;
    }
  }

  double get speechVolume {
    switch (voiceLevel) {
      case 'منخفض': return 0.4;
      case 'متوسط': return 0.7;
      default: return 1.0;
    }
  }
}

// ═══════════════════════════════════════
// SettingsScreen
// ═══════════════════════════════════════
class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final double ttsVolume;
  final String currentSecretaryName;
  final bool currentIsUserMale;
  final Future<void> Function(
    int hour, int minute, String voiceLevel,
    bool greeting, bool adhan, double ttsVol,
    bool showLock, bool shakeBg, String voiceGender,
    String defaultInterval,
  ) onSave;
  final Future<void> Function(String name, String voiceGender) onSaveSecretary;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.ttsVolume,
    required this.currentSecretaryName,
    required this.currentIsUserMale,
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
  late bool _shakeInBackground;
  late String _voiceGender;
  late String _defaultInterval;
  late String _secretaryName;
  final TextEditingController _nameController = TextEditingController();

  late int _origDefaultReminderHour;
  late int _origDefaultReminderMinute;
  late String _origVoiceLevel;
  late bool _origGreetingEnabled;
  late bool _origAdhanAlertEnabled;
  late double _origTtsVolume;
  late bool _origShowAboveLockScreen;
  late bool _origShakeInBackground;
  late String _origVoiceGender;
  late String _origDefaultInterval;
  late String _origSecretaryName;

  String? _maleVoiceName;
  String? _femaleVoiceName;
  bool _isPickingVoice = false;

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
    _shakeInBackground = widget.settings.shakeInBackgroundEnabled;
    _voiceGender = widget.settings.voiceGender;
    _defaultInterval = widget.settings.defaultInterval;
    _secretaryName = widget.currentSecretaryName;
    _nameController.text = _secretaryName;

    _origDefaultReminderHour = _defaultReminderHour;
    _origDefaultReminderMinute = _defaultReminderMinute;
    _origVoiceLevel = _voiceLevel;
    _origGreetingEnabled = _greetingEnabled;
    _origAdhanAlertEnabled = _adhanAlertEnabled;
    _origTtsVolume = _ttsVolume;
    _origShowAboveLockScreen = _showAboveLockScreen;
    _origShakeInBackground = _shakeInBackground;
    _origVoiceGender = _voiceGender;
    _origDefaultInterval = _defaultInterval;
    _origSecretaryName = _secretaryName;

    _loadSavedVoices();
  }

  Future<void> _loadSavedVoices() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _maleVoiceName = prefs.getString('male_voice_name');
      _femaleVoiceName = prefs.getString('female_voice_name');
    });
  }

  Future<void> _pickVoiceFor(String gender) async {
    if (_isPickingVoice) return;
    setState(() => _isPickingVoice = true);

    try {
      await _appTts.stop();
      await Future.delayed(const Duration(milliseconds: 200));

      List<Map<String, String>> voices = [];
      try {
        final rawVoices = await _appTts.getVoices;
        if (rawVoices is List) {
          for (final v in rawVoices) {
            if (v is Map) {
              final name = v['name']?.toString() ?? '';
              final locale = v['locale']?.toString() ?? '';
              if (locale.toLowerCase().startsWith('ar') && name.isNotEmpty) {
                voices.add({'name': name, 'locale': locale});
              }
            }
          }
        }
      } catch (_) {}

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final key = gender == 'ذكر' ? 'male_voice_name' : 'female_voice_name';
      final localeKey = gender == 'ذكر' ? 'male_voice_locale' : 'female_voice_locale';
      final saved = prefs.getString(key);
      final savedLocale = prefs.getString(localeKey) ?? 'ar-EG';

      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => VoicePickerDialog(
          gender: gender,
          voices: voices,
          initialVoiceName: saved,
          initialLocale: savedLocale,
        ),
      );

      if (result != null) {
        await prefs.setString(key, result['name']!);
        await prefs.setString(localeKey, result['locale']!);
        try { await _appTts.stop(); } catch (_) {}
        if (!mounted) return;
        setState(() {
          if (gender == 'ذكر') _maleVoiceName = result['name'];
          else _femaleVoiceName = result['name'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ تم حفظ صوت $gender: ${result['name']}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingVoice = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
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
        _shakeInBackground != _origShakeInBackground ||
        _voiceGender != _origVoiceGender ||
        _defaultInterval != _origDefaultInterval ||
        _nameController.text != _origSecretaryName;
  }

  Future<void> _save() async {
    final newName = _nameController.text.trim().isEmpty
        ? (_voiceGender == 'ذكر' ? 'محمد' : 'سارة')
        : _nameController.text.trim();

    await widget.onSave(
      _defaultReminderHour, _defaultReminderMinute, _voiceLevel,
      _greetingEnabled, _adhanAlertEnabled, _ttsVolume,
      _showAboveLockScreen, _shakeInBackground, _voiceGender,
      _defaultInterval,
    );
    await widget.onSaveSecretary(newName, _voiceGender);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = _getNamesForGender(_voiceGender);
    final secTitle = _voiceGender == 'ذكر' ? 'السكرتير' : 'السكرتيرة';

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B2A4A),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: _isPickingVoice ? null : () => _pickVoiceFor('ذكر'),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.record_voice_over, color: Color(0xFF1B2A4A), size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🎧 صوت السكرتير (راجل)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(
                            _maleVoiceName ?? 'اضغط لاختيار الصوت',
                            style: TextStyle(
                              fontSize: 12,
                              color: _maleVoiceName != null ? const Color(0xFFC5A059) : Colors.grey,
                              fontWeight: _maleVoiceName != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF1B2A4A)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: _isPickingVoice ? null : () => _pickVoiceFor('أنثى'),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.record_voice_over, color: Color(0xFF1B2A4A), size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🎧 صوت السكرتيرة (ست)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(
                            _femaleVoiceName ?? 'اضغط لاختيار الصوت',
                            style: TextStyle(
                              fontSize: 12,
                              color: _femaleVoiceName != null ? const Color(0xFFC5A059) : Colors.grey,
                              fontWeight: _femaleVoiceName != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF1B2A4A)),
                  ],
                ),
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
                    const Icon(Icons.face_3, color: Color(0xFF1B2A4A), size: 26),
                    const SizedBox(width: 10),
                    Text(secTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 15),
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFC5A059), width: 3),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8)],
                        image: DecorationImage(
                          image: AssetImage(_getSecretaryImage(_nameController.text, _voiceGender)),
                          fit: BoxFit.cover, alignment: const Alignment(0, -0.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text('اختر اسماً:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                        onPressed: () => setState(() => _nameController.text = name),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.access_time, color: Color(0xFF1B2A4A), size: 30),
              title: const Text('وقت التذكير الافتراضي للمناسبات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_defaultReminderHour.toString().padLeft(2, '0')}:${_defaultReminderMinute.toString().padLeft(2, '0')}',
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
                  const SizedBox(height: 6),
                  const Text('ده اللي هيبقى الوضع الافتراضي لما تضيف موعد جديد',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
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
                  const Row(children: [
                    Icon(Icons.volume_up, color: Color(0xFF1B2A4A), size: 26),
                    SizedBox(width: 10),
                    Text('مستوى الصوت', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _voiceLevel,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: ['عالي', 'متوسط', 'منخفض'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (val) => setState(() => _voiceLevel = val ?? 'عالي'),
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
                  _showAboveLockScreen ? 'التطبيق هيظهر تلقائياً عند التنبيه حتى لو التابلت مقفول' : 'التطبيق مش هيظهر والتابلت مقفول (أأمن)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              value: _showAboveLockScreen,
              activeColor: const Color(0xFFC5A059),
              onChanged: (v) => setState(() => _showAboveLockScreen = v),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _shakeInBackground ? const Color(0xFFC5A059) : Colors.transparent, width: 2),
            ),
            child: SwitchListTile(
              secondary: Icon(Icons.vibration, color: _shakeInBackground ? const Color(0xFFC5A059) : const Color(0xFF1B2A4A), size: 26),
              title: const Text('تشغيل الهز في الخلفية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _shakeInBackground ? 'الهز هيشتغل حتى لو التطبيق في الخلفية' : 'الهز مش هيشتغل غير لما التطبيق مفتوح قدامك',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              value: _shakeInBackground,
              activeColor: const Color(0xFFC5A059),
              onChanged: (v) => setState(() => _shakeInBackground = v),
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
        ],
      ),
    );
  }
}
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
        secretaryName: savedName ?? 'محمد',
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
    await Permission.notification.request();

    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }

    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    final micGranted = await Permission.microphone.isGranted;
    final batteryGranted = await Permission.ignoreBatteryOptimizations.isGranted;

    if (mounted) setState(() => _isRequesting = false);

    if (!micGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ محتاج إذن المايكروفون'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!batteryGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ محتاج تسمح للتطبيق يشتغل في الخلفية'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SetupSecretaryScreen()),
      );
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
                      SizedBox(height: 5),
                      Text('• المنبهات الدقيقة: لضبط مواقيت الأذان بدقة.', style: TextStyle(fontSize: 14, height: 1.6)),
                      SizedBox(height: 5),
                      Text('• تجاهل تحسين البطارية: ليعمل التطبيق في الخلفية بدون توقف.', style: TextStyle(fontSize: 14, height: 1.6)),
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
  String? _savedVoiceName;
  bool _isPickingVoice = false;

  @override
  void initState() {
    super.initState();
    _loadSavedVoice();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedVoice() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _voiceGender == 'ذكر' ? 'male_voice_name' : 'female_voice_name';
    if (!mounted) return;
    setState(() => _savedVoiceName = prefs.getString(key));
  }

  Future<void> _pickVoice() async {
    if (_isPickingVoice) return;
    setState(() => _isPickingVoice = true);

    try {
      await _appTts.stop();
      await Future.delayed(const Duration(milliseconds: 200));

      List<Map<String, String>> voices = [];
      try {
        final rawVoices = await _appTts.getVoices;
        if (rawVoices is List) {
          for (final v in rawVoices) {
            if (v is Map) {
              final name = v['name']?.toString() ?? '';
              final locale = v['locale']?.toString() ?? '';
              if (locale.toLowerCase().startsWith('ar') && name.isNotEmpty) {
                voices.add({'name': name, 'locale': locale});
              }
            }
          }
        }
      } catch (_) {}

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final key = _voiceGender == 'ذكر' ? 'male_voice_name' : 'female_voice_name';
      final localeKey = _voiceGender == 'ذكر' ? 'male_voice_locale' : 'female_voice_locale';
      final saved = prefs.getString(key);
      final savedLocale = prefs.getString(localeKey) ?? 'ar-EG';

      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => VoicePickerDialog(
          gender: _voiceGender,
          voices: voices,
          initialVoiceName: saved,
          initialLocale: savedLocale,
        ),
      );

      if (result != null) {
        await prefs.setString(key, result['name']!);
        await prefs.setString(localeKey, result['locale']!);
        try { await _appTts.stop(); } catch (_) {}
        if (!mounted) return;
        setState(() => _savedVoiceName = result['name']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ تم حفظ الصوت: ${result['name']}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingVoice = false);
    }
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
          builder: (_) => MainDashboard(secretaryName: name, isUserMale: _userGender == 'male'),
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
                    fit: BoxFit.cover, alignment: const Alignment(0, -0.4),
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
                        _loadSavedVoice();
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
                        _loadSavedVoice();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              InkWell(
                onTap: _isPickingVoice ? null : _pickVoice,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2A4A).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFC5A059), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.volume_up, color: Color(0xFFC5A059), size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'اختيار صوت $secTitle',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _savedVoiceName ?? 'اضغط للاختيار من الأصوات المتاحة',
                              style: TextStyle(
                                fontSize: 11,
                                color: _savedVoiceName != null ? Colors.black87 : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF1B2A4A)),
                    ],
                  ),
                ),
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
                child: Text('اختر اسماً أو اكتب اسماً مخصصاً:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

// ═══════════════════════════════════════
// VoicePickerDialog — مع awaitSpeakCompletion
// ═══════════════════════════════════════
class VoicePickerDialog extends StatefulWidget {
  final String gender;
  final List<Map<String, String>> voices;
  final String? initialVoiceName;
  final String initialLocale;

  const VoicePickerDialog({
    super.key,
    required this.gender,
    required this.voices,
    this.initialVoiceName,
    this.initialLocale = 'ar-EG',
  });

  @override
  State<VoicePickerDialog> createState() => _VoicePickerDialogState();
}

class _VoicePickerDialogState extends State<VoicePickerDialog> {
  String? _selected;
  String _selectedLocale = 'ar-EG';
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialVoiceName;
    _selectedLocale = widget.initialLocale;
    _appTts.awaitSpeakCompletion(true);
  }

  Future<void> _testVoice(String name, String locale) async {
    if (_isTesting) return;
    setState(() => _isTesting = true);
    try {
      await _appTts.stop();
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        await _appTts.setVoice({'name': name, 'locale': locale});
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
      await _appTts.setSpeechRate(0.48);
      await _appTts.setVolume(1.0);
      await _appTts.speak(widget.gender == 'ذكر'
          ? "مرحباً، أنا سكرتيرك الشخصي"
          : "مرحباً، أنا سكرتيرتك الشخصية");
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.gender == 'ذكر'
        ? '🎧 اختر صوت السكرتير (راجل)'
        : '🎧 اختر صوت السكرتيرة (ست)';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.voices.isEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 50),
                  SizedBox(height: 10),
                  Text('مفيش أصوات عربية على الجهاز',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                    'من فضلك نزّل حزمة اللغة العربية من إعدادات Google TTS',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.voices.length,
                itemBuilder: (ctx, i) {
                  final v = widget.voices[i];
                  final name = v['name'] ?? '';
                  final locale = v['locale'] ?? '';
                  final isSelected = _selected == name;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFC5A059).withOpacity(0.15)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFC5A059)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Radio<String>(
                        value: name,
                        groupValue: _selected,
                        activeColor: const Color(0xFF1B2A4A),
                        onChanged: (val) {
                          setState(() {
                            _selected = val;
                            _selectedLocale = locale;
                          });
                        },
                      ),
                      title: Text(name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          )),
                      subtitle: Text('اللغة: $locale',
                          style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      trailing: IconButton(
                        icon: Icon(
                          _isTesting ? Icons.hourglass_top : Icons.volume_up,
                          color: const Color(0xFF1B2A4A),
                        ),
                        onPressed: _isTesting ? null : () => _testVoice(name, locale),
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
          onPressed: _selected == null
              ? null
              : () {
                  Navigator.pop(context, {
                    'name': _selected,
                    'locale': _selectedLocale,
                  });
                },
          child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
// ═══════════════════════════════════════
// MainDashboard
// ═══════════════════════════════════════
class MainDashboard extends StatefulWidget {
  final String secretaryName;
  final bool isUserMale;

  const MainDashboard({super.key, required this.secretaryName, this.isUserMale = true});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  FlutterTts get _tts => _appTts;

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _starting = false;
  bool _isListening = false;
  int _currentIndex = 0;
  DateTime _selectedDate = DateTime.now();
  DateTime _diaryDate = DateTime.now();
  DateTime? _lastShake;

  late String _secretaryName;
  late bool _isUserMale;

  bool _isInBackground = false;

  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _specialEvents = [];
  Map<String, String> _diaries = {};
  AppSettings _settings = AppSettings();

  final Set<Timer> _activeTimers = {};
  StreamSubscription? _accelerometerSub;
  Timer? _adhanTimer;
  bool _adhanAlerted = false;

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

  static const Map<String, List<String>> _dayKeywords = {
    'السبت': ['السبت', 'سبت', 'يوم السبت', 'السبت الجاي'],
    'الأحد': ['الاحد', 'الأحد', 'حد', 'يوم الاحد'],
    'الاثنين': ['الاتنين', 'الاثنين', 'اتنين', 'يوم الاتنين'],
    'الثلاثاء': ['التلات', 'الثلاثاء', 'تلات', 'يوم التلات'],
    'الأربعاء': ['الاربع', 'الأربعاء', 'اربع', 'يوم الاربع'],
    'الخميس': ['الخميس', 'خميس', 'يوم الخميس'],
    'الجمعة': ['الجمعه', 'الجمعة', 'جمعه', 'جمعة', 'يوم الجمعه'],
  };

  String get _userTitle => _isUserMale ? "يا فندم" : "يا أستاذة";
  String get _secTitle => _settings.voiceGender == 'ذكر' ? 'السكرتير' : 'السكرتيرة';
  String get _secWord => _settings.voiceGender == 'ذكر' ? 'سكرتيرك' : 'سكرتيرتك';

  String get _pronoun => _isUserMale ? "وانت" : "وانتي";
  String get _takeCareWord => _isUserMale ? "خد" : "خدي";
  String get _readyWord => _settings.voiceGender == 'ذكر' ? "جاهز" : "جاهزة";
  String get _happyWord => _settings.voiceGender == 'ذكر' ? "مبسوط" : "مبسوطة";
  String get _listenWord => _settings.voiceGender == 'ذكر' ? "سامعك" : "سامعاك";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _secretaryName = widget.secretaryName;
    _isUserMale = widget.isUserMale;
    _initAll();
  }

  Future<void> _initAll() async {
    await _loadData();
    await _loadRecordings();
    await _configureVoice();
    _initSpeech();
    _initShakeDetector();
    _startAdhanWatcher();
    _scheduleAdhan30Days();
    Future.delayed(const Duration(seconds: 3), _checkPendingEventAnnouncements);
    Future.delayed(const Duration(seconds: 2), _checkPendingAlarm);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      Future.delayed(const Duration(milliseconds: 500), _checkPendingAlarm);
      Future.delayed(const Duration(seconds: 2), _checkPendingEventAnnouncements);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _isInBackground = true;
    }
  }

  Future<void> _checkPendingAlarm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingStr = prefs.getString('pending_alarm');
      if (pendingStr == null) return;

      final data = json.decode(pendingStr) as Map<String, dynamic>;
      final scheduledMillis = data['scheduledMillis'] as int?;
      final title = data['title'] as String? ?? '';
      final repeat = data['repeat'] as String? ?? 'مرة واحدة';
      final interval = data['interval'] as String? ?? 'بدون تنبيه';
      final customDays = List<String>.from(data['customDays'] ?? []);

      if (scheduledMillis == null || title.isEmpty) {
        await prefs.remove('pending_alarm');
        return;
      }

      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      final diff = nowMillis - scheduledMillis;

      if (diff > 5 * 60 * 1000) {
        await prefs.remove('pending_alarm');
        return;
      }
      if (diff < -60 * 1000) return;

      await prefs.remove('pending_alarm');
      if (mounted) {
        _startAlarmLoop(
          title,
          repeat,
          interval,
          customDays,
          DateTime.fromMillisecondsSinceEpoch(scheduledMillis),
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

      if (title.isNotEmpty && mounted) {
        _showEventReminder(title, detail, interval);
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

  // ✅ v2 + audioAttributesUsage
  Future<void> _scheduleAdhan30Days() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('adhan_schedule_start_date', DateTime.now().toIso8601String());

      for (int day = 0; day < 30; day++) {
        for (final prayer in ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']) {
          await _notifications.cancel((day * 10) + prayer.hashCode);
        }
      }

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

          final androidDetails = AndroidNotificationDetails(
            'adhan_channel_v2',
            'تنبيهات الأذان v2',
            channelDescription: 'تنبيهات مواقيت الصلاة',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(sounds[prayer]),
            enableVibration: true,
            category: AndroidNotificationCategory.alarm,
            autoCancel: false,
            ongoing: true,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          );

          await _notifications.zonedSchedule(
            (day * 10) + prayer.hashCode,
            'حان الآن موعد صلاة ${names[prayer]}',
            'موعد صلاة ${names[prayer]}',
            tz.TZDateTime.from(prayerTime, tz.local),
            NotificationDetails(android: androidDetails),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    } catch (_) {}
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
        if (_isInBackground && !_settings.shakeInBackgroundEnabled) return;
        _lastShake = now;
        if (!_isListening && !_starting && !_isRecording) _listenVoiceCommand();
      }
    });
  }

  void _startAdhanWatcher() {
    _adhanTimer?.cancel();
    _adhanTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _settings.adhanAlertEnabled) _checkAdhanTime();
    });
  }

  Future<void> _checkAdhanTime() async {
    if (!_settings.adhanAlertEnabled) return;
    try {
      final times = await _calculatePrayerTimes();
      final now = DateTime.now();
      final currentTime = DateFormat('HH:mm').format(now);

      final Map<String, String> prayerMap = {
        'الفجر': times['fajr'] ?? '', 'الظهر': times['dhuhr'] ?? '',
        'العصر': times['asr'] ?? '', 'المغرب': times['maghrib'] ?? '', 'العشاء': times['isha'] ?? '',
      };

      final prefs = await SharedPreferences.getInstance();
      final startDateStr = prefs.getString('adhan_schedule_start_date');
      int dayOffset = 0;
      if (startDateStr != null) {
        final startDate = DateTime.parse(startDateStr);
        dayOffset = now.difference(startDate).inDays;
      }

      for (final entry in prayerMap.entries) {
        try {
          final prayerTime = DateFormat('hh:mm a', 'ar').parse(entry.value);
          final prayerDateTime = DateTime(now.year, now.month, now.day, prayerTime.hour, prayerTime.minute);
          final prayerStr = DateFormat('HH:mm').format(prayerDateTime);
          final oneMinBeforeStr = DateFormat('HH:mm').format(prayerDateTime.subtract(const Duration(minutes: 1)));

          if (oneMinBeforeStr == currentTime && dayOffset >= 0 && dayOffset < 30) {
            final key = _prayerKey(entry.key);
            if (key.isNotEmpty) {
              await _notifications.cancel((dayOffset * 10) + key.hashCode);
            }
          }

          if (prayerStr == currentTime && !_adhanAlerted) {
            _adhanAlerted = true;
            await _speak("حان الآن موعد أذان ${entry.key}");
            Future.delayed(const Duration(minutes: 2), () => _adhanAlerted = false);
          }
        } catch (_) {}
      }
    } catch (_) {}
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
            _scheduleContinuousAlarm(t['task'].toString(), dt, t['repeat'] ?? 'مرة واحدة', t['repeatInterval'] ?? 'كل 10 ثواني', List<String>.from(t['customDays'] ?? []));
          }
        }
      }
    }
    String? eventsString = prefs.getString('saved_events');
    if (eventsString != null) {
      setState(() {
        _specialEvents = List<Map<String, dynamic>>.from(json.decode(eventsString));
      });
      for (final e in _specialEvents) {
        _scheduleEventReminder(e);
      }
    } else {
      setState(() => _specialEvents = []);
    }
    String? diariesString = prefs.getString('saved_diaries');
    if (diariesString != null) {
      setState(() {
        _diaries = Map<String, String>.from(json.decode(diariesString));
      });
    }
    _settings.defaultReminderHour = prefs.getInt('default_reminder_hour') ?? 18;
    _settings.defaultReminderMinute = prefs.getInt('default_reminder_minute') ?? 0;
    _settings.voiceLevel = prefs.getString('voice_level') ?? 'عالي';
    _settings.greetingEnabled = prefs.getBool('greeting_enabled') ?? true;
    _settings.adhanAlertEnabled = prefs.getBool('adhan_alert_enabled') ?? true;
    _settings.showAboveLockScreen = prefs.getBool('show_above_lock_screen') ?? false;
    _settings.shakeInBackgroundEnabled = prefs.getBool('shake_in_background') ?? true;
    _settings.voiceGender = prefs.getString('voice_gender') ?? 'ذكر';
    _settings.defaultInterval = prefs.getString('default_interval') ?? 'كل 10 ثواني';
    _playbackVolume = prefs.getDouble('playback_volume') ?? 1.0;
    _playbackSpeed = prefs.getDouble('playback_speed') ?? 1.0;
    _ttsVolume = prefs.getDouble('tts_volume') ?? 1.0;
    if (mounted) setState(() {});
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
    await prefs.setBool('adhan_alert_enabled', _settings.adhanAlertEnabled);
    await prefs.setBool('show_above_lock_screen', _settings.showAboveLockScreen);
    await prefs.setBool('shake_in_background', _settings.shakeInBackgroundEnabled);
    await prefs.setString('voice_gender', _settings.voiceGender);
    await prefs.setString('default_interval', _settings.defaultInterval);
    await prefs.setDouble('playback_volume', _playbackVolume);
    await prefs.setDouble('playback_speed', _playbackSpeed);
    await prefs.setDouble('tts_volume', _ttsVolume);
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
    try {
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
      await Future.delayed(const Duration(milliseconds: 150));
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final gender = prefs.getString('voice_gender') ?? _settings.voiceGender;
    final key = gender == 'ذكر' ? 'male_voice_name' : 'female_voice_name';
    final localeKey = gender == 'ذكر' ? 'male_voice_locale' : 'female_voice_locale';
    final savedVoice = prefs.getString(key);
    final savedLocale = prefs.getString(localeKey) ?? 'ar-EG';

    if (savedVoice != null && savedVoice.isNotEmpty) {
      try {
        await _tts.setVoice({'name': savedVoice, 'locale': savedLocale});
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (_) {}
    } else {
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
    }

    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(_settings.speechRate);
    await _tts.setVolume(_settings.speechVolume * _ttsVolume);

    if (!skipGreeting && _settings.greetingEnabled) {
      await _tts.speak("أهلاً بك $_userTitle. أنا $_secWord $_secretaryName، هُز الهاتف في أي وقت لأكون في خدمتك.");
    }
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

  Future<void> _openVoicePicker() async {
    if (_isListening || _isRecording) return;

    await _tts.stop();
    await Future.delayed(const Duration(milliseconds: 300));

    final voices = await _getArabicVoices();
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final gender = _settings.voiceGender;
    final key = gender == 'ذكر' ? 'male_voice_name' : 'female_voice_name';
    final localeKey = gender == 'ذكر' ? 'male_voice_locale' : 'female_voice_locale';
    final saved = prefs.getString(key);
    final savedLocale = prefs.getString(localeKey) ?? 'ar-EG';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => VoicePickerDialog(
        gender: gender,
        voices: voices,
        initialVoiceName: saved,
        initialLocale: savedLocale,
      ),
    );

    if (result != null) {
      await prefs.setString(key, result['name']!);
      await prefs.setString(localeKey, result['locale']!);

      try {
        await _tts.stop();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ تم حفظ الصوت: ${result['name']}')),
        );
      }

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _configureVoice(skipGreeting: true);
      });
    }
  }

  Future<void> _speak(String text) async {
    await _tts.setSpeechRate(_settings.speechRate);
    await _tts.setVolume(_settings.speechVolume * _ttsVolume);
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
        await _speak("لا أستطيع الوصول للميكروفون $_userTitle.");
        return;
      }
      await _tts.stop();
      if (mounted) setState(() => _isListening = true);
      await _speech.listen(
        localeId: "ar-EG",
        onDevice: false,
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

  Future<bool> _handleSocialReply(String cmd) async {
    final userTitle = _userTitle;
    final secTitle = _settings.voiceGender == 'ذكر' ? 'السكرتير' : 'السكرتيرة';

    if (_hasAny(cmd, ['صباح الخير', 'صباح النور', 'صباح الفل', 'صباحو', 'صباح النور والسرور', 'صبح صباح الخير', 'صباح الخيرات'])) {
      await _speak("صباح النور والسرور $userTitle ☀️");
      return true;
    }
    if (_hasAny(cmd, ['صباح الفل والياسمين', 'صباح الورد', 'صباح العسل'])) {
      await _speak("صباح الفل والياسمين والورد $userTitle 🌸");
      return true;
    }
    if (_hasAny(cmd, ['مساء الخير', 'مساء النور', 'مساء الفل', 'مسائو', 'مسا الخير', 'مساء الخيرات'])) {
      await _speak("مساء النور والفل والياسمين $userTitle 🌙");
      return true;
    }
    if (_hasAny(cmd, ['عامله ايه', 'عاملة ايه', 'اخبارك ايه', 'اخبارك', 'أخبارك', 'ازيك', 'عامل ايه', 'كيف حالك', 'كيف الحال', 'ايه الاخبار', 'إيه الأخبار', 'الدنيا عاملة ايه'])) {
      await _speak("الحمد لله بخير، دايماً في خدمتك $userTitle 💛");
      return true;
    }
    if (_hasAny(cmd, ['عامل ايه في الدنيا', 'اخبار الدنيا', 'الدنيا ايه'])) {
      await _speak("الحمد لله، الدنيا تمام. وبيك $userTitle أكثر 💛");
      return true;
    }
    if (_hasAny(cmd, ['شكرا', 'شكراً', 'متشكر', 'متشكرة', 'مشكور', 'مشكورة', 'ربنا يخليك', 'ربنا يخليكي', 'ميرسي', 'ميرسى', 'ثانكس'])) {
      await _speak("العفو $userTitle، ده واجبي 🙏");
      return true;
    }
    if (_hasAny(cmd, ['تسلم', 'تسلمي', 'تسلم ايدك', 'تسلم إيدك'])) {
      await _speak("ربنا يسلمك $userTitle، تحت أمرك دايماً 🙏");
      return true;
    }
    if (_hasAny(cmd, ['تصبح على خير', 'تصبحى على خير', 'تصبحي على خير', 'تصبحوا على خير', 'ليلتك سعيدة', 'ليلة سعيدة'])) {
      await _speak("$_pronoun من أهله $userTitle، تصبح على خير 🌙");
      return true;
    }
    if (_hasAny(cmd, ['وحشتني', 'وحشتينى', 'وحشني', 'اشتقتلك', 'اشتقت لك', 'مشتاقلك', 'مشتاقة لك'])) {
      await _speak("$_pronoun كمان وحشتني $userTitle، أنا $_readyWord لأي خدمة 💛");
      return true;
    }
    if (_hasAny(cmd, ['اسمك ايه', 'اسمك إيه', 'اسمك ايش', 'انت مين', 'انتي مين', 'مين انت', 'مين انتي'])) {
      await _speak("اسمي $_secretaryName، $secTitle الشخصي بتاعك، تحت أمرك $userTitle");
      return true;
    }
    if (_hasAny(cmd, ['بتعمل ايه', 'بتعملي ايه', 'بتعمل إيه', 'بتشتغل ايه', 'بتشغلي ايه', 'مشغول بايه', 'مشغولة بايه'])) {
      await _speak("بستنى أوامرك $userTitle 👌");
      return true;
    }
    if (_hasAny(cmd, ['تعبان', 'تعبانة', 'مش كويس', 'مش كويسة', 'مضايق', 'مضايقة', 'زعلان', 'زعلانة', 'حزين', 'حزينة', 'مش قادر', 'مش قادرة'])) {
      await _speak("ألف سلامة عليك $userTitle، $_takeCareWord بالك من نفسك 💚");
      return true;
    }
    if (_hasAny(cmd, ['مبسوط', 'مبسوطة', 'فرحان', 'فرحانة', 'سعيد', 'سعيدة', 'الحمد لله مبسوط'])) {
      await _speak("وأنا كمان $_happyWord ليك $userTitle 😊");
      return true;
    }
    if (_hasAny(cmd, ['تمام', 'ماشي', 'اوكي', 'أوكي', 'ok', 'طيب', 'حاضر', 'خلاص كده'])) {
      await _speak("تمام $userTitle 👌");
      return true;
    }
    if (_hasAny(cmd, ['بحبك', 'احبك', 'أحبك', 'بعشقك'])) {
      await _speak("وأنا كمان بحبك $userTitle 💛");
      return true;
    }
    if (_hasAny(cmd, ['سلام عليكم', 'السلام عليكم', 'باي', 'يلا سلام', 'مع السلامة', 'سلام'])) {
      await _speak("وعليكم السلام ورحمة الله وبركاته $userTitle 🌟");
      return true;
    }
    if (_hasAny(cmd, ['أشوفك بعدين', 'اشوفك بعدين', 'يلا باي', 'في رعاية الله'])) {
      await _speak("في رعاية الله $userTitle، أنا هنا لو احتجتني 🌟");
      return true;
    }
    if (_hasAny(cmd, ['يلا', 'يالا', 'بسرعة', 'بسرعه', 'حالا', 'حالاً', 'دلوقتي'])) {
      await _speak("حاضر $userTitle، أنا في الخدمة 🏃");
      return true;
    }
    if (_hasAny(cmd, ['انت موجود', 'انتي موجودة', 'معايا', 'سامعني', 'سامعاني', 'سامعنى'])) {
      await _speak("أيوة $userTitle، أنا $_listenWord وأنا في الخدمة 👂");
      return true;
    }
    if (_hasAny(cmd, ['يلا نبدأ', 'نبدأ', 'هيا نبدأ', 'هيا بنا', 'يلا نشوف'])) {
      await _speak("تمام $userTitle، أنا $secTitle الشخصي بتاعك، قولي عايز إيه وأنا أنفذ");
      return true;
    }
    if (_hasAny(cmd, ['صحة', 'أيوة', 'ايوه', 'ايوة', 'نعم', 'اه', 'آه'])) {
      await _speak("في الخدمة $userTitle 👌");
      return true;
    }
    if (_hasAny(cmd, ['ممكن اسألك', 'ممكن أسألك', 'عندي سؤال', 'عندي استفسار'])) {
      await _speak("اتفضل $userTitle، أنا في الخدمة");
      return true;
    }
    if (_hasAny(cmd, ['عايز حاجه', 'عايز حاجة', 'عايزة حاجه', 'عايزة حاجة', 'عندي طلب'])) {
      await _speak("اتفضل $userTitle، قوللي وأنا أنفذ");
      return true;
    }
    if (_hasAny(cmd, ['ربنا يكرمك', 'ربنا يسعدك', 'ربنا يحفظك', 'ربنا يوفقك', 'ربنا يخليك ليا'])) {
      await _speak("وربنا يكرمك $userTitle، ده من فضل ربنا 💛");
      return true;
    }
    if (_hasAny(cmd, ['زهقان', 'زهقانة', 'مليت', 'حاسس بالوحدة'])) {
      await _speak("ما تزعلش $userTitle، أنا معاك. قولي نحجز موعد أو نلعب لعبة؟");
      return true;
    }
    if (_hasAny(cmd, ['جعان', 'جعانة', 'عطشان', 'عطشانة', 'عايز اكل', 'عايزة اكل'])) {
      await _speak("خد بالك من نفسك $userTitle، متسيبش نفسك من غير أكل 💚");
      return true;
    }
    if (_hasAny(cmd, ['نايم', 'نايمة', 'صاحي', 'صاحية', 'قايم من النوم'])) {
      if (cmd.contains('صاحي') || cmd.contains('صاحية') || cmd.contains('قايم')) {
        await _speak("صباح الخير $userTitle، دايماً نشيط 🌟");
      } else {
        await _speak("خد راحتك $userTitle، أنا هسيبك تنام 😴");
      }
      return true;
    }
    if (_hasAny(cmd, ['الجو حلو', 'الجو جميل', 'الجو حر', 'الجو برد'])) {
      await _speak("الجو دايماً حلو معاك $userTitle 🌤️");
      return true;
    }
    if (_hasAny(cmd, ['اهلا', 'أهلاً', 'مرحبا', 'هاي', 'hello', 'hi'])) {
      await _speak("أهلاً بيك $userTitle، نورت 🌟");
      return true;
    }
    if (_hasAny(cmd, ['مبروك', 'ألف مبروك', 'الف مبروك'])) {
      await _speak("الله يبارك فيك $userTitle، عقبال كل حاجة حلوة 🎉");
      return true;
    }
    if (_hasAny(cmd, ['سلامتك', 'الف سلامة', 'ألف سلامة'])) {
      await _speak("الله يسلمك $userTitle 💚");
      return true;
    }
    if (_hasAny(cmd, ['عندك شغل', 'عندك حاجة', 'مشغول', 'مشغولة'])) {
      await _speak("لأ $userTitle، فاضي ليك دايماً 👌");
      return true;
    }
    if (_hasAny(cmd, ['يلا ننام', 'خلاص هننام', 'هنام'])) {
      await _speak("تصبح على خير $userTitle، أحلام سعيدة 🌙");
      return true;
    }
    if (_hasAny(cmd, ['يلا نصحي', 'خلص نوم', 'قوم اصحي'])) {
      await _speak("صباح الخير $userTitle، يومك سعيد ☀️");
      return true;
    }
    if (_hasAny(cmd, ['كلمني', 'اتكلم', 'قولي حاجة', 'اشغلني'])) {
      await _speak("أنا معاك $userTitle، سامعك. قولي عايز تعمل إيه؟");
      return true;
    }
    if (_hasAny(cmd, ['نكته', 'نكتة', 'ضحكني', 'قولي نكته'])) {
      await _speak("مرة واحد راح للدكتور قاله يا دكتور أنا حاسس إني ستارة، قاله انتشر يا ابني 😂");
      return true;
    }
    if (_hasAny(cmd, ['الساعه كام', 'الساعة كام', 'الوقت ايه', 'الساعة كم'])) {
      final now = DateTime.now();
      final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final period = now.hour >= 12 ? 'مساءً' : 'صباحاً';
      await _speak("الساعة $hour $period $userTitle");
      return true;
    }
    if (_hasAny(cmd, ['التاريخ ايه', 'تاريخ اليوم', 'اليوم كام', 'انهاردة كام'])) {
      final now = DateTime.now();
      final date = DateFormat('dd MMMM yyyy', 'ar').format(now);
      await _speak("التاريخ اليوم $date $userTitle");
      return true;
    }
    if (_hasAny(cmd, ['مش محتاج تشكرني', 'بلاش شكر', 'مش عايز شكر'])) {
      await _speak("تمام $userTitle، تحت أمرك دايماً 💛");
      return true;
    }
    if (_hasAny(cmd, ['خلاص', 'كفاية', 'كفايه', 'بس كده'])) {
      await _speak("تمام $userTitle، تحت أمرك في أي وقت 👌");
      return true;
    }
    return false;
  }

  // ✅ دالة تحليل تاريخ اليوميات
  DateTime? _parseDiaryDate(String cmd) {
    final now = DateTime.now();

    if (cmd.contains('النهاردة') || cmd.contains('النهارده') || cmd.contains('اليوم')) return now;
    if (cmd.contains('اول امبارح') || cmd.contains('أول امبارح') || cmd.contains('قبل امبارح')) return now.subtract(const Duration(days: 2));
    if (cmd.contains('امبارح') || cmd.contains('امس') || cmd.contains('البارح')) return now.subtract(const Duration(days: 1));
    if (cmd.contains('بعد بكره') || cmd.contains('بعد بكرة') || cmd.contains('بعد غد')) return now.add(const Duration(days: 2));
    if (cmd.contains('بكره') || cmd.contains('بكرة') || cmd.contains('غدا') || cmd.contains('غداً')) return now.add(const Duration(days: 1));

    final dayKeywords = {
      DateTime.saturday: ['السبت', 'سبت'],
      DateTime.sunday: ['الاحد', 'الأحد', 'حد'],
      DateTime.monday: ['الاتنين', 'الاثنين', 'اتنين'],
      DateTime.tuesday: ['التلات', 'الثلاثاء', 'تلات'],
      DateTime.wednesday: ['الاربع', 'الأربعاء', 'اربع'],
      DateTime.thursday: ['الخميس', 'خميس'],
      DateTime.friday: ['الجمعه', 'الجمعة', 'جمعه'],
    };

    int? targetWeekday;
    for (final entry in dayKeywords.entries) {
      if (_hasAny(cmd, entry.value)) {
        targetWeekday = entry.key;
        break;
      }
    }

    if (targetWeekday != null) {
      final isLast = _hasAny(cmd, ['اللي فات', 'اللى فات', 'الماضي', 'اللي عدى', 'اللى عدى']);
      final isNext = _hasAny(cmd, ['الجاي', 'القادم', 'اللي جاي', 'اللى جاي']);
      if (isLast) {
        var diff = now.weekday - targetWeekday;
        if (diff <= 0) diff += 7;
        return now.subtract(Duration(days: diff));
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

    final digitsRegex = RegExp(r'\d{1,4}');
    final digits = digitsRegex.allMatches(cmd).map((m) => int.parse(m.group(0)!)).toList();
    if (digits.length >= 3) {
      int? year, month, day;
      for (final n in digits) {
        if (n >= 1900 && n <= 2100) year = n;
        else if (n >= 1 && n <= 12) month ??= n;
        else if (n >= 1 && n <= 31) day ??= n;
      }
      if (year != null && month != null && day != null) {
        try { return DateTime(year, month, day); } catch (_) {}
      }
    }

    final daysAgoMatch = RegExp(r'قبل\s*(\d+)\s*يوم').firstMatch(cmd);
    if (daysAgoMatch != null) {
      final days = int.tryParse(daysAgoMatch.group(1)!) ?? 0;
      return now.subtract(Duration(days: days));
    }

    return null;
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
    if (_hasAny(cmd, ['كل يوم', 'يومي', 'يوميا', 'يومياً', 'كل يوم الصبح', 'كل يوم بالليل', 'يوم بيوم', 'يوم بعد يوم', 'كل يومين', 'دائما', 'على طول', 'كل صباح', 'كل مساء', 'كل ليله', 'بشكل يومي'])) return 'يومي';
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

  Future<void> _processSmartVoiceCommand(String rawCommand) async {
    final userTitle = _userTitle;
    final cmd = _norm(rawCommand);
    final nameNorm = _norm(_secretaryName);
    bool isCalledByName = cmd.contains(nameNorm) || cmd.contains('يا سكرتير') || cmd.contains('يا سكرتيره') || cmd.contains('يا سكرتيرة');

    if (await _handleSocialReply(cmd)) return;

    // ═══ أوامر اليوميات ═══
    if ((cmd.contains('اقرا') || cmd.contains('اقرالي') || cmd.contains('اقرأيلي')) && cmd.contains('يوميات')) {
      final key = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final diary = _diaries[key];
      if (diary == null || diary.isEmpty) {
        await _speak("مفيش يوميات مكتوبة النهاردة $userTitle");
      } else {
        await _speak("يومياتك النهاردة: $diary");
      }
      return;
    }
    if (cmd.contains('اكتب') && cmd.contains('يوميات')) {
      if (mounted) _openDiaryPage(DateTime.now());
      await _speak("اتفضل $userTitle، اكتب يومياتك");
      return;
    }
    if (cmd.contains('امسح') && cmd.contains('يوميات')) {
      final key = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (_diaries.containsKey(key)) {
        setState(() => _diaries.remove(key));
        _saveData();
        await _speak("تم مسح يوميات النهاردة $userTitle");
      } else {
        await _speak("مفيش يوميات النهاردة $userTitle");
      }
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

    if (_hasAny(cmd, alarmKeywords)) {
      await _createAlarmFromVoice(rawCommand, cmd);
      return;
    }

    final editKeywords = [
      "عدل", "عدلي", "عدللي", "عدليلي", "تعدل", "تعدلي",
      "تعديل", "تعديلي", "أعدل", "اعدل",
      "غير", "غيري", "غيرلي", "غيريلي", "تغير", "تغيري",
      "غيّر", "غيّري", "تغيير", "تغييري",
      "بدل", "بدلي", "بدللي", "بدليلي", "تبدل", "تبدلي",
      "حرك", "حركي", "أخر", "أخري",
    ];

    final deleteKeywords = [
      "امسح", "امسحي", "امسحلي", "امسحيلي", "أمسح", "أمسحي",
      "مسح", "مسحي", "مسحلي", "مسحيلي",
      "احذف", "احذفي", "احذفلي", "احذفيلي", "أحذف", "أحذفي",
      "حذف", "حذفي", "حذفلي", "حذفيلي",
      "شيل", "شيلي", "شيللي", "شيليلي", "أشيل",
      "الغي", "الغى", "ألغي", "ألغى", "الغيلي", "ألغيلي",
      "إلغاء", "إلغى", "كانسل", "كنسل", "كنسلي", "كانسلي",
      "وقف المنبه", "وقفي المنبه", "اوقف المنبه", "أوقف المنبه",
      "اقفل المنبه", "اقفلي المنبه", "الغي المنبه", "ألغي المنبه",
    ];

    if (_hasAny(cmd, deleteKeywords)) {
      await _deleteTaskByVoice(cmd);
      return;
    }

    if (_hasAny(cmd, editKeywords)) {
      await _editTaskByVoice(cmd);
      return;
    }

    final prayerKeywords = ["صلوات", "صلاة", "صلاه", "الصلاة", "مواقيت", "اذان", "أذان",
      "الفجر", "الظهر", "العصر", "المغرب", "العشاء"];

    final diaryKeywords = ["يوميات", "يومياتي", "اليوميات", "مفكرة", "مفكرتي", "المفكرة",
      "مذكرة", "مذكرتي", "تدوين", "خواطر", "اكتبلي", "اكتبيلي"];

    final eventKeywords = ["مناسبات", "مناسباتي", "المناسبات", "مناسبة", "مناسبه",
      "عيد", "العيد", "أعياد", "اعياد", "ذكرى", "الذكرى", "احتفال", "حفلة"];

    final openRecorderKeywords = [
      "افتح المسجل", "افتح مسجل", "افتحلي المسجل", "افتحي المسجل", "افتحيلى المسجل",
      "المسجل", "مسجل", "المسجل الصوتي",
      "سجل صوت", "سجل صوتي", "سجلي صوت", "سجلي صوتي",
      "التسجيلات", "تسجيلات", "تسجيلاتي",
      "صوتيات", "الصوتيات",
      "المذكرات الصوتيه", "مذكرات صوتيه", "المذكرات الصوتية",
    ];

    final startRecordKeywords = [
      "ابدأ تسجيل", "ابدأ التسجيل",
      "ابدئي تسجيل", "ابدئي التسجيل",
      "ابدا تسجيل", "ابدا التسجيل",
      "سجل دلوقتي", "سجل حالا", "سجل حالاً",
      "سجلي دلوقتي", "سجلي حالا", "سجلي حالاً",
      "سجللي دلوقتي", "سجليلي دلوقتي", "سجللي حالا", "سجليلي حالا",
      "ابدأ دلوقتي", "ابدئي دلوقتي",
      "ابدأ سجل", "ابدئي سجل",
      "عايز أسجل", "عايز اسجل", "عاوز أسجل", "عاوز اسجل",
      "عايزة أسجل", "عايزة اسجل", "عاوزة أسجل", "عاوزة اسجل",
      "شغل التسجيل", "شغلي التسجيل", "شغل المسجل", "شغلي المسجل",
      "ابدأ التسجيل دلوقتي", "ابدئي التسجيل دلوقتي",
      "سجل يلا", "سجلي يلا", "سجل بسرعة", "سجلي بسرعة",
    ];

    final stopRecordKeywords = [
      "وقف تسجيل", "وقف التسجيل",
      "وقفي تسجيل", "وقفي التسجيل",
      "اوقف تسجيل", "اوقف التسجيل",
      "أوقف تسجيل", "أوقف التسجيل",
      "وقفت تسجيل", "وقفت التسجيل",
      "خلاص وقف تسجيل", "خلاص وقف التسجيل",
      "خلاص وقفي تسجيل", "خلاص وقفي التسجيل",
      "خلاص وقف", "خلاص وقفي",
      "خلاص اوقف", "خلاص أوقف",
      "خلاص ايقاف", "خلاص إيقاف",
      "خلاص كفاية", "خلاص كفايه",
      "خلاص بلاها", "خلاص بلاش",
      "خلاص انتهي", "خلاص انتهى",
      "خلاص اقفل التسجيل", "خلاص اقفلي التسجيل",
      "خلص تسجيل", "خلص التسجيل",
      "خلصي تسجيل", "خلصي التسجيل",
      "خلصت تسجيل", "خلصت التسجيل",
      "خلص خلاص", "خلصي خلاص",
      "بطل تسجيل", "بطل التسجيل",
      "بطلي تسجيل", "بطلي التسجيل",
      "بطل بقي", "بطلي بقي",
      "انهي التسجيل", "انهي تسجيل",
      "أنهي التسجيل", "أنهي تسجيل",
      "اقفل التسجيل", "اقفلي التسجيل",
      "اقفل تسجيل", "اقفلي تسجيل",
      "قفل التسجيل", "قفلي التسجيل",
      "كفاية تسجيل", "كفاية التسجيل",
      "كفايه تسجيل", "كفايه التسجيل",
      "كفاية كده", "كفايه كده",
      "كفاية خلاص", "كفايه خلاص",
      "بس كده", "بس خلاص", "بس كفاية", "بس كفايه",
      "كده كفاية", "كده كفايه",
      "اوقف", "أوقف", "ايقاف", "إيقاف",
      "ستوب", "stop",
      "سيب التسجيل", "سيبي التسجيل",
      "متسجلش", "ماتسجلش", "متسجليش", "ماتسجليش",
      "مش عايز اسجل", "مش عاوز اسجل",
      "مش عايزة اسجل", "مش عاوزة اسجل",
    ];

    if (_hasAny(cmd, prayerKeywords)) {
      setState(() => _currentIndex = 2);
      await _speak("تم الانتقال لمواقيت الصلاة $userTitle.");
      return;
    } else if (_hasAny(cmd, diaryKeywords)) {
      setState(() => _currentIndex = 1);
      await Future.delayed(const Duration(milliseconds: 300));
      final requestedDate = _parseDiaryDate(cmd);
      if (requestedDate != null) {
        if (mounted) _openDiaryPage(requestedDate);
        final dayName = DateFormat('EEEE، dd MMMM yyyy', 'ar').format(requestedDate);
        await _speak("تم فتح يومية $dayName $userTitle");
      } else {
        if (mounted) _openDiaryPage(DateTime.now());
        await _speak("تم فتح يومية النهاردة $userTitle");
      }
      return;
    } else if (_hasAny(cmd, eventKeywords)) {
      setState(() => _currentIndex = 3);
      await _speak("تم الانتقال للمناسبات السنوية $userTitle.");
      return;
    } else if (_hasAny(cmd, stopRecordKeywords)) {
      if (_isRecording) {
        await _stopRecording();
        await _speak("تم إيقاف التسجيل $userTitle.");
      } else {
        await _speak("مفيش تسجيل شغال دلوقتي $userTitle.");
      }
      return;
    } else if (_hasAny(cmd, startRecordKeywords)) {
      setState(() => _currentIndex = 4);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_isRecording) {
        await _startRecording();
        await _speak("بدأت التسجيل $userTitle.");
      } else {
        await _speak("التسجيل شغال بالفعل $userTitle.");
      }
      return;
    } else if (_hasAny(cmd, openRecorderKeywords)) {
      setState(() => _currentIndex = 4);
      await _speak("تم فتح قسم المسجل $userTitle.");
      return;
    }

    if (isCalledByName) {
      await _speak("نعم $userTitle! أنا أسمعك.");
    } else {
      await _speak("عذراً $userTitle، لم أفهم الأمر.");
    }
  }

  Future<void> _deleteTaskByVoice(String cmd) async {
    final userTitle = _userTitle;
    final nameNorm = _norm(_secretaryName);
    String searchTerm = cmd;
    final deleteWords = ['امسح', 'امسحي', 'احذف', 'احذفي', 'شيل', 'شيلي', 'الغي', 'الغى', 'الغيلي', 'مسح', 'حذف', 'كانسل', 'كنسل', 'المنبه', 'منبه'];
    for (final w in deleteWords) {
      searchTerm = searchTerm.replaceAll(_norm(w), '');
    }
    searchTerm = searchTerm.replaceAll(nameNorm, '').trim();

    if (searchTerm.isEmpty) {
      await _speak("قوللي أمسح أي موعد $userTitle");
      return;
    }

    final matches = _tasks.where((t) {
      final taskName = _norm(t['task'].toString());
      return taskName.contains(searchTerm) || searchTerm.contains(taskName);
    }).toList();

    if (matches.isEmpty) {
      await _speak("مفيش موعد بالاسم ده $userTitle");
      return;
    }

    if (matches.length == 1) {
      final task = matches.first;
      setState(() => _tasks.remove(task));
      _saveData();
      await _speak("تم مسح موعد ${task['task']} $userTitle");
    } else {
      await _speak("لقيت ${matches.length} مواعيد بالاسم ده $userTitle، حدد أكتر");
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
      await _speak("قوللي أعدل أي موعد $userTitle");
      return;
    }

    final matches = _tasks.where((t) {
      final taskName = _norm(t['task'].toString());
      return taskName.contains(searchTerm) || searchTerm.contains(taskName);
    }).toList();

    if (matches.isEmpty) {
      await _speak("مفيش موعد بالاسم ده $userTitle");
      return;
    }

    if (matches.length == 1) {
      final index = _tasks.indexOf(matches.first);
      if (mounted) {
        _editTaskDialog(index);
        await _speak("هيظهرلك الموعد $userTitle، عدل زي ما تحب");
      }
    } else {
      await _speak("لقيت ${matches.length} مواعيد $userTitle، حدد أكتر");
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
      await _speak("في أي ساعة $userTitle؟");
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
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    final repeatType = _parseRepeatType(cmd);
    final intervalType = _parseIntervalType(cmd);
    final customDays = _parseCustomDays(cmd);

    final strip = <String>{
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
    };
    final nameNorm = _norm(_secretaryName);
    final kept = <String>[];
    bool hourTokenRemoved = false;
    for (final t in rawCommand.split(RegExp(r'\s+'))) {
      final n = _norm(t);
      if (n.isEmpty) continue;
      if (strip.contains(n) || n == nameNorm) continue;
      if (afterTomorrow && n == 'بعد') continue;
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

    setState(() {
      _selectedDate = scheduled;
      _currentIndex = 0;
      _tasks.add({
        'date': formattedDate, 'task': cleanTitle, 'time': formattedTime,
        'alarm': true, 'scheduled': scheduled.toIso8601String(),
        'repeat': repeatType, 'repeatInterval': intervalType, 'customDays': customDays,
      });
    });
    _saveData();
    _scheduleContinuousAlarm(cleanTitle, scheduled, repeatType, intervalType, customDays);

    final h12 = scheduled.hour % 12 == 0 ? 12 : scheduled.hour % 12;
    final minuteText = scheduled.minute > 0 ? ' و ${scheduled.minute} دقيقة' : '';
    final periodText = scheduled.hour >= 12 ? 'مساءً' : 'صباحاً';
    String repeatText = '';
    if (repeatType != 'مرة واحدة') {
      repeatText = '، $repeatType';
      if (repeatType == 'مخصص' && customDays.isNotEmpty) {
        repeatText += ' (${customDays.join("، ")})';
      }
    }
    String intervalText = '';
    if (intervalType != 'بدون تنبيه') {
      intervalText = '، والتنبيه المستمر $intervalType';
    }
    await _speak("تم التنفيذ $userTitle! تم تسجيل: $cleanTitle، الساعة $h12$minuteText $periodText$repeatText$intervalText.");
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

  void _scheduleContinuousAlarm(String taskTitle, DateTime scheduledDateTime, String repeat, String interval, List<String> customDays) {
    Duration difference = scheduledDateTime.difference(DateTime.now());
    if (difference.isNegative) return;
    _scheduleBackgroundNotification(
      taskTitle,
      scheduledDateTime,
      repeat: repeat,
      interval: interval,
      customDays: customDays,
    );
    late final Timer timer;
    timer = Timer(difference, () {
      _activeTimers.remove(timer);
      if (mounted) _startAlarmLoop(taskTitle, repeat, interval, customDays, scheduledDateTime);
    });
    _activeTimers.add(timer);
  }

  void _rescheduleRepeating(String taskTitle, String repeat, String interval, List<String> customDays, DateTime lastScheduled) {
    DateTime next;
    if (repeat == 'يومي') {
      next = lastScheduled.add(const Duration(days: 1));
    } else if (repeat == 'أسبوعي') {
      next = lastScheduled.add(const Duration(days: 7));
    } else if (repeat == 'شهري') {
      next = DateTime(lastScheduled.year, lastScheduled.month + 1, lastScheduled.day, lastScheduled.hour, lastScheduled.minute);
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
    _scheduleContinuousAlarm(taskTitle, next, repeat, interval, customDays);
  }

  // ✅ v5 + audioAttributesUsage
  Future<void> _scheduleBackgroundNotification(
    String taskTitle,
    DateTime scheduledDateTime, {
    String repeat = 'مرة واحدة',
    String interval = 'بدون تنبيه',
    List<String> customDays = const [],
  }) async {
    final tzTime = tz.TZDateTime.from(scheduledDateTime, tz.local);
    const androidDetails = AndroidNotificationDetails(
      'secretary_alarm_v5',
      'منبه السكرتير v5',
      channelDescription: 'تنبيهات المواعيد',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      autoCancel: false,
      ongoing: true,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'cancel_alarm',
          'إلغاء',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    await _notifications.zonedSchedule(
      taskTitle.hashCode + 1000,
      'تنبيه هام!',
      'حان الآن موعد: $taskTitle',
      tzTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_alarm', json.encode({
      'title': taskTitle,
      'scheduledMillis': scheduledDateTime.millisecondsSinceEpoch,
      'repeat': repeat,
      'interval': interval,
      'customDays': customDays,
    }));
  }

  // ✅ زر خلاص يمسح الموعد لو مرة واحدة
  void _startAlarmLoop(String taskTitle, String repeat, String interval, List<String> customDays, DateTime scheduled) {
    final userTitle = _userTitle;
    WakelockPlus.enable();
    HapticFeedback.vibrate();
    void speakAlert() {
      _speak("حان الآن موعد: $taskTitle");
      HapticFeedback.vibrate();
    }

    if (interval != 'بدون تنبيه') {
      speakAlert();
    }

    int secs = _getIntervalSeconds(interval);
    Timer? loopTimer;
    if (secs > 0 && interval != 'مرة واحدة') {
      loopTimer = Timer.periodic(Duration(seconds: secs), (_) => speakAlert());
      _activeTimers.add(loopTimer);
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2A4A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.alarm_on, color: Color(0xFFC5A059), size: 30), SizedBox(width: 10), Text('تنبيه هام!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
        content: Text('$userTitle، حان الآن موعد:\n"$taskTitle"', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC5A059)),
            onPressed: () {
              loopTimer?.cancel();
              if (loopTimer != null) _activeTimers.remove(loopTimer);
              _tts.stop();
              WakelockPlus.disable();
              Navigator.pop(ctx);

              // ✅ لو مرة واحدة → امسح الموعد
              if (repeat == 'مرة واحدة') {
                final idx = _tasks.indexWhere((t) => t['task'] == taskTitle);
                if (idx != -1) {
                  setState(() => _tasks.removeAt(idx));
                  _saveData();
                }
                SharedPreferences.getInstance().then((prefs) {
                  prefs.remove('pending_alarm');
                });
              } else {
                _rescheduleRepeating(taskTitle, repeat, interval, customDays, scheduled);
              }
            },
            child: const Text('خلاص (إيقاف)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
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
      return {'fajr': format.format(prayerTimes.fajr), 'sunrise': format.format(prayerTimes.sunrise), 'dhuhr': format.format(prayerTimes.dhuhr), 'asr': format.format(prayerTimes.asr), 'maghrib': format.format(prayerTimes.maghrib), 'isha': format.format(prayerTimes.isha)};
    } catch (e) {
      final format = DateFormat('hh:mm a', 'ar');
      final now = DateTime.now();
      return {'fajr': format.format(DateTime(now.year, now.month, now.day, 4, 25)), 'sunrise': format.format(DateTime(now.year, now.month, now.day, 5, 52)), 'dhuhr': format.format(DateTime(now.year, now.month, now.day, 11, 45)), 'asr': format.format(DateTime(now.year, now.month, now.day, 15, 8)), 'maghrib': format.format(DateTime(now.year, now.month, now.day, 17, 38)), 'isha': format.format(DateTime(now.year, now.month, now.day, 18, 55))};
    }
  }
    // ═══════════════════════════════════════
  // Events Reminders
  // ═══════════════════════════════════════
  Future<void> _scheduleEventReminder(Map<String, dynamic> event) async {
    try {
      final eventDate = DateTime.parse(event['eventDate'].toString());
      final reminderHour = event['reminderHour'] ?? _settings.defaultReminderHour;
      final reminderMinute = event['reminderMinute'] ?? _settings.defaultReminderMinute;
      final advanceDays = _getAdvanceDays(event['advanceReminder'] ?? 'قبلها بيوم');
      final interval = event['repeatInterval'] ?? 'مرة واحدة';
      final now = DateTime.now();

      final eventThisYear = DateTime(now.year, eventDate.month, eventDate.day);
      final reminderDate = eventThisYear.subtract(Duration(days: advanceDays));
      final reminderDateTime = DateTime(reminderDate.year, reminderDate.month, reminderDate.day, reminderHour, reminderMinute);

      if (reminderDateTime.isBefore(now)) return;

      await _scheduleEventNotification(event, reminderDateTime, interval);
      final diff = reminderDateTime.difference(now);

      late final Timer timer;
      timer = Timer(diff, () {
        _activeTimers.remove(timer);
        if (mounted) _showEventReminder(event['title'].toString(), event['detail'].toString(), interval);
      });
      _activeTimers.add(timer);
    } catch (_) {}
  }

  Future<void> _scheduleEventNotification(Map<String, dynamic> event, DateTime fireTime, String interval) async {
    try {
      final eventId = event['title'].toString().hashCode + event['eventDate'].toString().hashCode;
      final tzTime = tz.TZDateTime.from(fireTime, tz.local);

      const androidDetails = AndroidNotificationDetails(
        'event_channel_v1', 'تنبيهات المناسبات',
        channelDescription: 'تنبيهات المناسبات السنوية',
        importance: Importance.max, priority: Priority.max,
        playSound: true, enableVibration: true,
        category: AndroidNotificationCategory.alarm,
        autoCancel: false, ongoing: true, fullScreenIntent: true,
        visibility: NotificationVisibility.public,
      );

      await _notifications.zonedSchedule(
        eventId, '🎉 تذكير بمناسبة', 'قربت مناسبة: ${event['title']}',
        tzTime, const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_event_announce', json.encode({
        'title': event['title'], 'detail': event['detail'],
        'interval': interval, 'scheduledMillis': fireTime.millisecondsSinceEpoch,
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

  Future<void> _showEventReminder(String title, String detail, String interval) async {
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
      _speak("تنبيه: قربت مناسبة $title. $detail");
      HapticFeedback.vibrate();
    }

    if (interval != 'بدون تنبيه') speakAlert();

    _eventRepeatTimer?.cancel();
    int secs = _getIntervalSeconds(interval);
    if (secs > 0 && interval != 'مرة واحدة') {
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
        content: Text('قربت مناسبة: $title\n$detail', style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC5A059)),
            onPressed: () {
              _eventRepeatTimer?.cancel();
              _tts.stop();
              WakelockPlus.disable();
              _eventAnnouncing = false;
              _eventDialogShowing = false;
              Navigator.pop(ctx);
            },
            child: const Text('تمام', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _deleteTask(int index) {
    setState(() => _tasks.removeAt(index));
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الموعد')));
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
          onSave: (hour, minute, voiceLevel, greeting, adhan, ttsVol, showLock, shakeBg, voiceGender, defaultInterval) async {
            setState(() {
              _settings.defaultReminderHour = hour;
              _settings.defaultReminderMinute = minute;
              _settings.voiceLevel = voiceLevel;
              _settings.greetingEnabled = greeting;
              _settings.adhanAlertEnabled = adhan;
              _ttsVolume = ttsVol;
              _settings.showAboveLockScreen = showLock;
              _settings.shakeInBackgroundEnabled = shakeBg;
              _settings.voiceGender = voiceGender;
              _settings.defaultInterval = defaultInterval;
            });
            await _saveSettings();
            await _scheduleAdhan30Days();
            try {
              if (showLock) {
                await _lockScreenChannel.invokeMethod('enableShowWhenLocked');
              } else {
                await _lockScreenChannel.invokeMethod('disableShowWhenLocked');
              }
            } catch (_) {}
          },
          onSaveSecretary: (name, voiceGender) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('secretary_name', name);
            await prefs.setString('voice_gender', voiceGender);
            setState(() {
              _secretaryName = name;
              _settings.voiceGender = voiceGender;
            });
          },
        ),
      ),
    ).then((_) {
      _configureVoice(skipGreeting: true);
    });
  }

  void _addNewTaskDialog() {
    TextEditingController taskCtrl = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    String selectedRepeat = 'مرة واحدة';
    String selectedInterval = _settings.defaultInterval;
    List<String> selectedDays = [];
    final List<String> repeatOptions = ['مرة واحدة', 'يومي', 'أسبوعي', 'شهري', 'مخصص'];
    final List<String> intervalOptions = ['بدون تنبيه', 'مرة واحدة', 'كل 10 ثواني', 'كل 20 ثانية', 'كل 30 ثانية', 'كل دقيقة', 'كل دقيقتين', 'كل 3 دقايق', 'كل 5 دقايق', 'كل 10 دقايق'];
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
                  const Divider(),
                  const Align(alignment: Alignment.centerRight, child: Text('التكرار:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(value: selectedRepeat, decoration: const InputDecoration(border: OutlineInputBorder()), items: repeatOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (val) => setStateSB(() => selectedRepeat = val ?? 'مرة واحدة')),
                  if (selectedRepeat == 'مخصص') ...[
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerRight, child: Text('اختر الأيام:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    const SizedBox(height: 5),
                    Wrap(spacing: 5, runSpacing: 5, children: _weekDays.map((day) {
                      final isSelected = selectedDays.contains(day);
                      return FilterChip(label: Text(day, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)), selected: isSelected, selectedColor: const Color(0xFF1B2A4A), onSelected: (v) => setStateSB(() { if (v) selectedDays.add(day); else selectedDays.remove(day); }));
                    }).toList()),
                  ],
                ],
                const Divider(),
                const Align(alignment: Alignment.centerRight, child: Text('التنبيه المستمر:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(value: selectedInterval, decoration: const InputDecoration(border: OutlineInputBorder()), items: intervalOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (val) => setStateSB(() => selectedInterval = val ?? _settings.defaultInterval)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () {
                if (taskCtrl.text.isNotEmpty) {
                  final scheduledDateTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, selectedTime.hour, selectedTime.minute);
                  setState(() {
                    _tasks.add({'date': DateFormat('yyyy-MM-dd').format(_selectedDate), 'task': taskCtrl.text, 'time': selectedInterval == 'بدون تنبيه' ? 'بدون تنبيه' : selectedTime.format(context), 'alarm': selectedInterval != 'بدون تنبيه', 'scheduled': scheduledDateTime.toIso8601String(), 'repeat': selectedRepeat, 'repeatInterval': selectedInterval, 'customDays': selectedDays});
                  });
                  _saveData();
                  if (selectedInterval != 'بدون تنبيه') _scheduleContinuousAlarm(taskCtrl.text, scheduledDateTime, selectedRepeat, selectedInterval, selectedDays);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _editTaskDialog(int index) {
    final task = _tasks[index];
    TextEditingController taskCtrl = TextEditingController(text: task['task'].toString());
    TimeOfDay selectedTime = TimeOfDay.now();
    try {
      final t = DateFormat('hh:mm a', 'ar').parse(task['time'].toString());
      selectedTime = TimeOfDay(hour: t.hour, minute: t.minute);
    } catch (_) {}
    String selectedRepeat = task['repeat'] ?? 'مرة واحدة';
    String selectedInterval = task['repeatInterval'] ?? _settings.defaultInterval;
    List<String> selectedDays = List<String>.from(task['customDays'] ?? []);
    final List<String> repeatOptions = ['مرة واحدة', 'يومي', 'أسبوعي', 'شهري', 'مخصص'];
    final List<String> intervalOptions = ['بدون تنبيه', 'مرة واحدة', 'كل 10 ثواني', 'كل 20 ثانية', 'كل 30 ثانية', 'كل دقيقة', 'كل دقيقتين', 'كل 3 دقايق', 'كل 5 دقايق', 'كل 10 دقايق'];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('تعديل الموعد', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  const Divider(),
                  const Align(alignment: Alignment.centerRight, child: Text('التكرار:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(value: selectedRepeat, decoration: const InputDecoration(border: OutlineInputBorder()), items: repeatOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (val) => setStateSB(() => selectedRepeat = val ?? 'مرة واحدة')),
                  if (selectedRepeat == 'مخصص') ...[
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerRight, child: Text('اختر الأيام:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    const SizedBox(height: 5),
                    Wrap(spacing: 5, runSpacing: 5, children: _weekDays.map((day) {
                      final isSelected = selectedDays.contains(day);
                      return FilterChip(label: Text(day, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)), selected: isSelected, selectedColor: const Color(0xFF1B2A4A), onSelected: (v) => setStateSB(() { if (v) selectedDays.add(day); else selectedDays.remove(day); }));
                    }).toList()),
                  ],
                ],
                const Divider(),
                const Align(alignment: Alignment.centerRight, child: Text('التنبيه المستمر:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(value: selectedInterval, decoration: const InputDecoration(border: OutlineInputBorder()), items: intervalOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (val) => setStateSB(() => selectedInterval = val ?? _settings.defaultInterval)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () {
                if (taskCtrl.text.isNotEmpty) {
                  final scheduledDateTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, selectedTime.hour, selectedTime.minute);
                  setState(() {
                    _tasks[index] = {'date': task['date'], 'task': taskCtrl.text, 'time': selectedInterval == 'بدون تنبيه' ? 'بدون تنبيه' : selectedTime.format(context), 'alarm': selectedInterval != 'بدون تنبيه', 'scheduled': scheduledDateTime.toIso8601String(), 'repeat': selectedRepeat, 'repeatInterval': selectedInterval, 'customDays': selectedDays};
                  });
                  _saveData();
                  if (selectedInterval != 'بدون تنبيه') _scheduleContinuousAlarm(taskCtrl.text, scheduledDateTime, selectedRepeat, selectedInterval, selectedDays);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _addSpecialEventDialog() {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController detailCtrl = TextEditingController();
    String selectedAdvanceReminder = 'قبلها بيوم';
    String selectedInterval = 'مرة واحدة';
    DateTime selectedEventDate = DateTime.now();
    TimeOfDay reminderTime = TimeOfDay(hour: _settings.defaultReminderHour, minute: _settings.defaultReminderMinute);
    final List<String> reminderOptions = ['في نفس اليوم', 'قبلها بيوم', 'قبلها بـ 3 أيام', 'قبلها بأسبوع', 'قبلها بـ 10 أيام', 'قبلها بشهر'];
    final List<String> intervalOptions = ['بدون تنبيه', 'مرة واحدة', 'كل 10 ثواني', 'كل 20 ثانية', 'كل 30 ثانية', 'كل دقيقة', 'كل دقيقتين', 'كل 3 دقايق', 'كل 5 دقايق', 'كل 10 دقايق'];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('إضافة مناسبة', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'اسم المناسبة')),
                const SizedBox(height: 10),
                TextField(controller: detailCtrl, decoration: const InputDecoration(labelText: 'التفاصيل/الاسم')),
                const SizedBox(height: 15),
                ListTile(contentPadding: EdgeInsets.zero, title: Text('التاريخ: ${DateFormat('yyyy/MM/dd').format(selectedEventDate)}'), trailing: const Icon(Icons.calendar_today, color: Color(0xFF1B2A4A)), onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: selectedEventDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (picked != null) setStateSB(() => selectedEventDate = picked);
                }),
                ListTile(contentPadding: EdgeInsets.zero, title: Text('وقت التذكير: ${reminderTime.format(context)}'), trailing: const Icon(Icons.access_time, color: Color(0xFF1B2A4A)), onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: reminderTime);
                  if (picked != null) setStateSB(() => reminderTime = picked);
                }),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(value: selectedAdvanceReminder, decoration: const InputDecoration(labelText: 'التذكير المسبق', border: OutlineInputBorder()), items: reminderOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(), onChanged: (val) => setStateSB(() => selectedAdvanceReminder = val ?? selectedAdvanceReminder)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(value: selectedInterval, decoration: const InputDecoration(labelText: 'التنبيه المستمر', border: OutlineInputBorder()), items: intervalOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(), onChanged: (val) => setStateSB(() => selectedInterval = val ?? 'مرة واحدة')),
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
                    'advanceReminder': selectedAdvanceReminder,
                    'eventDate': selectedEventDate.toIso8601String(),
                    'reminderHour': reminderTime.hour,
                    'reminderMinute': reminderTime.minute,
                    'repeatInterval': selectedInterval,
                  };
                  setState(() => _specialEvents.add(newEvent));
                  _saveData();
                  _scheduleEventReminder(newEvent);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _editSpecialEventDialog(int index) {
    final event = _specialEvents[index];
    TextEditingController titleCtrl = TextEditingController(text: event['title'].toString());
    TextEditingController detailCtrl = TextEditingController(text: event['detail'].toString());
    String selectedAdvanceReminder = event['advanceReminder'] ?? 'قبلها بيوم';
    String selectedInterval = event['repeatInterval'] ?? 'مرة واحدة';
    DateTime selectedEventDate = DateTime.now();
    try {
      selectedEventDate = DateTime.parse(event['eventDate'].toString());
    } catch (_) {}
    TimeOfDay reminderTime = TimeOfDay(
      hour: event['reminderHour'] ?? _settings.defaultReminderHour,
      minute: event['reminderMinute'] ?? _settings.defaultReminderMinute,
    );
    final List<String> reminderOptions = ['في نفس اليوم', 'قبلها بيوم', 'قبلها بـ 3 أيام', 'قبلها بأسبوع', 'قبلها بـ 10 أيام', 'قبلها بشهر'];
    final List<String> intervalOptions = ['بدون تنبيه', 'مرة واحدة', 'كل 10 ثواني', 'كل 20 ثانية', 'كل 30 ثانية', 'كل دقيقة', 'كل دقيقتين', 'كل 3 دقايق', 'كل 5 دقايق', 'كل 10 دقايق'];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('تعديل المناسبة', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'اسم المناسبة')),
                const SizedBox(height: 10),
                TextField(controller: detailCtrl, decoration: const InputDecoration(labelText: 'التفاصيل/الاسم')),
                const SizedBox(height: 15),
                ListTile(contentPadding: EdgeInsets.zero, title: Text('التاريخ: ${DateFormat('yyyy/MM/dd').format(selectedEventDate)}'), trailing: const Icon(Icons.calendar_today, color: Color(0xFF1B2A4A)), onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: selectedEventDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (picked != null) setStateSB(() => selectedEventDate = picked);
                }),
                ListTile(contentPadding: EdgeInsets.zero, title: Text('وقت التذكير: ${reminderTime.format(context)}'), trailing: const Icon(Icons.access_time, color: Color(0xFF1B2A4A)), onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: reminderTime);
                  if (picked != null) setStateSB(() => reminderTime = picked);
                }),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(value: selectedAdvanceReminder, decoration: const InputDecoration(labelText: 'التذكير المسبق', border: OutlineInputBorder()), items: reminderOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(), onChanged: (val) => setStateSB(() => selectedAdvanceReminder = val ?? selectedAdvanceReminder)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(value: selectedInterval, decoration: const InputDecoration(labelText: 'التنبيه المستمر', border: OutlineInputBorder()), items: intervalOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(), onChanged: (val) => setStateSB(() => selectedInterval = val ?? 'مرة واحدة')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A)),
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  final updatedEvent = {
                    'title': titleCtrl.text,
                    'detail': detailCtrl.text.isEmpty ? 'مناسبة سنوية' : detailCtrl.text,
                    'advanceReminder': selectedAdvanceReminder,
                    'eventDate': selectedEventDate.toIso8601String(),
                    'reminderHour': reminderTime.hour,
                    'reminderMinute': reminderTime.minute,
                    'repeatInterval': selectedInterval,
                  };
                  setState(() => _specialEvents[index] = updatedEvent);
                  _saveData();
                  _scheduleEventReminder(updatedEvent);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _openDiaryPage(DateTime date) {
    String key = DateFormat('yyyy-MM-dd').format(date);
    String dayName = DateFormat('EEEE', 'ar').format(date);
    String fullDate = DateFormat('dd MMMM yyyy', 'ar').format(date);
    TextEditingController diaryCtrl = TextEditingController(text: _diaries[key] ?? '');
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: const Color(0xFF1B2A4A), foregroundColor: Colors.white, title: const Text('تدوين اليوميات'), actions: [
        IconButton(icon: const Icon(Icons.check, color: Color(0xFFC5A059), size: 28), onPressed: () {
          setState(() => _diaries[key] = diaryCtrl.text);
          _saveData();
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ!')));
        })
      ]),
      body: Padding(padding: const EdgeInsets.all(20.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFFF4F6F9), borderRadius: BorderRadius.circular(12), border: const Border(right: BorderSide(color: Color(0xFFC5A059), width: 4))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('اليوم: $dayName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
          const SizedBox(height: 4),
          Text('التاريخ: $fullDate', style: const TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w600)),
        ])),
        const SizedBox(height: 20),
        Expanded(child: TextField(controller: diaryCtrl, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top, style: const TextStyle(fontSize: 16, height: 1.6), decoration: const InputDecoration(hintText: 'اكتب يومياتك هنا...', border: InputBorder.none))),
      ])),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [_buildCalendarAndTasksTab(), _buildDiariesTab(), _buildPrayerTimesTab(), _buildSpecialEventsTab(), _buildRecorderTab()];

    Widget? fab;
    if (_isRecording) {
      fab = FloatingActionButton.extended(
        onPressed: _stopRecording,
        backgroundColor: Colors.red,
        icon: const Icon(Icons.stop, color: Colors.white),
        label: Text(
          'إيقاف التسجيل (${_formatDuration(_recordingDuration)})',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      );
    } else if (_currentIndex == 0) {
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
          CircleAvatar(radius: 22, backgroundColor: const Color(0xFFC5A059), child: ClipOval(child: Image.asset(_getSecretaryImage(_secretaryName, _settings.voiceGender), width: 44, height: 44, fit: BoxFit.cover, alignment: const Alignment(0, -0.3), errorBuilder: (c, e, s) => const Icon(Icons.face_3, color: Colors.white)))),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$_secTitle: $_secretaryName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Text('هز الهاتف للتحدث', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.record_voice_over, color: Color(0xFFC5A059)),
            tooltip: 'اختيار الصوت',
            onPressed: (_isListening || _isRecording) ? null : _openVoicePicker,
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
        onTap: (index) => setState(() => _currentIndex = index),
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

  Widget _buildCalendarAndTasksTab() {
    String formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String currentTime = DateFormat('hh:mm a', 'ar').format(DateTime.now());
    var dayTasks = _tasks.where((t) => t['date'] == formattedDate).toList();
    String userTitle = _userTitle;
    return SingleChildScrollView(
      child: Column(children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF2C3E50)], begin: Alignment.topRight, end: Alignment.bottomLeft), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Row(children: [
            Container(width: 70, height: 70, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFC5A059), width: 2), image: DecorationImage(image: AssetImage(_getSecretaryImage(_secretaryName, _settings.voiceGender)), fit: BoxFit.cover, alignment: const Alignment(0, -0.3)))),
            const SizedBox(width: 15),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مرحباً بك $userTitle! 👋', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              Text('الوقت: $currentTime', style: const TextStyle(fontSize: 13, color: Color(0xFFC5A059), fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('📳 هُز الهاتف أو نادِ باسم $_secTitle.', style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ])),
          ]),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFFFFF8EE), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC5A059), width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)]),
          child: CalendarDatePicker(key: ValueKey(formattedDate), initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2030), onDateChanged: (d) => setState(() => _selectedDate = d)),
        ),
        const SizedBox(height: 15),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('جدول أعمال اليوم:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
            Chip(label: Text('${dayTasks.length} مواعيد', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1B2A4A)),
          ]),
        ),
        dayTasks.isEmpty
            ? Container(padding: const EdgeInsets.all(30), child: Column(children: [Icon(Icons.event_note, size: 50, color: Colors.grey.shade400), const SizedBox(height: 8), const Text('لا توجد مواعيد', style: TextStyle(color: Colors.grey, fontSize: 14))]))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dayTasks.length,
                itemBuilder: (ctx, i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border(right: BorderSide(color: Color(0xFFC5A059), width: 5)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5)]),
                  child: ListTile(
                    leading: const Icon(Icons.alarm, color: Color(0xFF1B2A4A)),
                    title: Text(dayTasks[i]['task'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: Text('${dayTasks[i]['time']} • ${dayTasks[i]['repeat'] ?? 'مرة واحدة'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      dayTasks[i]['alarm'] == true ? const Icon(Icons.notifications_active, color: Colors.redAccent) : const Icon(Icons.notifications_off, color: Colors.grey),
                      IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _editTaskDialog(_tasks.indexOf(dayTasks[i]))),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteTask(_tasks.indexOf(dayTasks[i]))),
                    ]),
                  ),
                ),
              ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildDiariesTab() {
    return SingleChildScrollView(child: Column(children: [
      Container(width: double.infinity, margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1B2A4A), borderRadius: BorderRadius.circular(12)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📖 مفكرة اليوميات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        SizedBox(height: 5),
        Text('اختر أي يوم لفتح صفحة التدوين.', style: TextStyle(color: Colors.white70, fontSize: 13)),
      ])),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC5A059), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)]),
        child: CalendarDatePicker(initialDate: _diaryDate, firstDate: DateTime(2024), lastDate: DateTime(2030), onDateChanged: (selectedDay) { setState(() => _diaryDate = selectedDay); _openDiaryPage(selectedDay); }),
      ),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B2A4A), minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: const Icon(Icons.edit_note, color: Color(0xFFC5A059)), label: const Text('فتح يومية اليوم', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: () => _openDiaryPage(_diaryDate))),
      const SizedBox(height: 20),
    ]));
  }

  Widget _buildPrayerTimesTab() {
    return FutureBuilder<Map<String, String>>(
      future: _calculatePrayerTimes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final times = snapshot.data!;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF0F172A)]), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC5A059), width: 1.5)), child: const Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.access_time_filled, color: Color(0xFFC5A059), size: 22), SizedBox(width: 8), Text('مواقيت الصلاة', style: TextStyle(color: Color(0xFFC5A059), fontSize: 16, fontWeight: FontWeight.bold))])])),
          const SizedBox(height: 15),
          _prayerCard('الفجر', times['fajr']!, Icons.wb_twilight),
          _prayerCard('الشروق', times['sunrise']!, Icons.wb_sunny_outlined),
          _prayerCard('الظهر', times['dhuhr']!, Icons.wb_sunny),
          _prayerCard('العصر', times['asr']!, Icons.filter_drama),
          _prayerCard('المغرب', times['maghrib']!, Icons.nights_stay_outlined),
          _prayerCard('العشاء', times['isha']!, Icons.nights_stay),
        ]);
      },
    );
  }

  Widget _prayerCard(String title, String time, IconData icon) {
    return Container(margin: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]), child: ListTile(leading: Icon(icon, color: const Color(0xFF1B2A4A)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)), trailing: Text(time, style: const TextStyle(color: Color(0xFF1B2A4A), fontSize: 16, fontWeight: FontWeight.bold))));
  }

  Widget _buildSpecialEventsTab() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('المناسبات والتنبيهات:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
      const SizedBox(height: 10),
      InkWell(onTap: _addSpecialEventDialog, child: Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: const ListTile(leading: Icon(Icons.cake, color: Colors.pink, size: 32), title: Text('أعياد الميلاد (اضغط للإضافة)', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('تنبيهات مسبقة'), trailing: Icon(Icons.add_circle, color: Color(0xFF1B2A4A))))),
      const SizedBox(height: 20),
      const Text('قائمة المناسبات:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A))),
      const SizedBox(height: 10),
      if (_specialEvents.isEmpty)
        Container(padding: const EdgeInsets.all(30), child: Column(children: [Icon(Icons.stars, size: 50, color: Colors.grey.shade400), const SizedBox(height: 8), const Text('لا توجد مناسبات', style: TextStyle(color: Colors.grey, fontSize: 14))]))
      else
        ..._specialEvents.asMap().entries.map((entry) {
          final i = entry.key;
          final e = entry.value;
          final eventDate = DateTime.tryParse(e['eventDate'] ?? '') ?? DateTime.now();
          final now = DateTime.now();
          final thisYear = DateTime(now.year, eventDate.month, eventDate.day);
          final nextYear = DateTime(now.year + 1, eventDate.month, eventDate.day);
          final nextOccurrence = thisYear.isAfter(now) ? thisYear : nextYear;
          final remaining = _formatRemaining(nextOccurrence);
          final reminderTime = '${(e['reminderHour'] ?? 18).toString().padLeft(2, '0')}:${(e['reminderMinute'] ?? 0).toString().padLeft(2, '0')}';
          final repeatInterval = e['repeatInterval'] ?? 'مرة واحدة';
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade300)),
            child: ListTile(
              leading: const Icon(Icons.stars, color: Color(0xFFC5A059), size: 28),
              title: Text(e['title'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${e['detail']} • ${DateFormat('yyyy/MM/dd').format(eventDate)}\nالتذكير: ${e['advanceReminder']} الساعة $reminderTime • $remaining\nالتنبيه المستمر: $repeatInterval'),
              isThreeLine: true,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _editSpecialEventDialog(i)),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () { setState(() => _specialEvents.removeAt(i)); _saveData(); }),
              ]),
            ),
          );
        }),
    ]);
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
                  style: ElevatedButton.styleFrom(backgroundColor: _isRecording ? Colors.red : const Color(0xFFC5A059), minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record, color: _isRecording ? Colors.white : Colors.black),
                  label: Text(_isRecording ? 'إيقاف التسجيل' : 'بدء التسجيل', style: TextStyle(color: _isRecording ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Align(alignment: Alignment.centerRight, child: Text('التسجيلات المحفوظة:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A)))),
          const SizedBox(height: 10),
          Expanded(
            child: _recordings.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.mic_none, size: 60, color: Colors.grey.shade400), const SizedBox(height: 10), const Text('لا توجد تسجيلات', style: TextStyle(color: Colors.grey, fontSize: 14))]))
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
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isPlaying ? const Color(0xFFC5A059) : Colors.grey.shade300, width: isPlaying ? 2 : 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                        child: Column(
                          children: [
                            ListTile(
                              leading: IconButton(icon: Icon(isPlaying ? Icons.stop_circle : Icons.play_circle_fill, color: const Color(0xFF1B2A4A), size: 32), onPressed: () => _playRecording(path)),
                              title: Text(rec['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text('المدة: ${rec['duration']}\n$dateText', style: const TextStyle(fontSize: 12)),
                              isThreeLine: true,
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(icon: const Icon(Icons.share, color: Colors.green, size: 22), onPressed: () => _shareRecording(path)),
                                IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 22), onPressed: () => _renameRecording(i)),
                                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22), onPressed: () => _deleteRecording(i)),
                              ]),
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
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                    Text(_formatDuration(_currentPosition), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text(_formatDuration(_currentDuration), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ]),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    const Icon(Icons.volume_up, size: 20, color: Color(0xFF1B2A4A)),
                                    Expanded(
                                      child: Slider(
                                        value: _playbackVolume,
                                        min: 0.0,
                                        max: 1.0,
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
                                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
                                  ]),
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
}
