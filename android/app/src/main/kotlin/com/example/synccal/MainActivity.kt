package com.example.synccal

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {

    companion object {
        private const val SMS_CHANNEL = "com.example.synccal/sms"
        private const val TAG = "SmsGateway"
        private const val REQUEST_SMS_PERMISSIONS = 101
        private const val ACTION_SMS_SENT = "com.example.synccal.SMS_SENT"
        private const val ACTION_SMS_DELIVERED = "com.example.synccal.SMS_DELIVERED"
    }

    private val messageStatusMap = mutableMapOf<String, MutableMap<String, Any?>>()
    private lateinit var channel: MethodChannel
    private var permissionResult: MethodChannel.Result? = null

    // Broadcast Receivers (unchanged)
    private val smsSentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val msgId = intent.getStringExtra("msgId") ?: return
            val status = messageStatusMap.getOrPut(msgId) { mutableMapOf() }
            when (resultCode) {
                Activity.RESULT_OK -> {
                    Log.d(TAG, "SMS sent OK: $msgId")
                    status["sent"] = true
                    status["sentError"] = null
                }
                else -> {
                    status["sent"] = false
                    status["sentError"] = "Error code: $resultCode"
                }
            }
            runOnUiThread {
                channel.invokeMethod("onSmsStatusUpdate", buildStatusMap(msgId, status))
            }
        }
    }

    private val smsDeliveredReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val msgId = intent.getStringExtra("msgId") ?: return
            val status = messageStatusMap.getOrPut(msgId) { mutableMapOf() }
            when (resultCode) {
                Activity.RESULT_OK -> {
                    Log.d(TAG, "SMS delivered OK: $msgId")
                    status["delivered"] = true
                }
                else -> {
                    status["delivered"] = false
                }
            }
            runOnUiThread {
                channel.invokeMethod("onSmsStatusUpdate", buildStatusMap(msgId, status))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSmsPermissions" -> handleRequestPermissions(result)
                "checkSmsPermissions" -> result.success(hasSmsPermissions())
                "getSimCards" -> result.success(getSimCards())
                "sendSms" -> {
                    val to = call.argument<String>("to")
                    val message = call.argument<String>("message")
                    val simSlot = call.argument<Int>("simSlot") ?: -1
                    if (to.isNullOrBlank() || message.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "to and message are required", null)
                        return@setMethodCallHandler
                    }
                    if (!hasSmsPermissions()) {
                        result.error("NO_PERMISSION", "SMS permission not granted", null)
                        return@setMethodCallHandler
                    }
                    sendSms(to, message, simSlot, result)
                }
                "getSmsStatus" -> {
                    val msgId = call.argument<String>("msgId")
                    if (msgId == null) {
                        result.error("INVALID_ARGS", "msgId is required", null)
                        return@setMethodCallHandler
                    }
                    val status = messageStatusMap[msgId]
                    if (status == null) {
                        result.error("NOT_FOUND", "No message with id $msgId", null)
                    } else {
                        result.success(buildStatusMap(msgId, status))
                    }
                }
                // ── NEW: Install APK ─────────────────────────────────────
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "filePath is required", null)
                        return@setMethodCallHandler
                    }
                    installApk(filePath, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ==================== NEW: APK Installation ====================

    private fun installApk(filePath: String, result: MethodChannel.Result) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "APK file not found at: $filePath", null)
                return
            }

            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(
                    this,
                    "${packageName}.fileprovider",  // Must match AndroidManifest
                    file
                )
            } else {
                Uri.fromFile(file)
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }

            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Install APK failed: ${e.message}")
            result.error("INSTALL_FAILED", e.message, null)
        }
    }

    // ==================== Rest of your existing code (unchanged) ====================

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsSentReceiver, IntentFilter(ACTION_SMS_SENT), Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(smsDeliveredReceiver, IntentFilter(ACTION_SMS_DELIVERED), Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(smsSentReceiver, IntentFilter(ACTION_SMS_SENT))
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(smsDeliveredReceiver, IntentFilter(ACTION_SMS_DELIVERED))
        }
    }

    override fun onStop() {
        super.onStop()
        try {
            unregisterReceiver(smsSentReceiver)
            unregisterReceiver(smsDeliveredReceiver)
        } catch (e: Exception) {}
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

    private fun sendSms(to: String, message: String, simSlot: Int, result: MethodChannel.Result) {
        val msgId = UUID.randomUUID().toString()
        messageStatusMap[msgId] = mutableMapOf("sent" to null, "delivered" to null, "sentError" to null, "deliveryError" to null)

        val sentIntent = Intent(ACTION_SMS_SENT).apply { putExtra("msgId", msgId) }
        val sentPI = PendingIntent.getBroadcast(this, msgId.hashCode(), sentIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val deliveredIntent = Intent(ACTION_SMS_DELIVERED).apply { putExtra("msgId", msgId) }
        val deliveredPI = PendingIntent.getBroadcast(this, msgId.hashCode() + 1, deliveredIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

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
            messageStatusMap.remove(msgId)
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

    private fun buildStatusMap(msgId: String, status: Map<String, Any?>): Map<String, Any?> {
        return mapOf(
            "msgId" to msgId,
            "sent" to status["sent"],
            "delivered" to status["delivered"],
            "sentError" to status["sentError"],
            "deliveryError" to status["deliveryError"]
        )
    }
}