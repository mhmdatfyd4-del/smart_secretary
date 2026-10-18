package com.example.secretary_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.NotificationCompat
import java.util.Locale

class AlarmService : Service(), TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var isTtsReady = false
    private var pendingText: String? = null
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val CHANNEL_ID = "secretary_native_alarm_v2"
        const val NOTIF_ID = 99001
        const val EXTRA_TITLE = "title"
        const val EXTRA_PREFIX = "prefix"
        const val ACTION_START = "com.example.secretary_app.START_ALARM"
        const val ACTION_STOP = "com.example.secretary_app.STOP_ALARM"
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
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: return START_NOT_STICKY
        val prefix = intent?.getStringExtra(EXTRA_PREFIX) ?: DEFAULT_PREFIX

        val notification = buildNotification(title)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(
                    NOTIF_ID,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } catch (e: Exception) {
                startForeground(NOTIF_ID, notification)
            }
        } else {
            startForeground(NOTIF_ID, notification)
        }

        if (wakeLock?.isHeld == false) {
            wakeLock?.acquire(60 * 1000L)
        }

        if (isTtsReady) {
            speak(prefix, title)
        } else {
            pendingText = "$prefix|$title"
        }

        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "منبه السكرتير (خلفية)",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "تشغيل صوت المنبه في الخلفية"
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("تشغيل التنبيه")
            .setContentText(title)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .build()
    }

    private fun speak(prefix: String, text: String) {
        val toSay = "$prefix$text"
        
        // صوت الميديا العادي
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
            
        tts?.setAudioAttributes(audioAttributes)
        tts?.setLanguage(Locale("ar"))
        tts?.setSpeechRate(1.0f)
        tts?.setPitch(1.0f)

        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) {
                stopSelf()
            }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                stopSelf()
            }
        })

        tts?.speak(toSay, TextToSpeech.QUEUE_FLUSH, null, "alarm_${System.currentTimeMillis()}")
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isTtsReady = true
            pendingText?.let {
                val parts = it.split("|", limit = 2)
                if (parts.size == 2) {
                    speak(parts[0], parts[1])
                }
                pendingText = null
            }
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
