package com.example.SynCal

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.UUID

class SmsMethodCallHandler(
    private val context: Context,
    private var activity: Activity? = null
) : MethodCallHandler {

    companion object {
        private const val TAG = "SmsMethodCallHandler"
    }

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "checkSmsPermissions" -> result.success(hasSmsPermissions())
            "getSimCards" -> result.success(getSimCards())
            "sendSms" -> sendSms(
                call.argument<String>("to") ?: "",
                call.argument<String>("message") ?: "",
                call.argument<Int>("simSlot") ?: -1,
                result
            )
            "getSmsStatus" -> {
                val msgId = call.argument<String>("msgId")
                if (msgId == null) {
                    result.error("INVALID_ARGS", "msgId is required", null)
                    return
                }
                val status = SmsStatusTracker.getStatus(msgId)
                if (status == null) {
                    result.error("NOT_FOUND", "No message with id $msgId", null)
                } else {
                    result.success(status)
                }
            }
            "startForegroundService" -> {
                val intent = Intent(context, SmsForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                result.success(null)
            }
            "stopForegroundService" -> {
                context.stopService(Intent(context, SmsForegroundService::class.java))
                result.success(null)
            }
            "scheduleAlarm" -> {
                val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
                if (triggerAtMillis == null) {
                    result.error("INVALID_ARGS", "triggerAtMillis is required", null)
                    return
                }
                AlarmScheduler.scheduleAt(context, triggerAtMillis)
                AlarmScheduler.scheduleSafetyNet(context)
                result.success(null)
            }
            "cancelAlarm" -> {
                AlarmScheduler.cancel(context)
                result.success(null)
            }
            "canScheduleExactAlarms" -> {
                result.success(AlarmScheduler.canScheduleExact(context))
            }
            "requestExactAlarmPermission" -> {
                requestExactAlarmPermission(result)
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(isIgnoringBatteryOptimizations())
            }
            "requestIgnoreBatteryOptimizations" -> {
                requestIgnoreBatteryOptimizations(result)
            }
            "openAutostartSettings" -> {
                openAutostartSettings(result)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasSmsPermissions(): Boolean {
        val send = ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS)
        val readPhoneState = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE)
        val readContacts = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS)
        return send == PackageManager.PERMISSION_GRANTED &&
                readPhoneState == PackageManager.PERMISSION_GRANTED &&
                readContacts == PackageManager.PERMISSION_GRANTED
    }

    private fun getSimCards(): List<Map<String, Any>> {
        if (!hasSmsPermissions()) return emptyList()
        return try {
            val subscriptionManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val subs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                subscriptionManager.activeSubscriptionInfoList ?: emptyList()
            } else emptyList()

            subs.mapIndexed { index, info ->
                mapOf(
                    "slotIndex" to index,
                    "subscriptionId" to info.subscriptionId,
                    "displayName" to (info.displayName?.toString() ?: "SIM ${index + 1}"),
                    "carrierName" to (info.carrierName?.toString() ?: "Unknown"),
                    "number" to (info.number ?: ""),
                    "simSlotIndex" to info.simSlotIndex,
                    "countryIso" to info.countryIso
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching SIM cards: ${e.message}")
            emptyList()
        }
    }

    private fun sendSms(to: String, message: String, simSlot: Int, result: Result) {
        val msgId = UUID.randomUUID().toString()
        val statusMap = mutableMapOf<String, Any?>(
            "sent" to null,
            "delivered" to null,
            "sentError" to null,
            "deliveryError" to null
        )
        SmsStatusTracker.putStatus(msgId, statusMap)

        val sentIntent = Intent(SmsStatusTracker.ACTION_SMS_SENT).apply { putExtra("msgId", msgId) }
        val sentPI = android.app.PendingIntent.getBroadcast(
            context,
            msgId.hashCode(),
            sentIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val deliveredIntent = Intent(SmsStatusTracker.ACTION_SMS_DELIVERED).apply { putExtra("msgId", msgId) }
        val deliveredPI = android.app.PendingIntent.getBroadcast(
            context,
            msgId.hashCode() + 1,
            deliveredIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        try {
            val smsManager = getSmsManagerForSlot(simSlot)
            val parts = smsManager.divideMessage(message)

            if (parts.size == 1) {
                smsManager.sendTextMessage(to, null, message, sentPI, deliveredPI)
            } else {
                val sentPIs = ArrayList<android.app.PendingIntent>(parts.size).apply { repeat(parts.size) { add(sentPI) } }
                val delivPIs = ArrayList<android.app.PendingIntent>(parts.size).apply { repeat(parts.size) { add(deliveredPI) } }
                smsManager.sendMultipartTextMessage(to, null, parts, sentPIs, delivPIs)
            }

            result.success(mapOf("msgId" to msgId, "status" to "queued"))
        } catch (e: Exception) {
            Log.e(TAG, "sendSms error: ${e.message}")
            SmsStatusTracker.removeStatus(msgId)
            result.error("SEND_FAILED", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun getSmsManagerForSlot(simSlot: Int): SmsManager {
        if (simSlot < 0) {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else SmsManager.getDefault()
        }

        return try {
            val subscriptionManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val subs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                subscriptionManager.activeSubscriptionInfoList ?: emptyList()
            } else emptyList()

            val sub = subs.getOrNull(simSlot)
            if (sub != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java).createForSubscriptionId(sub.subscriptionId)
            } else if (sub != null) {
                SmsManager.getSmsManagerForSubscriptionId(sub.subscriptionId)
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(SmsManager::class.java)
                } else SmsManager.getDefault()
            }
        } catch (e: Exception) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else SmsManager.getDefault()
        }
    }

    private fun requestExactAlarmPermission(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.success(false)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (AlarmScheduler.canScheduleExact(context)) {
                result.success(true)
                return
            }
            try {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:${context.packageName}")
                }
                currentActivity.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Could not open exact alarm settings: ${e.message}")
            }
            result.success(false)
        } else {
            result.success(true)
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(context.packageName)
        } else {
            true
        }
    }

    private fun requestIgnoreBatteryOptimizations(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.success(false)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        if (isIgnoringBatteryOptimizations()) {
            result.success(true)
            return
        }
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
            currentActivity.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Direct battery opt request failed, falling back to settings list: ${e.message}")
            try {
                currentActivity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (e2: Exception) {
                Log.e(TAG, "Could not open battery optimization settings: ${e2.message}")
            }
        }
        result.success(false)
    }

    private fun openAutostartSettings(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.success(false)
            return
        }

        data class AutostartIntent(
            val action: String,
            val pkg: String? = null,
            val cls: String? = null,
            val extraKey: String? = null,
            val extraValue: String? = null
        )

        val candidates = listOf(
            AutostartIntent(
                action = "com.transsion.phonemanager.autostart.settings",
                pkg = "com.transsion.phonemanager",
                cls = "com.transsion.phonemanager.autostart.AutoStartActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.transsion.phonemanager",
                cls = "com.transsion.phonemanager.MainActivity"
            ),
            AutostartIntent(
                action = "miui.intent.action.APP_PERM_EDITOR",
                pkg = "com.miui.securitycenter",
                cls = "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.huawei.systemmanager",
                cls = "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.huawei.systemmanager",
                cls = "com.huawei.systemmanager.optimize.process.ProtectActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.coloros.safecenter",
                cls = "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.oppo.safe",
                cls = "com.oppo.safe.permission.startup.StartupAppListActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.vivo.permissionmanager",
                cls = "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.iqoo.secure",
                cls = "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.samsung.android.lool",
                cls = "com.samsung.android.sm.battery.ui.BatteryActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.oneplus.security",
                cls = "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.letv.android.letvsafe",
                cls = "com.letv.android.letvsafe.AutobootManageActivity"
            ),
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.asus.mobilemanager",
                cls = "com.asus.mobilemanager.autostart.AutostartSettings"
            )
        )

        for (candidate in candidates) {
            try {
                val intent = Intent(candidate.action).apply {
                    if (candidate.pkg != null && candidate.cls != null) {
                        component = ComponentName(candidate.pkg, candidate.cls)
                    }
                    if (candidate.extraKey != null && candidate.extraValue != null) {
                        putExtra(candidate.extraKey, candidate.extraValue)
                    }
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }

                val resolves = context.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null
                if (resolves) {
                    currentActivity.startActivity(intent)
                    Log.d(TAG, "Opened autostart settings via: ${candidate.pkg}/${candidate.cls}")
                    result.success(true)
                    return
                }
            } catch (e: Exception) {
                Log.d(TAG, "Autostart candidate failed (${candidate.pkg}/${candidate.cls}): ${e.message}")
            }
        }

        Log.w(TAG, "No OEM autostart screen found; falling back to App Info settings")
        try {
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            currentActivity.startActivity(fallback)
            result.success(false)
        } catch (e: Exception) {
            Log.e(TAG, "Could not open any settings screen: ${e.message}")
            result.error("SETTINGS_UNAVAILABLE", "Could not open any settings screen: ${e.message}", null)
        }
    }
}
