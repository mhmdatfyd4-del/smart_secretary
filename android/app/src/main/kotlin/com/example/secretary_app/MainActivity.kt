package com.example.secretary_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val LOCK_CHANNEL = "com.example.secretary_app/lock_screen"
    private val SETTINGS_CHANNEL = "com.example.secretary_app/settings"
    private val ALARM_CHANNEL = "com.example.secretary_app/native_alarm"
    private val SOUND_CHANNEL = "com.example.secretary_app/sounds"
    private val WAKE_WORD_CHANNEL = "com.example.secretary_app/wake_word"

    private var previewPlayer: MediaPlayer? = null
    private var previewRingtone: android.media.Ringtone? = null
    private var pendingWakeWord = false

    private val wakeWordReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.secretary_app.WAKE_WORD_DETECTED") {
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, WAKE_WORD_CHANNEL).invokeMethod("onWakeWordDetected", null)
                }
            }
        }
    }

    private val alarmStopReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.secretary_app.ALARM_STOPPED_BY_VOICE") {
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, WAKE_WORD_CHANNEL).invokeMethod("onAlarmStoppedByVoice", null)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(wakeWordReceiver, android.content.IntentFilter("com.example.secretary_app.WAKE_WORD_DETECTED"), Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(alarmStopReceiver, android.content.IntentFilter("com.example.secretary_app.ALARM_STOPPED_BY_VOICE"), Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(wakeWordReceiver, android.content.IntentFilter("com.example.secretary_app.WAKE_WORD_DETECTED"))
            registerReceiver(alarmStopReceiver, android.content.IntentFilter("com.example.secretary_app.ALARM_STOPPED_BY_VOICE"))
        }

        if (intent?.getBooleanExtra("WAKE_WORD_DETECTED", false) == true) {
            pendingWakeWord = true
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("WAKE_WORD_DETECTED", false)) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, WAKE_WORD_CHANNEL).invokeMethod("onWakeWordDetected", null)
            }
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(wakeWordReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(alarmStopReceiver) } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableShowWhenLocked" -> { enableShowWhenLocked(); result.success(true) }
                "disableShowWhenLocked" -> { disableShowWhenLocked(); result.success(true) }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFullScreenIntentSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                        } else {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) { result.success(false) }
                    }
                }
                "isFullScreenIntentAllowed" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val nm = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                            result.success(nm.canUseFullScreenIntent())
                        } else { result.success(true) }
                    } catch (e: Exception) { result.success(true) }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val title = call.argument<String>("title") ?: ""
                    val timestamp = call.argument<Long>("timestamp") ?: 0L
                    val prefix = call.argument<String>("prefix") ?: AlarmService.DEFAULT_PREFIX
                    scheduleAlarm(id, title, timestamp, prefix)
                    result.success(true)
                }
                "cancelAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    cancelAlarm(id)
                    result.success(true)
                }
                "stopAlarmService" -> {
                    try {
                        val intent = Intent(this, AlarmService::class.java)
                        stopService(intent)
                    } catch (_: Exception) {}
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOUND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableSounds" -> {
                    val sounds = mutableListOf<Map<String, String>>()
                    val customSounds = listOf(
                        "alarm_scary1" to "😱 مرعب 1", "alarm_scary2" to "👻 مرعب 2",
                        "alarm_iphone" to "📱 iPhone", "alarm_famous1" to "⭐ مشهور 1",
                        "alarm_famous2" to "⭐ مشهور 2", "alarm_loud1" to "🔊 صحيان قوي 1",
                        "alarm_loud2" to "🔊 صحيان قوي 2"
                    )
                    for ((fileName, displayName) in customSounds) {
                        try {
                            val resId = resources.getIdentifier(fileName, "raw", packageName)
                            if (resId != 0) {
                                val mp = MediaPlayer.create(this, resId)
                                val duration = mp?.duration ?: 5000
                                mp?.release()
                                sounds.add(mapOf("title" to displayName, "uri" to "raw://$fileName", "duration" to duration.toString()))
                            }
                        } catch (_: Exception) {}
                    }
                    val types = listOf(RingtoneManager.TYPE_ALARM to "منبه", RingtoneManager.TYPE_NOTIFICATION to "إشعار", RingtoneManager.TYPE_RINGTONE to "رنين")
                    for ((type, prefix) in types) {
                        try {
                            val manager = RingtoneManager(this)
                            manager.setType(type)
                            val cursor = manager.cursor
                            while (cursor.moveToNext()) {
                                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                                val uri = cursor.getString(RingtoneManager.URI_COLUMN_INDEX)
                                val id = cursor.getString(RingtoneManager.ID_COLUMN_INDEX)
                                sounds.add(mapOf("title" to "$prefix: $title", "uri" to "$uri/$id", "duration" to "0"))
                            }
                        } catch (_: Exception) {}
                    }
                    result.success(sounds)
                }
                "previewSound" -> {
                    val uriStr = call.argument<String>("uri") ?: ""
                    try {
                        previewPlayer?.release(); previewPlayer = null
                        previewRingtone?.stop(); previewRingtone = null
                        if (uriStr.startsWith("raw://")) {
                            val fileName = uriStr.replace("raw://", "")
                            val resId = resources.getIdentifier(fileName, "raw", packageName)
                            if (resId != 0) {
                                previewPlayer = MediaPlayer.create(this, resId)
                                previewPlayer?.start()
                                previewPlayer?.setOnCompletionListener { it.release(); previewPlayer = null }
                            }
                        } else {
                            previewRingtone = RingtoneManager.getRingtone(this, Uri.parse(uriStr))
                            previewRingtone?.play()
                        }
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "stopPreview" -> {
                    try {
                        previewPlayer?.stop(); previewPlayer?.release(); previewPlayer = null
                        previewRingtone?.stop(); previewRingtone = null
                    } catch (_: Exception) {}
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKE_WORD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startWakeWord" -> {
                    val intent = Intent(this, WakeWordService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(true)
                }
                "stopWakeWord" -> {
                    val intent = Intent(this, WakeWordService::class.java)
                    stopService(intent)
                    result.success(true)
                }
                "pauseWakeWord" -> {
                    sendBroadcast(Intent("com.example.secretary_app.PAUSE_WAKE_WORD"))
                    result.success(true)
                }
                "resumeWakeWord" -> {
                    val intent = Intent(this, WakeWordService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(true)
                }
                "isWakeWordPending" -> {
                    result.success(pendingWakeWord)
                    pendingWakeWord = false
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleAlarm(id: Int, title: String, timestamp: Long, prefix: String) {
        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("title", title); putExtra("prefix", prefix)
        }
        val pendingIntent = PendingIntent.getBroadcast(this, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent)
            else alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent)
        } else alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent)
    }

    private fun cancelAlarm(id: Int) {
        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(this, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarmManager.cancel(pendingIntent)
    }

    private fun enableShowWhenLocked() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else { @Suppress("DEPRECATION") window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON) }
    }

    private fun disableShowWhenLocked() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) { setShowWhenLocked(false); setTurnScreenOn(false) }
        else { @Suppress("DEPRECATION") window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON) }
    }
}
