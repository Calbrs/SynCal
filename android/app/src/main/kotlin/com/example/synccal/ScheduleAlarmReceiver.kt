package com.example.SynCal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Fired by AlarmManager when a scheduled message is due.
 *
 * This receiver is deliberately lightweight. It does NOT acquire a Wakelock
 * and does NOT send SMS directly. Its only job is to hand off execution
 * to SmsForegroundService, which will manage the WakeLock and process
 * the queue on a background thread.
 */
class ScheduleAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ScheduleAlarmReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Alarm received: ${intent.action} — delegating to SmsForegroundService")
        val appContext = context.applicationContext

        val serviceIntent = Intent(appContext, SmsForegroundService::class.java).apply {
            action = AlarmScheduler.ACTION_PROCESS_DUE_SCHEDULES
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(serviceIntent)
            } else {
                appContext.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start SmsForegroundService: ${e.message}")
        }
        
        // Receiver finishes immediately. Android keeps the process alive just long enough
        // to hand off to the foreground service.
    }
}