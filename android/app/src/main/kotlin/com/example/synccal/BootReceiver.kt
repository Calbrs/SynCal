package com.example.SynCal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * AlarmManager alarms (and Workmanager periodic tasks in some OEM ROMs) are
 * wiped on reboot. This receiver re-establishes the safety-net repeating
 * alarm immediately after boot, and also fires one immediate due-schedule
 * check (via ScheduleAlarmReceiver) in case something was due while the
 * device was off.
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
        Log.d(TAG, "Boot completed — restoring safety-net alarm and checking due schedules")
        val appContext = context.applicationContext

        AlarmScheduler.scheduleSafetyNet(appContext)

        // Trigger an immediate check in case a message was due while the
        // phone was powered off.
        val checkIntent = Intent(appContext, ScheduleAlarmReceiver::class.java).apply {
            action = AlarmScheduler.ACTION_PROCESS_DUE_SCHEDULES
        }
        ScheduleAlarmReceiver().onReceive(appContext, checkIntent)
    }
}