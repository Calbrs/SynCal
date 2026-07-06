package com.example.SynCal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * AlarmManager alarms (and Workmanager periodic tasks in some OEM ROMs) are
 * wiped on reboot. This receiver re-establishes both the exact per-schedule
 * alarm and the safety-net repeating alarm immediately after boot, then fires
 * one immediate due-schedule check in case something was due while the device
 * was off.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        Log.d(TAG, "Boot completed — restoring alarms and checking due schedules")
        val appContext = context.applicationContext

        // 1. Re-arm the exact per-schedule alarm using the persisted trigger time.
        //    AlarmManager alarms are wiped on reboot; this restores the precise
        //    delivery time for the next scheduled message.
        AlarmScheduler.scheduleAtFromPrefs(appContext)

        // 2. Re-register the safety-net 15-min repeating alarm.
        AlarmScheduler.scheduleSafetyNet(appContext)

        // 3. Trigger an immediate check in case a message was due while the
        //    phone was powered off. scheduleAtFromPrefs already fires in 5s for
        //    overdue alarms, but this covers Workmanager safety-net path too.
        val checkIntent = Intent(appContext, ScheduleAlarmReceiver::class.java).apply {
            action = AlarmScheduler.ACTION_PROCESS_DUE_SCHEDULES
        }
        ScheduleAlarmReceiver().onReceive(appContext, checkIntent)
    }
}