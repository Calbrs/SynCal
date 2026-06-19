package com.example.SynCal

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Wraps AlarmManager scheduling with graceful degradation:
 * - If the app holds SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM (or is on an SDK
 *   where it isn't required), we schedule an exact, idle-doze-bypassing alarm.
 * - Otherwise we fall back to an inexact alarm that still bypasses Doze via
 *   setAndAllowWhileIdle, so messages still go out, just without a hard
 *   guarantee of exact timing. The app keeps working either way.
 */
object AlarmScheduler {
    private const val TAG = "AlarmScheduler"
    const val ACTION_PROCESS_DUE_SCHEDULES = "com.example.SynCal.PROCESS_DUE_SCHEDULES"
    const val ACTION_REGISTER_NEXT_BOOT_CHECK = "com.example.SynCal.BOOT_CHECK"
    private const val REQUEST_CODE = 7001

    private fun alarmManager(context: Context): AlarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    fun canScheduleExact(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager(context).canScheduleExactAlarms()
        } else {
            true
        }
    }

    private fun buildPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, ScheduleAlarmReceiver::class.java).apply {
            action = ACTION_PROCESS_DUE_SCHEDULES
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /**
     * Schedules a single wake-up at [triggerAtMillis]. Safe to call repeatedly;
     * each call replaces the previous pending alarm (same request code), which
     * is intentional — the Dart side always tells us the *next* due time.
     */
    fun scheduleAt(context: Context, triggerAtMillis: Long) {
        val pendingIntent = buildPendingIntent(context)
        val am = alarmManager(context)
        try {
            if (canScheduleExact(context)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
                Log.d(TAG, "Scheduled EXACT alarm at $triggerAtMillis")
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
                Log.d(TAG, "Scheduled inexact (fallback) alarm at $triggerAtMillis — exact-alarm permission not granted")
            }
        } catch (e: SecurityException) {
            // Defensive fallback in case the OS revokes exact-alarm permission
            // between our check and the actual call (can happen after user
            // toggles the setting in System Settings).
            Log.w(TAG, "Exact alarm denied at call time, falling back to inexact: ${e.message}")
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
    }

    fun cancel(context: Context) {
        val am = alarmManager(context)
        am.cancel(buildPendingIntent(context))
    }

    /** Also schedules a periodic safety-net check every 15 min, inexact (no special permission needed),
     * so a missed/cancelled exact alarm (e.g. OEM aggressively clearing alarms) still self-heals.
     */
    fun scheduleSafetyNet(context: Context) {
        val intent = Intent(context, ScheduleAlarmReceiver::class.java).apply {
            action = ACTION_PROCESS_DUE_SCHEDULES
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE + 1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val am = alarmManager(context)
        val interval = 15 * 60 * 1000L
        am.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + interval,
            interval,
            pendingIntent
        )
        Log.d(TAG, "Safety-net 15min repeating alarm scheduled")
    }
}