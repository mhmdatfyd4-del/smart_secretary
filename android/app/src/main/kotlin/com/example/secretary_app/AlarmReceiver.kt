package com.example.secretary_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: return
        val prefix = intent.getStringExtra("prefix") ?: AlarmService.DEFAULT_PREFIX
        val soundUri = intent.getStringExtra("soundUri")
        val showOnScreen = intent.getBooleanExtra("showOnScreen", true)

        val serviceIntent = Intent(context, AlarmService::class.java).apply {
            action = AlarmService.ACTION_START
            putExtra(AlarmService.EXTRA_TITLE, title)
            putExtra(AlarmService.EXTRA_PREFIX, prefix)
            putExtra(AlarmService.EXTRA_SOUND_URI, soundUri)
            putExtra(AlarmService.EXTRA_SHOW_ON_SCREEN, showOnScreen)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            try {
                context.startService(serviceIntent)
            } catch (_: Exception) {}
        }
    }
}
