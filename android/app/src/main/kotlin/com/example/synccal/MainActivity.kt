package com.example.synccal

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {

    companion object {
        private const val SMS_CHANNEL = "com.example.synccal/sms"
        private const val TAG = "SmsGateway"
        private const val REQUEST_SMS_PERMISSIONS = 101
        private const val ACTION_SMS_SENT = "com.example.synccal.SMS_SENT"
        private const val ACTION_SMS_DELIVERED = "com.example.synccal.SMS_DELIVERED"
    }

    // Tracks status of every message: uuid -> { "sent": bool?, "delivered": bool?, ... }
    private val messageStatusMap = mutableMapOf<String, MutableMap<String, Any?>>()

    private lateinit var channel: MethodChannel
    private var permissionResult: MethodChannel.Result? = null

    // ── BroadcastReceiver: SMS sent ──────────────────────────────────────────
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
                SmsManager.RESULT_ERROR_GENERIC_FAILURE -> {
                    Log.e(TAG, "SMS send failed (generic): $msgId")
                    status["sent"] = false
                    status["sentError"] = "Generic failure"
                }
                SmsManager.RESULT_ERROR_NO_SERVICE -> {
                    status["sent"] = false
                    status["sentError"] = "No service"
                }
                SmsManager.RESULT_ERROR_NULL_PDU -> {
                    status["sent"] = false
                    status["sentError"] = "Null PDU"
                }
                SmsManager.RESULT_ERROR_RADIO_OFF -> {
                    status["sent"] = false
                    status["sentError"] = "Radio off"
                }
                else -> {
                    status["sent"] = false
                    status["sentError"] = "Unknown error: $resultCode"
                }
            }

            // Push the sent status update to Flutter via the channel
            runOnUiThread {
                channel.invokeMethod("onSmsStatusUpdate", buildStatusMap(msgId, status))
            }
        }
    }

    // ── BroadcastReceiver: SMS delivered ────────────────────────────────────
    private val smsDeliveredReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val msgId = intent.getStringExtra("msgId") ?: return
            val status = messageStatusMap.getOrPut(msgId) { mutableMapOf() }

            when (resultCode) {
                Activity.RESULT_OK -> {
                    Log.d(TAG, "SMS delivered OK: $msgId")
                    status["delivered"] = true
                    status["deliveryError"] = null
                }
                Activity.RESULT_CANCELED -> {
                    status["delivered"] = false
                    status["deliveryError"] = "Not delivered"
                }
                else -> {
                    status["delivered"] = false
                    status["deliveryError"] = "Delivery error: $resultCode"
                }
            }

            // Push a status update to Flutter via the channel
            runOnUiThread {
                channel.invokeMethod("onSmsStatusUpdate", buildStatusMap(msgId, status))
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {

                // ── Check / request SMS permissions ──────────────────────
                "requestSmsPermissions" -> {
                    handleRequestPermissions(result)
                }

                // ── Check permission status only ──────────────────────────
                "checkSmsPermissions" -> {
                    result.success(hasSmsPermissions())
                }

                // ── Get list of available SIM cards ──────────────────────
                "getSimCards" -> {
                    result.success(getSimCards())
                }

                // ── Send SMS ──────────────────────────────────────────────
                // Required args: "to" (String), "message" (String)
                // Optional args: "simSlot" (Int, 0-based index; -1 = default)
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

                // ── Poll status of a previously sent message ──────────────
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

                else -> result.notImplemented()
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    override fun onStart() {
        super.onStart()
        // Register broadcast receivers
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsSentReceiver, IntentFilter(ACTION_SMS_SENT),
                Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(smsDeliveredReceiver, IntentFilter(ACTION_SMS_DELIVERED),
                Context.RECEIVER_NOT_EXPORTED)
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
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Receiver not registered: ${e.message}")
        }
    }

    // ── Permission helpers ───────────────────────────────────────────────────
    private fun hasSmsPermissions(): Boolean {
        val send = ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
        val read = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
        return send == PackageManager.PERMISSION_GRANTED &&
               read == PackageManager.PERMISSION_GRANTED
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
        // READ_SMS needed on some devices to track delivery
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS)
            != PackageManager.PERMISSION_GRANTED) {
            permissions.add(Manifest.permission.READ_SMS)
        }
        ActivityCompat.requestPermissions(this, permissions.toTypedArray(), REQUEST_SMS_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_SMS_PERMISSIONS) {
            val granted = grantResults.isNotEmpty() &&
                          grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    // ── SIM card detection ───────────────────────────────────────────────────
    private fun getSimCards(): List<Map<String, Any>> {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED) {
            return emptyList()
        }

        return try {
            val subscriptionManager =
                getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager

            val subs: List<SubscriptionInfo> =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    subscriptionManager.activeSubscriptionInfoList ?: emptyList()
                } else {
                    emptyList()
                }

            subs.mapIndexed { index, info ->
                mapOf(
                    "slotIndex"       to index,
                    "subscriptionId"  to info.subscriptionId,
                    "displayName"     to (info.displayName?.toString() ?: "SIM ${index + 1}"),
                    "carrierName"     to (info.carrierName?.toString() ?: "Unknown"),
                    "number"          to (info.number ?: ""),
                    "simSlotIndex"    to info.simSlotIndex,
                    "countryIso"      to info.countryIso
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching SIM cards: ${e.message}")
            emptyList()
        }
    }

    // ── SMS sending ──────────────────────────────────────────────────────────
    private fun sendSms(
        to: String,
        message: String,
        simSlot: Int,
        result: MethodChannel.Result
    ) {
        val msgId = UUID.randomUUID().toString()

        // Initialise status entry
        messageStatusMap[msgId] = mutableMapOf(
            "sent"          to null,
            "delivered"     to null,
            "sentError"     to null,
            "deliveryError" to null
        )

        // PendingIntent: fired when SMS is sent
        val sentIntent = Intent(ACTION_SMS_SENT).apply {
            putExtra("msgId", msgId)
        }
        val sentPI = PendingIntent.getBroadcast(
            this, msgId.hashCode(), sentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // PendingIntent: fired when SMS is delivered to handset
        val deliveredIntent = Intent(ACTION_SMS_DELIVERED).apply {
            putExtra("msgId", msgId)
        }
        val deliveredPI = PendingIntent.getBroadcast(
            this, (msgId.hashCode() + 1), deliveredIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            val smsManager = getSmsManagerForSlot(simSlot)

            // Split long messages automatically
            val parts = smsManager.divideMessage(message)

            if (parts.size == 1) {
                smsManager.sendTextMessage(to, null, message, sentPI, deliveredPI)
            } else {
                val sentPIs    = ArrayList<PendingIntent>(parts.size).apply { repeat(parts.size) { add(sentPI) } }
                val delivPIs   = ArrayList<PendingIntent>(parts.size).apply { repeat(parts.size) { add(deliveredPI) } }
                smsManager.sendMultipartTextMessage(to, null, parts, sentPIs, delivPIs)
            }

            // Resolve immediately — Flutter polls getSmsStatus or listens to onSmsStatusUpdate
            result.success(mapOf(
                "msgId"   to msgId,
                "status"  to "queued",
                "simSlot" to simSlot
            ))

        } catch (e: Exception) {
            Log.e(TAG, "sendSms error: ${e.message}")
            messageStatusMap.remove(msgId)
            result.error("SEND_FAILED", e.message, null)
        }
    }

    // ── Pick the right SmsManager for the chosen SIM ─────────────────────────
    @Suppress("DEPRECATION")
    private fun getSmsManagerForSlot(simSlot: Int): SmsManager {
        if (simSlot < 0) {
            // Use the default SIM
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                applicationContext.getSystemService(SmsManager::class.java)
            } else {
                SmsManager.getDefault()
            }
        }

        // Resolve subscription ID from slot index
        return try {
            val subscriptionManager =
                getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager

            val subs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                subscriptionManager.activeSubscriptionInfoList ?: emptyList()
            } else {
                emptyList()
            }

            val sub = subs.getOrNull(simSlot)
            if (sub != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    applicationContext.getSystemService(SmsManager::class.java)
                        .createForSubscriptionId(sub.subscriptionId)
                } else {
                    SmsManager.getSmsManagerForSubscriptionId(sub.subscriptionId)
                }
            } else {
                // Slot not found, fall back to default
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    applicationContext.getSystemService(SmsManager::class.java)
                } else {
                    SmsManager.getDefault()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "getSmsManagerForSlot error: ${e.message}")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                applicationContext.getSystemService(SmsManager::class.java)
            } else {
                SmsManager.getDefault()
            }
        }
    }

    // ── Build the status map returned to Flutter ─────────────────────────────
    private fun buildStatusMap(msgId: String, status: Map<String, Any?>): Map<String, Any?> {
        return mapOf(
            "msgId"         to msgId,
            "sent"          to status["sent"],
            "delivered"     to status["delivered"],
            "sentError"     to status["sentError"],
            "deliveryError" to status["deliveryError"]
        )
    }
}