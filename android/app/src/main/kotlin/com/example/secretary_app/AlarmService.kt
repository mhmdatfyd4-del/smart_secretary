package com.example.secretary_app

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import java.util.Locale

class AlarmService : Service(), TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var isTtsReady = false
    private var pendingText: String? = null

    companion object {
        const val CHANNEL_ID = "secretary_native_alarm_v1"
        const val NOTIF_ID = 99001
        const val EXTRA_TITLE = "title"
        const val ACTION_START = "com.example.secretary_app.START_ALARM"
        const val ACTION_STOP = "com.example.secretary_app.STOP_ALARM"
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        tts = TextToSpeech(this, this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: return START_NOT_STICKY

        val notification = buildNotification(title)
        startForeground(NOTIF_ID, notification)

        if (isTtsReady) {
            speak(title)
        } else {
            pendingText = title
        }

        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "منبه السكرتير (Native)",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "تنبيهات المنبه في الخلفية"
                setSound(null, null)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String): Notification {
        val stopIntent = Intent(this, AlarmService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val openPending = PendingIntent.getActivity(
            this, 2, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("تنبيه هام!")
            .setContentText("حان الآن موعد: $title")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "إيقاف", stopPending)
            .build()
    }

    private fun speak(text: String) {
        val toSay = "حان الآن موعد: $text"
        tts?.setLanguage(Locale("ar"))
        tts?.setSpeechRate(0.48f)
        tts?.setPitch(1.0f)
        tts?.speak(toSay, TextToSpeech.QUEUE_FLUSH, null, "alarm_${System.currentTimeMillis()}")
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isTtsReady = true
            pendingText?.let {
                speak(it)
                pendingText = null
            }
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
