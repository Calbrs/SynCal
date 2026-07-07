package com.example.SynCal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import java.util.Timer
import java.util.TimerTask
import kotlin.concurrent.thread

class SmsForegroundService : Service() {

    companion object {
        private const val TAG = "SmsForegroundService"
        private const val CHANNEL_ID = "sms_service_channel"
        private const val NOTIFICATION_ID = 1001
        private const val WAKELOCK_TAG = "SynCal:SmsSendWakeLock"
        private const val HEADLESS_CHANNEL = "com.example.SynCal/headless"
        private const val WATCHDOG_TIMEOUT_MS = 45_000L
    }

    private var continuousWakeLock: PowerManager.WakeLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var isProcessing = false
    private var periodicTimer: Timer? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        
        // Acquire a continuous Partial WakeLock to keep the CPU awake
        // This prevents Deep Sleep and guarantees the 30-second watchdog
        // runs exactly on time, bypassing OEM AlarmManager throttling.
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        continuousWakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SynCal:ContinuousWakeLock").apply {
            acquire() // Held indefinitely while service is alive
        }
        Log.d(TAG, "Continuous WakeLock acquired")
        
        // Start the periodic watchdog timer on a dedicated background thread.
        // We use java.util.Timer instead of a MainLooper Handler because
        // many OEMs freeze the UI Main Thread when the app is backgrounded.
        periodicTimer = Timer("SmsWatchdogTimer")
        periodicTimer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                Log.d(TAG, "Periodic watchdog: checking for due schedules (Background Thread)")
                if (!isProcessing) {
                    isProcessing = true
                    acquireWakeLock()
                    // Already on a background thread, so no need to spawn a new one
                    processSmsQueue(isPeriodicCheck = true)
                }
            }
        }, 30_000L, 30_000L)
    }

    // Unkillable mode setting check removed: service is now unconditionally persistent.

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: Received intent to process queue")
        
        if (!isProcessing) {
            isProcessing = true
            acquireWakeLock()
            
            // Process queue on a background thread (Pipeline execution)
            thread {
                processSmsQueue(isPeriodicCheck = false)
            }
        }
        
        // Update notification
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, buildNotification())

        // Return START_STICKY to ensure the OS restarts the service if it's killed.
        Log.d(TAG, "Returning START_STICKY to keep service alive.")
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        periodicTimer?.cancel()
        periodicTimer = null
        continuousWakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "Continuous WakeLock released")
            }
        }
        releaseWakeLock()
        stopForeground(true)
        super.onDestroy()
        Log.d(TAG, "onDestroy: SmsForegroundService stopped")
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG).apply {
                acquire(10 * 60 * 1000L) // 10 minutes max timeout as a safety net
            }
            Log.d(TAG, "WakeLock acquired")
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "WakeLock released")
            }
        }
        wakeLock = null
    }

    // ── Pipeline Execution ──────────────────────────────────────────────────

    private fun processSmsQueue(isPeriodicCheck: Boolean = false) {
        val appContext = applicationContext
        
        // Step 1: Find ALL due schedules from SQLite
        val dueSchedules = NativeScheduleStore.getDue(appContext)

        if (dueSchedules.isNotEmpty()) {
            Log.d(TAG, "PRIMARY path: ${dueSchedules.size} schedule(s) due — processing queue natively")
            
            // Step 2 & 3: Process the queue (send via SmsManager)
            for (schedule in dueSchedules) {
                // ── Atomic claim ─────────────────────────────────────────────
                // Transitions status pending → processing in a single SQLite
                // UPDATE. Returns false if another path (headless Flutter,
                // WorkManager isolate, etc.) already claimed this schedule,
                // in which case we skip to avoid sending a duplicate SMS.
                if (!NativeScheduleStore.claimForSending(appContext, schedule.scheduleId)) {
                    Log.w(TAG, "Schedule ${schedule.scheduleId} already claimed by another path — skipping native send")
                    continue
                }

                val success = sendScheduleNatively(appContext, schedule)
                
                // Step 4: Update state in the database
                if (success) {
                    NativeScheduleStore.markAsSent(appContext, schedule.scheduleId)
                    Log.d(TAG, "Schedule ${schedule.scheduleId} sent natively — marked sent")
                } else {
                    NativeScheduleStore.markAsFailed(appContext, schedule.scheduleId)
                    Log.w(TAG, "Schedule ${schedule.scheduleId} send failed — marked failed")
                }
            }

            
            // Step 5: Reschedule remaining alarms
            AlarmScheduler.scheduleAtFromPrefs(appContext)
            
            // Step 6: Shut down service
            finishProcessing()
        } else {
            // FALLBACK PATH: If SQLite is empty, run headless Flutter to check if Dart has anything
            // To save battery, we ONLY spin up Headless Flutter if triggered by an intent (AlarmManager),
            // NOT during the 30-second periodic checks.
            if (!isPeriodicCheck) {
                Log.d(TAG, "FALLBACK path: no native schedule found — starting headless Flutter engine")
                Handler(Looper.getMainLooper()).post {
                    runHeadlessTask(appContext)
                }
            } else {
                Log.d(TAG, "Periodic check: no native schedules due. Skipping headless fallback to save battery.")
                finishProcessing()
            }
        }
    }

    private fun finishProcessing() {
        isProcessing = false
        releaseWakeLock()
        
        // We no longer stop the service here. We want it to remain persistent
        // in the foreground so the OS does not kill the app, similar to SMSGate.
        Log.d(TAG, "finishProcessing: Queue empty. Service remains alive in foreground.")
    }

    // ── Native SMS sending ──────────────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun sendScheduleNatively(
        context: Context,
        schedule: NativeScheduleStore.NativeSchedule
    ): Boolean {
        if (schedule.recipients.isEmpty()) {
            Log.w(TAG, "Schedule ${schedule.scheduleId} has no recipients")
            return false
        }
        return try {
            val smsManager = getSmsManager(context, schedule.simSlot)
            for (recipient in schedule.recipients) {
                val parts = smsManager.divideMessage(schedule.message)
                if (parts.size == 1) {
                    smsManager.sendTextMessage(recipient.phone, null, schedule.message, null, null)
                } else {
                    smsManager.sendMultipartTextMessage(
                        recipient.phone, null, parts,
                        null, null
                    )
                }
                Log.d(TAG, "  → Sent to ${recipient.name} (${recipient.phone})")
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "sendScheduleNatively error for ${schedule.scheduleId}: ${e.message}")
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun getSmsManager(context: Context, simSlot: Int): SmsManager {
        if (simSlot < 0) {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else SmsManager.getDefault()
        }
        return try {
            val subMgr = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val subs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                subMgr.activeSubscriptionInfoList ?: emptyList()
            } else emptyList()
            val sub = subs.getOrNull(simSlot)
            when {
                sub != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                    context.getSystemService(SmsManager::class.java)
                        .createForSubscriptionId(sub.subscriptionId)
                sub != null ->
                    SmsManager.getSmsManagerForSubscriptionId(sub.subscriptionId)
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                    context.getSystemService(SmsManager::class.java)
                else -> SmsManager.getDefault()
            }
        } catch (e: Exception) {
            Log.w(TAG, "getSmsManager fallback: ${e.message}")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                context.getSystemService(SmsManager::class.java)
            else SmsManager.getDefault()
        }
    }

    // ── Headless Flutter Fallback ───────────────────────────────────────────

    private fun runHeadlessTask(context: Context) {
        val loader = FlutterLoader()
        if (!loader.initialized()) loader.startInitialization(context)
        loader.ensureInitializationComplete(context, null)

        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(
            getCallbackHandle(context)
        )
        if (callbackInfo == null) {
            Log.e(TAG, "No Dart callback handle — headless fallback unavailable")
            finishProcessing()
            return
        }

        val engine = FlutterEngine(context)
        var finished = false
        val watchdog = Handler(Looper.getMainLooper())
        val watchdogRunnable = Runnable {
            if (!finished) {
                Log.w(TAG, "Headless watchdog timeout — tearing down")
                finished = true
                try { engine.destroy() } catch (_: Exception) {}
                finishProcessing()
            }
        }
        watchdog.postDelayed(watchdogRunnable, WATCHDOG_TIMEOUT_MS)

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, HEADLESS_CHANNEL)

        SmsStatusTracker.init(context)
        val smsChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.example.SynCal/sms")
        val smsHandler = SmsMethodCallHandler(context)
        smsChannel.setMethodCallHandler(smsHandler)
        SmsStatusTracker.setChannel(smsChannel)

        channel.setMethodCallHandler { call, result ->
            if (call.method == "headlessTaskComplete") {
                Log.d(TAG, "Headless task signaled completion")
                if (!finished) {
                    finished = true
                    watchdog.removeCallbacks(watchdogRunnable)
                    result.success(null)
                    Handler(Looper.getMainLooper()).postDelayed({
                        try { engine.destroy() } catch (_: Exception) {}
                        finishProcessing()
                    }, 200)
                } else {
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }

        val dartCallback = DartExecutor.DartCallback(
            context.assets,
            loader.findAppBundlePath(),
            callbackInfo
        )
        engine.dartExecutor.executeDartCallback(dartCallback)
        Log.d(TAG, "Headless engine started, awaiting Dart-side completion signal")
    }

    private fun getCallbackHandle(context: Context): Long {
        val prefs = context.getSharedPreferences("headless_callback_prefs", Context.MODE_PRIVATE)
        return prefs.getLong("callback_handle", 0L)
    }

    // ── Foreground Notification ─────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SMS Processing Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Runs briefly to process scheduled messages"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SynCal Background Service")
            .setContentText("Listening for schedules... (Persistent)")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true) // Crucial: prevents the user from swiping away the notification, making it unkillable
            .build()
    }
}