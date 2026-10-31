package com.example.secretary_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isMuted = prefs.getBoolean("flutter.is_system_muted", false)
            
            // 👈 لو التطبيق كان بيكتم الصوت والتليفون عمل ريستارت، رجع الصوت
            if (isMuted) {
                try {
                    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val sysVol = prefs.getInt("flutter.muted_sys_vol", -1)
                    val notifVol = prefs.getInt("flutter.muted_notif_vol", -1)
                    val dtmfVol = prefs.getInt("flutter.muted_dtmf_vol", -1)

                    if (sysVol != -1) audioManager.setStreamVolume(AudioManager.STREAM_SYSTEM, sysVol, 0)
                    if (notifVol != -1) audioManager.setStreamVolume(AudioManager.STREAM_NOTIFICATION, notifVol, 0)
                    if (dtmfVol != -1) audioManager.setStreamVolume(AudioManager.STREAM_DTMF, dtmfVol, 0)
                    
                    prefs.edit().putBoolean("flutter.is_system_muted", false).apply()
                } catch (_: Exception) {}
            }
        }
    }
}
