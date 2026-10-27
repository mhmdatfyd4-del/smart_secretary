package com.example.secretary_app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.Locale

class AlarmService : Service(), TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var isTtsReady = false
    private var pendingText: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var mediaPlayer: MediaPlayer? = null
    private var customSoundUri: String? = null
    private var showOnScreen = true
    private var currentTitle: String = ""
    private var currentPrefix: String = DEFAULT_PREFIX
    private var intervalSeconds: Int = 0
    
    private val handler = Handler(Looper.getMainLooper())
    
    // 👈 تعديل 1: التكرار يقطع النغمة ويبدأها من الأول
    private val repeatRunnable = object : Runnable {
        override fun run() {
            val hasCustomSound = !customSoundUri.isNullOrEmpty() && customSoundUri != "default" && customSoundUri != "null"
            if (hasCustomSound) {
                playCustomSound(customSoundUri!!) 
            } else {
                speakTts(currentPrefix, currentTitle)
            }
            if (intervalSeconds > 0) {
                handler.postDelayed(this, intervalSeconds * 1000L)
            }
        }
    }

    companion object {
        private const val TAG = "AlarmService"
        const val CHANNEL_ID = "secretary_native_alarm_v6"
        const val NOTIF_ID = 99001
        const val EXTRA_TITLE = "title"
        const val EXTRA_PREFIX = "prefix"
        const val EXTRA_SOUND_URI = "soundUri"
        const val EXTRA_SHOW_ON_SCREEN = "showOnScreen"
        const val EXTRA_INTERVAL = "interval"
        const val ACTION_START = "com.example.secretary_app.START_ALARM"
        const val ACTION_CANCEL = "com.example.secretary_app.CANCEL_ALARM"
        const val ACTION_SNOOZE = "com.example.secretary_app.SNOOZE_ALARM"
        const val DEFAULT_PREFIX = "حان الآن موعد: "
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        tts = TextToSpeech(this, this)
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SecretaryApp::AlarmWakeLock")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            try {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().remove("flutter.pending_alarm").apply()
            } catch (_: Exception) {}
            stopAlarmAndSelf()
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_SNOOZE) {
            val snoozeTime = System.currentTimeMillis() + (5 * 60 * 1000)
            try {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val pendingJson = prefs.getString("flutter.pending_alarm", null)
                if (pendingJson != null) {
                    val obj = org.json.JSONObject(pendingJson)
                    obj.put("scheduledMillis", snoozeTime)
                    prefs.edit().putString("flutter.pending_alarm", obj.toString()).apply()
                }
            } catch (_: Exception) {}
            snoozeAlarm()
            stopAlarmAndSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: return START_NOT_STICKY
        val prefix = intent?.getStringExtra(EXTRA_PREFIX) ?: DEFAULT_PREFIX
        customSoundUri = intent?.getStringExtra(EXTRA_SOUND_URI)
        showOnScreen = intent?.getBooleanExtra(EXTRA_SHOW_ON_SCREEN, true) ?: true
        intervalSeconds = intent?.getIntExtra(EXTRA_INTERVAL, 0) ?: 0

        currentTitle = title
        currentPrefix = prefix

        val notification = buildNotification(title)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIF_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed", e)
        }

        if (wakeLock?.isHeld == false) wakeLock?.acquire(60 * 1000L)

        val hasCustomSound = !customSoundUri.isNullOrEmpty() && customSoundUri != "default" && customSoundUri != "null"
        if (hasCustomSound) {
            playCustomSound(customSoundUri!!)
        } else {
            speakTts(prefix, title)
        }

        handler.removeCallbacks(repeatRunnable)
        if (intervalSeconds > 0) {
            handler.postDelayed(repeatRunnable, intervalSeconds * 1000L)
        }

        return START_NOT_STICKY
    }

    private fun snoozeAlarm() {
        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager
        val snoozeTime = System.currentTimeMillis() + (5 * 60 * 1000) 
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_TITLE, currentTitle)
            putExtra(EXTRA_PREFIX, currentPrefix)
            putExtra(EXTRA_SOUND_URI, customSoundUri)
            putExtra(EXTRA_SHOW_ON_SCREEN, true)
            putExtra(EXTRA_INTERVAL, intervalSeconds)
        }val pendingIntent = PendingIntent.getBroadcast(
    this, currentTitle.hashCode() + 5000, intent, // 👈 ضيف الأقواس هنا
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
)
        val alarmClockInfo = AlarmManager.AlarmClockInfo(snoozeTime, pendingIntent)
        alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
    }

    // 👈 تعديل 2: إضافة release عشان الصوت يقف فوراً
    private fun stopAlarmAndSelf() {
        handler.removeCallbacks(repeatRunnable)
        tts?.stop()
        mediaPlayer?.stop()
        mediaPlayer?.release() 
        mediaPlayer = null      
        stopForeground(true)
        stopSelf()
    }

    // 👈 تعديل 3: isLooping = true عشان النغمة تفضل شغالة
    private fun playCustomSound(uriStr: String) {
        try {
            mediaPlayer?.release()
            val uri: Uri = if (uriStr.startsWith("raw://")) {
                val resName = uriStr.replace("raw://", "")
                val resId = resources.getIdentifier(resName, "raw", packageName)
                if (resId != 0) Uri.parse("android.resource://$packageName/$resId")
                else RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            } else Uri.parse(uriStr)

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                setDataSource(this@AlarmService, uri)
                isLooping = true 
                prepare()
                start()
            }
        } catch (e: Exception) { speakTts(DEFAULT_PREFIX, "تنبيه هام") }
    }

    // 👈 تعديل 4: توحيد اللغة ar-EG
    private fun speakTts(prefix: String, text: String) {
        if (isTtsReady) {
            val audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
            tts?.setAudioAttributes(audioAttributes)
            tts?.setLanguage(Locale("ar-EG")) 
            tts?.speak("$prefix$text", TextToSpeech.QUEUE_FLUSH, null, "alarm")
        } else { pendingText = "$prefix|$text" }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "منبه السكرتير", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null); setShowBadge(false); lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("from_alarm", true); putExtra("alarm_title", title)
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val cancelIntent = Intent(this, AlarmService::class.java).apply { action = ACTION_CANCEL }
        val cancelPendingIntent = PendingIntent.getService(this, 1, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val snoozeIntent = Intent(this, AlarmService::class.java).apply { action = ACTION_SNOOZE }
        val snoozePendingIntent = PendingIntent.getService(this, 2, snoozeIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("تنبيه هام!").setContentText(title)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_MAX).setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true).setContentIntent(pendingIntent).setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_menu_recent_history, "تأجيل ٥ د", snoozePendingIntent) 
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "إلغاء", cancelPendingIntent)

        if (showOnScreen) builder.setFullScreenIntent(pendingIntent, true)
        return builder.build()
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isTtsReady = true
            pendingText?.let {
                val parts = it.split("|", limit = 2)
                if (parts.size == 2) speakTts(parts[0], parts[1])
                pendingText = null
            }
        }
    }

    override fun onDestroy() {
        stopAlarmAndSelf()
        tts?.shutdown(); mediaPlayer?.release()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
