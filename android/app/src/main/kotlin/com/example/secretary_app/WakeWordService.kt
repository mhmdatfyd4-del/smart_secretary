package com.example.secretary_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class WakeWordService : Service() {
    private var speechRecognizer: SpeechRecognizer? = null
    private var wakeWord: String = "يا سكرتير"
    private var secretaryName: String = "سارة"
    private var listenMode: String = "always"
    private var wakeWordTrigger: String = "both"
    private var voiceGender: String = "أنثى"
    private var intent: Intent? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())

    private var isPaused = false
    private val pauseReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.secretary_app.PAUSE_WAKE_WORD") {
                isPaused = true
                speechRecognizer?.cancel()
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
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(100, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(100, notification)
        }

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Secretary::WakeWordWakeLock")
        wakeLock?.acquire(10 * 60 * 1000L)

        ContextCompat.registerReceiver(this, pauseReceiver, android.content.IntentFilter("com.example.secretary_app.PAUSE_WAKE_WORD"), ContextCompat.RECEIVER_NOT_EXPORTED)

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        wakeWord = prefs.getString("flutter.custom_wake_word", "يا سكرتير") ?: "يا سكرتير"
        secretaryName = prefs.getString("flutter.secretary_name", "سارة") ?: "سارة"
        listenMode = prefs.getString("flutter.wake_word_mode", "always") ?: "always"
        wakeWordTrigger = prefs.getString("flutter.wake_word_trigger", "both") ?: "both"
        voiceGender = prefs.getString("flutter.voice_gender", "أنثى") ?: "أنثى"

        initSpeechRecognizer()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (isPaused) {
            isPaused = false
            if (wakeLock?.isHeld == false) wakeLock?.acquire(10 * 60 * 1000L)
            startListening()
        }
        return START_STICKY
    }

    private fun initSpeechRecognizer() {
        if (SpeechRecognizer.isRecognitionAvailable(this)) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
            intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-EG")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            }

            speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                
                override fun onError(error: Int) { 
                    if (!isPaused && listenMode != "off") {
                        handler.postDelayed({ startListening() }, 2000)
                    }
                }
                
                override fun onResults(results: Bundle?) { 
                    processResults(results)
                    if (!isPaused && listenMode != "off") {
                        handler.postDelayed({ startListening() }, 200)
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
        speechRecognizer?.cancel()
        speechRecognizer?.startListening(intent)
    }

    fun stopListening() {
        speechRecognizer?.cancel()
    }

    private fun normalizeArabic(text: String): String {
        return text.lowercase()
            .replace("أ", "ا")
            .replace("إ", "ا")
            .replace("آ", "ا")
            .replace("ة", "ه")
            .replace("ى", "ي")
            .replace(Regex("\\s+"), "")
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
                              text.contains(secTitleNorm) || 
                              text.contains(secTitleAltNorm)
            
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
                
                val openIntent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("WAKE_WORD_DETECTED", true)
                }
                startActivity(openIntent)
                
                val broadcastIntent = Intent("com.example.secretary_app.WAKE_WORD_DETECTED")
                sendBroadcast(broadcastIntent)
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel("WakeWordChannel", "Wake Word Service", NotificationManager.IMPORTANCE_LOW)
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
        super.onDestroy()
    }
}
