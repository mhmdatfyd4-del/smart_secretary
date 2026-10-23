package com.example.secretary_app

import android.app.*
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

    companion object {
        const val CHANNEL_ID = "secretary_native_alarm_v6" 
        const val NOTIF_ID = 99001
        const val EXTRA_TITLE = "title"
        const val EXTRA_PREFIX = "prefix"
        const val EXTRA_SOUND_URI = "soundUri"
        const val EXTRA_SHOW_ON_SCREEN = "showOnScreen"
        const val ACTION_START = "com.example.secretary_app.START_ALARM" // 👈 عشان البناء ينجح
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
        customSoundUri = intent?.getStringExtra(EXTRA_SOUND_URI)
        showOnScreen = intent?.getBooleanExtra(EXTRA_SHOW_ON_SCREEN, true) ?: true
        
        val notification = buildNotification(title)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIF_ID, notification)
        }

        if (wakeLock?.isHeld == false) wakeLock?.acquire(60 * 1000L)

        // 👈 محاولة فتح التطبيق 5 مرات عشان نتغلب على حماية أندرويد
        if (showOnScreen) {
            val mainHandler = Handler(Looper.getMainLooper())
            for (i in 0 until 5) {
                mainHandler.postDelayed({
                    try {
                        val launchIntent = Intent(this@AlarmService, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                        startActivity(launchIntent)
                    } catch (_: Exception) {}
                }, (i * 1000).toLong())
            }
        }

        // 👈 تشغيل الصوت مرة واحدة بس (من غير أي لوب)
        val hasCustomSound = !customSoundUri.isNullOrEmpty() && customSoundUri != "default" && customSoundUri != "null"
        if (hasCustomSound) {
            playCustomSound(customSoundUri!!)
        } else {
            speakTts(prefix, title)
        }

        return START_NOT_STICKY
    }

    private fun playCustomSound(uriStr: String) {
        try {
            mediaPlayer?.release()
            val uri: Uri = if (uriStr.startsWith("raw://")) {
                val resName = uriStr.replace("raw://", "")
                val resId = resources.getIdentifier(resName, "raw", packageName)
                if (resId != 0) {
                    Uri.parse("android.resource://$packageName/$resId")
                } else {
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                }
            } else {
                Uri.parse(uriStr)
            }

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@AlarmService, uri)
                prepare()
                start()
            }
        } catch (e: Exception) {
            speakTts(DEFAULT_PREFIX, "تنبيه هام")
        }
    }

    private fun speakTts(prefix: String, text: String) {
        if (isTtsReady) {
            val toSay = "$prefix$text"
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            tts?.setAudioAttributes(audioAttributes)
            tts?.setLanguage(Locale("ar"))
            tts?.setSpeechRate(1.0f)
            tts?.setPitch(1.0f)
            tts?.speak(toSay, TextToSpeech.QUEUE_FLUSH, null, "alarm")
        } else {
            pendingText = "$prefix|$text"
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "منبه السكرتير (خلفية)", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("تنبيه هام!")
            .setContentText(title)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setContentIntent(pendingIntent)

        if (showOnScreen) {
            builder.setFullScreenIntent(pendingIntent, true)
        }

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
        tts?.stop()
        tts?.shutdown()
        mediaPlayer?.stop()
        mediaPlayer?.release()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
