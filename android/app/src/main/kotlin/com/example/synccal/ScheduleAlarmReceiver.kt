package com.example.SynCal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

/**
 * Fired by AlarmManager (exact or inexact, doze-bypassing) or by BootReceiver.
 * Spins up a short-lived headless FlutterEngine, asks Dart to process any due
 * scheduled messages, waits for a completion signal, then tears the engine
 * down again so we don't hold ~30-50MB of extra RAM indefinitely.
 *
 * This does NOT depend on MainActivity or the cached UI engine being alive —
 * it works even if the user has swiped the app away from recents, because
 * a BroadcastReceiver + a fresh FlutterEngine instance only need the process
 * to be startable, which AlarmManager guarantees (it will start the process
 * fresh if needed).
 */
class ScheduleAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ScheduleAlarmReceiver"
        private const val HEADLESS_CHANNEL = "com.example.SynCal/headless"
        private const val ENTRYPOINT_NAME = "scheduledMessageCallbackDispatcher"
        private const val WATCHDOG_TIMEOUT_MS = 45_000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Alarm received: ${intent.action}")
        val appContext = context.applicationContext
        val pendingResult = goAsync()

        val mainHandler = Handler(Looper.getMainLooper())
        mainHandler.post {
            runHeadlessTask(appContext, pendingResult)
        }
    }

    private fun runHeadlessTask(context: Context, pendingResult: PendingResult) {
        val loader = FlutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(context)
        }
        loader.ensureInitializationComplete(context, null)

        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(
            getCallbackHandle(context)
        )
        if (callbackInfo == null) {
            Log.e(TAG, "Could not find registered Dart callback handle — has the Dart side called registerHeadlessCallback() yet?")
            pendingResult.finish()
            return
        }

        val engine = FlutterEngine(context)
        var finished = false
        val watchdog = Handler(Looper.getMainLooper())
        val watchdogRunnable = Runnable {
            if (!finished) {
                Log.w(TAG, "Headless task watchdog timeout — tearing down engine anyway")
                finished = true
                try { engine.destroy() } catch (_: Exception) {}
                pendingResult.finish()
            }
        }
        watchdog.postDelayed(watchdogRunnable, WATCHDOG_TIMEOUT_MS)

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, HEADLESS_CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "headlessTaskComplete") {
                Log.d(TAG, "Headless task signaled completion")
                if (!finished) {
                    finished = true
                    watchdog.removeCallbacks(watchdogRunnable)
                    result.success(null)
                    // Give the engine a brief moment to flush logs/IO before destroying.
                    Handler(Looper.getMainLooper()).postDelayed({
                        try { engine.destroy() } catch (_: Exception) {}
                        pendingResult.finish()
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

    /**
     * The Dart side persists its registered callback handle via SharedPreferences
     * (written once at app startup — see HeadlessTaskPlugin on the Dart side).
     * We read it directly here to avoid depending on any plugin registration
     * order, since this receiver may run before MainActivity has ever launched.
     */
    private fun getCallbackHandle(context: Context): Long {
        val prefs = context.getSharedPreferences("headless_callback_prefs", Context.MODE_PRIVATE)
        return prefs.getLong("callback_handle", 0L)
    }
}