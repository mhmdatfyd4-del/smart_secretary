package com.example.secretary_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.Locale

class AlarmService : Service(), TextToSpeech.OnInitListener, RecognitionListener {
    private var tts: TextToSpeech? = null
    private var isTtsReady = false
    private var pendingText: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var stopRequested = false
    private val handler = Handler(Looper.getMainLooper())

    private val mutedStreams = mutableMapOf<Int, Int>()
    private var muteRestoreRunnable: Runnable? = null

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
        sendBroadcast(Intent("com.example.secretary_app.PAUSE_WAKE_WORD"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP || stopRequested) {
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: return START_NOT_STICKY
        val prefix = intent?.getStringExtra(EXTRA_PREFIX) ?: DEFAULT_PREFIX
        val notification = buildNotification(title)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(
                    NOTIF_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } catch (e: Exception) {
                startForeground(NOTIF_ID, notification)
            }
        } else {
            startForeground(NOTIF_ID, notification)
        }

        if (wakeLock?.isHeld == false) wakeLock?.acquire(60 * 1000L)

        if (isTtsReady) speak(prefix, title) else pendingText = "$prefix|$title"
        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "منبه السكرتير (خلفية)", NotificationManager.IMPORTANCE_MIN).apply {
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
            .setOngoing(true).setSilent(true).setShowWhen(false)
            .build()
    }

    private fun speak(prefix: String, text: String) {
        val toSay = "$prefix$text"

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
                if (!stopRequested) {
                    startListening()
                }
            }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                if (!stopRequested) {
                    startListening()
                }
            }
        })

        tts?.speak(toSay, TextToSpeech.QUEUE_FLUSH, null, "alarm_${System.currentTimeMillis()}")
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

    private fun startListening() {
        if (stopRequested) return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) return

        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (prefs.getBoolean("flutter.mute_beep", true)) {
                setSystemSoundMute(true)
                muteRestoreRunnable?.let { handler.removeCallbacks(it) }
                muteRestoreRunnable = Runnable { setSystemSoundMute(false) }
                handler.postDelayed(muteRestoreRunnable!!, 3500)
            }

            speechRecognizer?.destroy()
            speechRecognizer = null
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
            speechRecognizer?.setRecognitionListener(this)

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-EG")
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "ar-EG")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 700L)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 400L)
            }

            speechRecognizer?.startListening(intent)
        } catch (e: Exception) {}
    }

    private fun isStopCommand(text: String): Boolean {
        if (text.isBlank()) return false
        val normalized = text.lowercase()
            .replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
            .replace("ة", "ه").replace("ى", "ي").replace(Regex("\\s+"), "")

        val variants = listOf(
            normalized, normalized.replace("ص", "س"), normalized.replace("س", "ص"),
            normalized.replace("خ", "ح"), normalized.replace("ح", "خ"),
        )
        val keywords = listOf(
            "خلاص", "خلاس", "خالص", "خالس", "صحيت", "صحيتو", "صاحي", "قومت", "قمت",
            "فوقت", "فقت", "ايقاف", "الغاء", "الغي", "الغ", "كفايه", "كافي", "كافيه",
            "قف", "وقف", "اوقف", "بس", "بلاها", "بلاش", "خلص", "خلصت",
            "ستوب", "stop", "quit", "cancel", "توقف", "توقفي", "اسكت", "اسكتي", "سكوت", "انتهي", "كافي"
        )
        for (variant in variants) {
            for (keyword in keywords) {
                if (variant.contains(keyword)) return true
            }
        }
        return false
    }

    override fun onReadyForSpeech(params: Bundle?) { }
    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {}
    override fun onEvent(eventType: Int, params: Bundle?) {}

    override fun onError(error: Int) {
        forceUnmute()
        if (!stopRequested) {
            handler.postDelayed({ startListening() }, 500)
        }
    }

    override fun onResults(results: Bundle?) {
        forceUnmute()
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (matches != null && matches.isNotEmpty()) {
            for (i in 0 until matches.size) {
                val text = matches[i] ?: continue
                if (isStopCommand(text)) {
                    stopRequested = true
                    sendBroadcast(Intent("com.example.secretary_app.ALARM_STOPPED_BY_VOICE"))
                    stopSelf()
                    return
                }
            }
            if (!stopRequested) handler.postDelayed({ startListening() }, 300)
        } else {
            if (!stopRequested) handler.postDelayed({ startListening() }, 300)
        }
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (matches != null && matches.isNotEmpty()) {
            for (i in 0 until matches.size) {
                val text = matches[i] ?: continue
                if (isStopCommand(text)) {
                    stopRequested = true
                    sendBroadcast(Intent("com.example.secretary_app.ALARM_STOPPED_BY_VOICE"))
                    stopSelf()
                    return
                }
            }
        }
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
        stopRequested = true
        forceUnmute()
        tts?.stop()
        tts?.shutdown()
        speechRecognizer?.destroy()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        try {
            val intent = Intent(this, WakeWordService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
