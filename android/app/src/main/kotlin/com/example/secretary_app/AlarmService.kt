package com.example.secretary_app

import android.animation.ObjectAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
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
    
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var lipSyncAnimator: ObjectAnimator? = null

    companion object {
        private const val TAG = "AlarmService"
        const val CHANNEL_ID = "secretary_native_alarm_v6"
        const val NOTIF_ID = 99001
        const val EXTRA_TITLE = "title"
        const val EXTRA_PREFIX = "prefix"
        const val EXTRA_SOUND_URI = "soundUri"
        const val EXTRA_SHOW_ON_SCREEN = "showOnScreen"
        const val ACTION_START = "com.example.secretary_app.START_ALARM"
        const val ACTION_CANCEL = "com.example.secretary_app.CANCEL_ALARM"
        const val DEFAULT_PREFIX = "حان الآن موعد: "
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        tts = TextToSpeech(this, this)
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SecretaryApp::AlarmWakeLock")
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            stopAlarmAndOverlay()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: return START_NOT_STICKY
        val prefix = intent?.getStringExtra(EXTRA_PREFIX) ?: DEFAULT_PREFIX
        customSoundUri = intent?.getStringExtra(EXTRA_SOUND_URI)
        showOnScreen = intent?.getBooleanExtra(EXTRA_SHOW_ON_SCREEN, true) ?: true

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

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val useOverlay = prefs.getBoolean("flutter.use_overlay_alarm", true)

        if (showOnScreen && useOverlay) {
            showAlarmOverlay(title, prefix, hasCustomSound)
        }

        return START_NOT_STICKY
    }

    private fun showAlarmOverlay(title: String, prefix: String, hasCustomSound: Boolean) {
        if (!Settings.canDrawOverlays(this)) return
        if (overlayView != null) return

        Handler(Looper.getMainLooper()).post {
            try {
                val layout = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    setBackgroundColor(Color.parseColor("#E61B2A4A"))
                    setPadding(60, 60, 60, 60)
                }

                val imageView = ImageView(this).apply {
                    setImageResource(R.mipmap.ic_launcher)
                    layoutParams = LinearLayout.LayoutParams(250, 250).apply {
                        gravity = Gravity.CENTER
                        setMargins(0, 0, 0, 30)
                    }
                }
                layout.addView(imageView)

                // 👈 حركة الفم (لو المنبه بصوت السكرتير)
                if (!hasCustomSound) {
                    lipSyncAnimator = ObjectAnimator.ofFloat(imageView, "scaleY", 1f, 1.1f, 1f).apply {
                        duration = 300
                        repeatCount = ObjectAnimator.INFINITE
                        start()
                    }
                }

                val textView = TextView(this).apply {
                    text = "تنبيه هام!\n\n$prefix$title"
                    setTextColor(Color.WHITE)
                    textSize = 24f
                    gravity = Gravity.CENTER
                    setTypeface(null, Typeface.BOLD)
                    setPadding(0, 0, 0, 50)
                }
                layout.addView(textView)

                val button = Button(this).apply {
                    text = "خلاص (إيقاف)"
                    textSize = 20f
                    setTextColor(Color.BLACK)
                    setTypeface(null, Typeface.BOLD)
                    background = GradientDrawable().apply {
                        setColor(Color.parseColor("#C5A059"))
                        cornerRadius = 30f
                    }
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 150)
                    setOnClickListener { stopAlarmAndOverlay() }
                }
                layout.addView(button)

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    else WindowManager.LayoutParams.TYPE_PHONE,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT
                ).apply { gravity = Gravity.CENTER }

                windowManager?.addView(layout, params)
                overlayView = layout

            } catch (e: Exception) { Log.e(TAG, "Overlay failed", e) }
        }
    }

    private fun stopAlarmAndOverlay() {
        try {
            lipSyncAnimator?.cancel()
            if (overlayView != null && windowManager != null) {
                windowManager?.removeView(overlayView)
                overlayView = null
            }
        } catch (e: Exception) {}
        tts?.stop()
        mediaPlayer?.stop()
        stopForeground(true)
        stopSelf()
    }

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
                prepare()
                start()
            }
        } catch (e: Exception) { speakTts(DEFAULT_PREFIX, "تنبيه هام") }
    }

    private fun speakTts(prefix: String, text: String) {
        if (isTtsReady) {
            val audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
            tts?.setAudioAttributes(audioAttributes)
            tts?.setLanguage(Locale("ar"))
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

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("تنبيه هام!").setContentText(title)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_MAX).setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true).setContentIntent(pendingIntent).setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "إلغاء التنبيه", cancelPendingIntent)

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
        stopAlarmAndOverlay()
        tts?.shutdown(); mediaPlayer?.release()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
