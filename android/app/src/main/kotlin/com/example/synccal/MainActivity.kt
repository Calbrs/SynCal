package com.example.SynCal

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {

    companion object {
        private const val SMS_CHANNEL = "com.example.SynCal/sms"
        private const val TAG = "SmsGateway"
        private const val REQUEST_SMS_PERMISSIONS = 101
        private const val REQUEST_INSTALL_PERMISSION = 102
        private const val ENGINE_ID = "sync_cal_engine"
    }

    private lateinit var channel: MethodChannel
    private var permissionResult: MethodChannel.Result? = null
    private var installPermissionResult: MethodChannel.Result? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(ENGINE_ID)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
        SmsStatusTracker.setChannel(channel)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSmsPermissions" -> handleRequestPermissions(result)
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
                        return@setMethodCallHandler
                    }
                    val status = SmsStatusTracker.getStatus(msgId)
                    if (status == null) {
                        result.error("NOT_FOUND", "No message with id $msgId", null)
                    } else {
                        result.success(status)
                    }
                }
                "installApk" -> installApk(call.argument<String>("filePath") ?: "", result)
                "canInstallPackages" -> {
                    result.success(canInstallPackages())
                }
                "requestInstallPermission" -> {
                    requestInstallPermission(result)
                }
                "startForegroundService" -> {
                    val intent = Intent(this, SmsForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopForegroundService" -> {
                    stopService(Intent(this, SmsForegroundService::class.java))
                    result.success(null)
                }
                "scheduleAlarm" -> {
                    val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
                    if (triggerAtMillis == null) {
                        result.error("INVALID_ARGS", "triggerAtMillis is required", null)
                        return@setMethodCallHandler
                    }
                    AlarmScheduler.scheduleAt(applicationContext, triggerAtMillis)
                    AlarmScheduler.scheduleSafetyNet(applicationContext)
                    result.success(null)
                }
                "cancelAlarm" -> {
                    AlarmScheduler.cancel(applicationContext)
                    result.success(null)
                }
                "canScheduleExactAlarms" -> {
                    result.success(AlarmScheduler.canScheduleExact(applicationContext))
                }
                "requestExactAlarmPermission" -> {
                    requestExactAlarmPermission(result)
                }
                "saveHeadlessCallbackHandle" -> {
                    val handle = call.argument<Number>("handle")?.toLong()
                    if (handle == null) {
                        result.error("INVALID_ARGS", "handle is required", null)
                        return@setMethodCallHandler
                    }
                    val prefs = applicationContext.getSharedPreferences(
                        "headless_callback_prefs", Context.MODE_PRIVATE
                    )
                    prefs.edit().putLong("callback_handle", handle).apply()
                    result.success(null)
                }

                // ---- Battery Optimization ----
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations(result)
                }

                // ---- OEM Autostart (Transsion/XOS + other vendors) ----
                "openAutostartSettings" -> {
                    openAutostartSettings(result)
                }

                else -> result.notImplemented()
            }
        }
    }

    // ---- Exact alarm permission ----

    private fun requestExactAlarmPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (AlarmScheduler.canScheduleExact(applicationContext)) {
                result.success(true)
                return
            }
            try {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Could not open exact alarm settings: ${e.message}")
            }
            // We can't get a synchronous result from this settings screen;
            // Dart should re-check via canScheduleExactAlarms after resume.
            result.success(false)
        } else {
            result.success(true)
        }
    }

    // ---- Battery Optimization ----

    /**
     * Returns true if the app is already whitelisted from battery optimizations.
     * On Android 6+ (API 23+) this uses the standard PowerManager API.
     * On older versions there are no battery optimizations to worry about, so we return true.
     */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    /**
     * Opens the standard Android "Ignore battery optimizations" request dialog for this app.
     *
     * Requires  <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
     * in AndroidManifest.xml.
     *
     * Note: Google Play policies restrict this permission for most apps; if your app is not
     * exempt (e.g. SMS gateway / alarm apps typically are), use ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
     * as a fallback which opens the general list so the user can find and whitelist the app manually.
     *
     * Result is returned immediately as false because we cannot synchronously await the
     * system dialog. Dart side should re-check via isIgnoringBatteryOptimizations after resume.
     */
    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        if (isIgnoringBatteryOptimizations()) {
            result.success(true)
            return
        }
        try {
            // Direct request dialog — requires REQUEST_IGNORE_BATTERY_OPTIMIZATIONS permission
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Direct battery opt request failed, falling back to settings list: ${e.message}")
            try {
                // Fallback: open the general battery optimization settings list
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (e2: Exception) {
                Log.e(TAG, "Could not open battery optimization settings: ${e2.message}")
            }
        }
        // Dart must re-check on resume
        result.success(false)
    }

    // ---- OEM Autostart Settings ----

    /**
     * Attempts to open the OEM-specific "Autostart" / "Background activity" settings screen
     * so the user can manually allow the app to start on boot and run in the background.
     *
     * This is NOT a standard Android API — every OEM uses a different Intent. We try them in
     * order of specificity and fall back to the standard App Info screen if none resolves.
     *
     * Covered OEMs:
     *   • Transsion (Infinix / Tecno / Itel) — XOS "Phone Manager" autostart list
     *   • Xiaomi (MIUI) — Security app autostart
     *   • Huawei / Honor (EMUI) — Protected apps
     *   • Oppo (ColorOS) — Auto-start management
     *   • Vivo (FuntouchOS / OriginOS) — i-Manager autostart
     *   • Samsung (One UI) — Device care / battery autostart (≥ Android 10)
     *   • OnePlus (OxygenOS) — Battery optimization autostart
     *   • Letv / LeEco
     *   • Asus (ZenUI)
     *
     * Returns: true if a specific OEM screen was opened, false if only the generic App Info
     *          screen was available (or if nothing could be opened at all).
     */
    private fun openAutostartSettings(result: MethodChannel.Result) {
        // Ordered list of (action, component-package, component-class) triples.
        // component-package / component-class may be null for action-only intents.
        data class AutostartIntent(
            val action: String,
            val pkg: String? = null,
            val cls: String? = null,
            val extraKey: String? = null,
            val extraValue: String? = null
        )

        val candidates = listOf(
            // --- Transsion (Infinix / Tecno / Itel) XOS ---
            AutostartIntent(
                action = "com.transsion.phonemanager.autostart.settings",
                pkg = "com.transsion.phonemanager",
                cls = "com.transsion.phonemanager.autostart.AutoStartActivity"
            ),
            // XOS alternative entry (some firmware versions)
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.transsion.phonemanager",
                cls = "com.transsion.phonemanager.MainActivity"
            ),
            // --- Xiaomi / MIUI ---
            AutostartIntent(
                action = "miui.intent.action.APP_PERM_EDITOR",
                pkg = "com.miui.securitycenter",
                cls = "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            // --- Huawei / Honor (EMUI) ---
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
            // --- Oppo (ColorOS) ---
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
            // --- Vivo (FuntouchOS / OriginOS) ---
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
            // --- Samsung (One UI ≥ Android 10) ---
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.samsung.android.lool",
                cls = "com.samsung.android.sm.battery.ui.BatteryActivity"
            ),
            // --- OnePlus (OxygenOS) ---
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.oneplus.security",
                cls = "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            ),
            // --- Letv / LeEco ---
            AutostartIntent(
                action = Intent.ACTION_MAIN,
                pkg = "com.letv.android.letvsafe",
                cls = "com.letv.android.letvsafe.AutobootManageActivity"
            ),
            // --- Asus (ZenUI) ---
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

                // Only launch if the activity actually resolves on this device
                val resolves = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null
                if (resolves) {
                    startActivity(intent)
                    Log.d(TAG, "Opened autostart settings via: ${candidate.pkg}/${candidate.cls}")
                    result.success(true)
                    return
                }
            } catch (e: Exception) {
                Log.d(TAG, "Autostart candidate failed (${candidate.pkg}/${candidate.cls}): ${e.message}")
            }
        }

        // --- Final fallback: standard App Info screen ---
        Log.w(TAG, "No OEM autostart screen found; falling back to App Info settings")
        try {
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallback)
            result.success(false) // false = only generic screen was available
        } catch (e: Exception) {
            Log.e(TAG, "Could not open any settings screen: ${e.message}")
            result.error("SETTINGS_UNAVAILABLE", "Could not open any settings screen: ${e.message}", null)
        }
    }

    // ---- SMS Sending ----

    private fun sendSms(to: String, message: String, simSlot: Int, result: MethodChannel.Result) {
        val msgId = UUID.randomUUID().toString()
        val statusMap = mutableMapOf<String, Any?>(
            "sent" to null,
            "delivered" to null,
            "sentError" to null,
            "deliveryError" to null
        )
        SmsStatusTracker.putStatus(msgId, statusMap)

        val sentIntent = Intent(SmsStatusTracker.ACTION_SMS_SENT).apply { putExtra("msgId", msgId) }
        val sentPI = PendingIntent.getBroadcast(
            this,
            msgId.hashCode(),
            sentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val deliveredIntent = Intent(SmsStatusTracker.ACTION_SMS_DELIVERED).apply { putExtra("msgId", msgId) }
        val deliveredPI = PendingIntent.getBroadcast(
            this,
            msgId.hashCode() + 1,
            deliveredIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            val smsManager = getSmsManagerForSlot(simSlot)
            val parts = smsManager.divideMessage(message)

            if (parts.size == 1) {
                smsManager.sendTextMessage(to, null, message, sentPI, deliveredPI)
            } else {
                val sentPIs = ArrayList<PendingIntent>(parts.size).apply { repeat(parts.size) { add(sentPI) } }
                val delivPIs = ArrayList<PendingIntent>(parts.size).apply { repeat(parts.size) { add(deliveredPI) } }
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
                applicationContext.getSystemService(SmsManager::class.java)
            } else SmsManager.getDefault()
        }

        return try {
            val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val subs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                subscriptionManager.activeSubscriptionInfoList ?: emptyList()
            } else emptyList()

            val sub = subs.getOrNull(simSlot)
            if (sub != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                applicationContext.getSystemService(SmsManager::class.java).createForSubscriptionId(sub.subscriptionId)
            } else if (sub != null) {
                SmsManager.getSmsManagerForSubscriptionId(sub.subscriptionId)
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    applicationContext.getSystemService(SmsManager::class.java)
                } else SmsManager.getDefault()
            }
        } catch (e: Exception) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                applicationContext.getSystemService(SmsManager::class.java)
            } else SmsManager.getDefault()
        }
    }

    // ---- Permissions ----

    private fun hasSmsPermissions(): Boolean {
        val send = ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
        val readPhoneState = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
        val readContacts = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS)
        return send == PackageManager.PERMISSION_GRANTED &&
                readPhoneState == PackageManager.PERMISSION_GRANTED &&
                readContacts == PackageManager.PERMISSION_GRANTED
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        if (hasSmsPermissions()) {
            result.success(true)
            return
        }
        permissionResult = result
        val permissions = mutableListOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CONTACTS
        )
        ActivityCompat.requestPermissions(this, permissions.toTypedArray(), REQUEST_SMS_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_SMS_PERMISSIONS -> {
                val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                permissionResult?.success(granted)
                permissionResult = null
            }
            REQUEST_INSTALL_PERMISSION -> {
                val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                installPermissionResult?.success(granted)
                installPermissionResult = null
            }
        }
    }

    // ---- SIM cards ----

    private fun getSimCards(): List<Map<String, Any>> {
        if (!hasSmsPermissions()) return emptyList()
        return try {
            val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
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

    // ---- Self‑update ----

    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun requestInstallPermission(result: MethodChannel.Result) {
        if (canInstallPackages()) {
            result.success(true)
            return
        }
        installPermissionResult = result
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
        startActivityForResult(intent, REQUEST_INSTALL_PERMISSION)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_INSTALL_PERMISSION) {
            val granted = canInstallPackages()
            installPermissionResult?.success(granted)
            installPermissionResult = null
        }
    }

    private fun installApk(filePath: String, result: MethodChannel.Result) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "APK file not found at: $filePath", null)
                return
            }

            val uri: Uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )

            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
            }

            startActivity(intent)
            result.success("success")
        } catch (e: Exception) {
            Log.e(TAG, "Install APK failed", e)
            result.error("INSTALL_FAILED", e.message ?: "Unknown error", null)
        }
    }
}