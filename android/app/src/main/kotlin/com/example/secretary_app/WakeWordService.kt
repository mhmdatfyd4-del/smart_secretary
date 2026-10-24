package com.example.secretary_app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class WakeWordService : Service() {
    private var speechRecognizer: SpeechRecognizer? = null
    private var wakeWord: String = "يا سكرتير"
    private var secretaryName: String = "سارة"
    private var listenMode: String = "always"
    private var wakeWordTrigger: String = "both"
    private var intent: Intent? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())

    private var isPaused = false
    private val mutedStreams = mutableMapOf<Int, Int>()
    private var muteRestoreRunnable: Runnable? = null

    private val pauseReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.secretary_app.PAUSE_WAKE_WORD") {
                isPaused = true
                speechRecognizer?.cancel()
                forceUnmute()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        val notification = NotificationCompat.Builder(this, "WakeWordChannel")
            .setContentTitle("سكرتيري")
            .setContentText("بيستنى تنادي عليه...")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(100, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(100, notification)
        }

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Secretary::WakeWordWakeLock")
        wakeLock?.acquire(10 * 60 * 1000L)

        ContextCompat.registerReceiver(
            this, pauseReceiver,
            android.content.IntentFilter("com.example.secretary_app.PAUSE_WAKE_WORD"),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        wakeWord = prefs.getString("flutter.custom_wake_word", "يا سكرتير") ?: "يا سكرتير"
        secretaryName = prefs.getString("flutter.secretary_name", "سارة") ?: "سارة"
        listenMode = prefs.getString("flutter.wake_word_mode", "always") ?: "always"
        wakeWordTrigger = prefs.getString("flutter.wake_word_trigger", "both") ?: "both"

        initSpeechRecognizer()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        listenMode = prefs.getString("flutter.wake_word_mode", "always") ?: "always"

        if (isPaused) {
            isPaused = false
            if (wakeLock?.isHeld == false) wakeLock?.acquire(10 * 60 * 1000L)
            startListening()
        }
        
        // لو الوضع مش "دائماً"، خلي النظام ميعملش إعادة تشغيل للخدمة لو اتقتلت
        return if (listenMode == "always") START_STICKY else START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val mode = prefs.getString("flutter.wake_word_mode", "off") ?: "off"
        
        if (mode != "always") {
            // الوضع "مفتوح" أو "خلفية": أوقف الخدمة نهائياً لما التطبيق يتقفل
            stopSelf()
        } else {
            // الوضع "دائماً": أعد تشغيل الخدمة
            val restartIntent = Intent(applicationContext, WakeWordService::class.java)
            restartIntent.setPackage(packageName)
            val pendingIntent = PendingIntent.getService(
                applicationContext, 1, restartIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = applicationContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.set(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + 1000,
                pendingIntent
            )
        }
    }

    private fun initSpeechRecognizer() {
        if (SpeechRecognizer.isRecognitionAvailable(this)) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
            intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-EG")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 2000L)
            }

            speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) { }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}

                override fun onError(error: Int) {
                    forceUnmute()
                    if (!isPaused && listenMode != "off") {
                        handler.postDelayed({ startListening() }, 1000)
                    }
                }

                override fun onResults(results: Bundle?) {
                    forceUnmute()
                    processResults(results)
                    if (!isPaused && listenMode != "off") {
                        handler.postDelayed({ startListening() }, 500)
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) { processResults(partialResults) }
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            startListening()
        }
    }

    fun startListening() {
        if (listenMode == "off" || isPaused) return
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (prefs.getBoolean("flutter.mute_beep", true)) {
            setSystemSoundMute(true)
            scheduleUnmute(3500)
        }
        speechRecognizer?.cancel()
        speechRecognizer?.startListening(intent)
    }

    fun stopListening() {
        speechRecognizer?.cancel()
        forceUnmute()
    }

    private fun scheduleUnmute(delayMs: Long) {
        muteRestoreRunnable?.let { handler.removeCallbacks(it) }
        muteRestoreRunnable = Runnable { forceUnmute() }
        handler.postDelayed(muteRestoreRunnable!!, delayMs)
    }

    private fun forceUnmute() {
        muteRestoreRunnable?.let { handler.removeCallbacks(it) }
        muteRestoreRunnable = null
        setSystemSoundMute(false)
    }

    private fun setSystemSoundMute(mute: Boolean) {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (mute) {
                if (mutedStreams.isNotEmpty()) return
                val streams = intArrayOf(
                    AudioManager.STREAM_SYSTEM,
                    AudioManager.STREAM_NOTIFICATION,
                    AudioManager.STREAM_DTMF
                )
                for (stream in streams) {
                    try {
                        val original = audioManager.getStreamVolume(stream)
                        mutedStreams[stream] = original
                        audioManager.setStreamVolume(stream, 0, 0)
                    } catch (_: Exception) {}
                }
            } else {
                for ((stream, original) in mutedStreams) {
                    try { audioManager.setStreamVolume(stream, original, 0) } catch (_: Exception) {}
                }
                mutedStreams.clear()
            }
        } catch (_: Exception) {}
    }

    private fun normalizeArabic(text: String): String {
        return text.lowercase()
            .replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
            .replace("ة", "ه").replace("ى", "ي").replace(Regex("\\s+"), "")
    }

    private fun processResults(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (matches != null && matches.isNotEmpty()) {
            val text = normalizeArabic(matches[0])
            val nameNorm = normalizeArabic(secretaryName)
            val customNorm = normalizeArabic(wakeWord)
            val secTitleNorm = normalizeArabic("سكرتير")
            val secTitleAltNorm = normalizeArabic("سكرتيره")

            val isNameMatch = (nameNorm.isNotEmpty() && text.contains(nameNorm)) ||
                    text.contains(secTitleNorm) || text.contains(secTitleAltNorm)
            val isCustomMatch = customNorm.isNotEmpty() && text.contains(customNorm)

            var isTriggered = false
            when (wakeWordTrigger) {
                "name_only" -> isTriggered = isNameMatch
                "custom_only" -> isTriggered = isCustomMatch
                else -> isTriggered = isNameMatch || isCustomMatch
            }

            if (isTriggered) {
                isPaused = true
                stopListening()
                forceUnmute()

                val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("WAKE_WORD_DETECTED", true)
                }
                val pendingIntent = PendingIntent.getActivity(
                    this, 0, fullScreenIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val notification = NotificationCompat.Builder(this, "WakeWordChannel")
                    .setContentTitle("سكرتيري")
                    .setContentText("جاري فتح التطبيق...")
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_CALL)
                    .setFullScreenIntent(pendingIntent, true)
                    .setAutoCancel(true)
                    .setTimeoutAfter(2000)
                    .build()

                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(888, notification)

                sendBroadcast(Intent("com.example.secretary_app.WAKE_WORD_DETECTED"))

                try {
                    startActivity(fullScreenIntent)
                    handler.postDelayed({ notificationManager.cancel(888) }, 500)
                } catch (e: Exception) {
                    Log.e("WakeWord", "فشل فتح التطبيق: ${e.message}")
                    isPaused = false
                    startListening()
                }
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                "WakeWordChannel", "Wake Word Service",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        speechRecognizer?.destroy()
        try { unregisterReceiver(pauseReceiver) } catch (_: Exception) {}
        if (wakeLock?.isHeld == true) wakeLock?.release()
        forceUnmute()
        super.onDestroy()
    }
}
