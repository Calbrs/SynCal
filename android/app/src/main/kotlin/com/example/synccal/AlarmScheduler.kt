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
                val showIntent = Intent(context, MainActivity::class.java)
                val showPendingIntent = PendingIntent.getActivity(
                    context,
                    REQUEST_CODE,
                    showIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMillis, showPendingIntent), pendingIntent)
                Log.d(TAG, "Scheduled EXACT (AlarmClock) alarm at $triggerAtMillis")
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

    /**
     * Reads the persisted next-alarm trigger time from SharedPreferences and
     * re-arms the exact AlarmManager alarm. Called by BootReceiver to restore
     * the alarm after device reboot (AlarmManager alarms are wiped on reboot).
     *
     * If the persisted time is already in the past (message was due while the
     * device was off), the alarm is set 5 seconds in the future so the headless
     * engine fires immediately and processes the overdue schedule.
     */
    fun scheduleAtFromPrefs(context: Context) {
        val prefs = context.getSharedPreferences(
            SmsMethodCallHandler.ALARM_PREFS_NAME,
            android.content.Context.MODE_PRIVATE
        )
        val triggerAtMillis = prefs.getLong(SmsMethodCallHandler.NEXT_ALARM_TRIGGER_KEY, 0L)
        if (triggerAtMillis == 0L) {
            Log.d(TAG, "scheduleAtFromPrefs: no persisted alarm — nothing to restore")
            return
        }
        // If the scheduled time is in the past, fire almost immediately so overdue
        // messages are processed as soon as the device finishes booting.
        val effectiveTrigger = if (triggerAtMillis <= System.currentTimeMillis()) {
            Log.d(TAG, "scheduleAtFromPrefs: schedule was due while device was off — firing in 5s")
            System.currentTimeMillis() + 5_000L
        } else {
            triggerAtMillis
        }
        scheduleAt(context, effectiveTrigger)
        Log.d(TAG, "scheduleAtFromPrefs: restored alarm for $effectiveTrigger (original: $triggerAtMillis)")
    }

    /** Also schedules a periodic safety-net check every 2 min, inexact (no special permission needed),
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
        val interval = 2 * 60 * 1000L
        am.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + interval,
            interval,
            pendingIntent
        )
        Log.d(TAG, "Safety-net 2min repeating alarm scheduled")
    }
}