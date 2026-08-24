package com.kold.f50.monitor.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        val rawConfig = context.getSharedPreferences("f50_agent", Context.MODE_PRIVATE)
            .getString("config", null)
        val launchAtLogin = runCatching {
            rawConfig == null || org.json.JSONObject(rawConfig).optBoolean("launchAtLogin", true)
        }.getOrDefault(true)
        if (!launchAtLogin) return
        val serviceIntent = Intent(context, F50AgentService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
