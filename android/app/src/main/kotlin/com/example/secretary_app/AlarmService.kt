package com.example.secretary_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import java.util.Locale

class AlarmService : Service(), TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var isTtsReady = false
    private var pendingText: String? = null
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val CHANNEL_ID = "secretary_native_alarm_v4"
        const val NOTIF_ID = 99001
        const val EXTRA_TITLE = "title"
        const val EXTRA_PREFIX = "prefix"
        const val ACTION_START = "com.example.secretary_app.START_ALARM"
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
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: return START_NOT_STICKY
        val prefix = intent?.getStringExtra(EXTRA_PREFIX) ?: DEFAULT_PREFIX
        val notification = buildNotification(title)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIF_ID, notification)
        }

        if (wakeLock?.isHeld == false) wakeLock?.acquire(60 * 1000L)

        if (isTtsReady) {
            speak(prefix, title)
        } else {
            pendingText = "$prefix|$title"
        }
        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 👈 غيرنا الأهمية لـ HIGH عشان يقدر يفتح الشاشة
            val channel = NotificationChannel(CHANNEL_ID, "منبه السكرتير (خلفية)", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String): Notification {
        // 👈 ده اللي بيفتح التطبيق لما الإشعار يضرب
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("تشغيل التنبيه").setContentText(title)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pendingIntent, true) // 👈 السر هنا: بيفتح التطبيق غصب عن النظام
            .setOngoing(true)
            .build()
    }

    private fun speak(prefix: String, text: String) {
        val toSay = "$prefix$text"
        
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        tts?.setAudioAttributes(audioAttributes)
        tts?.setLanguage(Locale("ar"))
        tts?.setSpeechRate(1.0f)
        tts?.setPitch(1.0f)

        tts?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) {
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ stopSelf() }, 1000)
            }
            override fun onError(utteranceId: String?) {
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ stopSelf() }, 1000)
            }
        })
        
        tts?.speak(toSay, TextToSpeech.QUEUE_FLUSH, null, "alarm")
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isTtsReady = true
            pendingText?.let {
                val parts = it.split("|", limit = 2)
                if (parts.size == 2) speak(parts[0], parts[1])
                pendingText = null
            }
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
