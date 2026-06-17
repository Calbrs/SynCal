package com.example.synccal

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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
        private const val SMS_CHANNEL = "com.example.synccal/sms"
        private const val TAG = "SmsGateway"
        private const val REQUEST_SMS_PERMISSIONS = 101
        private const val ENGINE_ID = "sync_cal_engine"
    }

    private lateinit var channel: MethodChannel
    private var permissionResult: MethodChannel.Result? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // Use the cached engine from Application
        return FlutterEngineCache.getInstance().get(ENGINE_ID)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
        // Give the channel to the status tracker so it can send updates
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
                else -> result.notImplemented()
            }
        }
    }

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

    private fun hasSmsPermissions(): Boolean {
        val send = ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
        val read = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
        return send == PackageManager.PERMISSION_GRANTED && read == PackageManager.PERMISSION_GRANTED
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        if (hasSmsPermissions()) {
            result.success(true)
            return
        }
        permissionResult = result
        val permissions = mutableListOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_PHONE_STATE
        )
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
            permissions.add(Manifest.permission.READ_SMS)
        }
        ActivityCompat.requestPermissions(this, permissions.toTypedArray(), REQUEST_SMS_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_SMS_PERMISSIONS) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

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