package com.example.SynCal

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

object SmsStatusTracker {
    const val ACTION_SMS_SENT = "com.example.SynCal.SMS_SENT"
    const val ACTION_SMS_DELIVERED = "com.example.SynCal.SMS_DELIVERED"
    private const val TAG = "SmsStatusTracker"

    private var channel: MethodChannel? = null
    private val messageStatusMap = mutableMapOf<String, MutableMap<String, Any?>>()
    private var receiversRegistered = false
    private lateinit var context: Context

    fun init(context: Context) {
        this.context = context.applicationContext
        registerReceivers()
    }

    fun setChannel(channel: MethodChannel) {
        this.channel = channel
    }

    private val sentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val msgId = intent.getStringExtra("msgId") ?: return
            val status = messageStatusMap.getOrPut(msgId) { mutableMapOf() }
            when (resultCode) {
                Activity.RESULT_OK -> {
                    status["sent"] = true
                    status["sentError"] = null
                }
                else -> {
                    status["sent"] = false
                    status["sentError"] = "Error code: $resultCode"
                }
            }
            notifyFlutter(msgId, status)
        }
    }

    private val deliveredReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val msgId = intent.getStringExtra("msgId") ?: return
            val status = messageStatusMap.getOrPut(msgId) { mutableMapOf() }
            when (resultCode) {
                Activity.RESULT_OK -> status["delivered"] = true
                else -> status["delivered"] = false
            }
            notifyFlutter(msgId, status)
        }
    }

    private fun registerReceivers() {
        if (receiversRegistered) return
        try {
            val sentFilter = IntentFilter(ACTION_SMS_SENT)
            val deliveredFilter = IntentFilter(ACTION_SMS_DELIVERED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.registerReceiver(
                    context,
                    sentReceiver,
                    sentFilter,
                    ContextCompat.RECEIVER_NOT_EXPORTED
                )
                ContextCompat.registerReceiver(
                    context,
                    deliveredReceiver,
                    deliveredFilter,
                    ContextCompat.RECEIVER_NOT_EXPORTED
                )
            } else {
                context.registerReceiver(sentReceiver, sentFilter)
                context.registerReceiver(deliveredReceiver, deliveredFilter)
            }
            receiversRegistered = true
            Log.d(TAG, "SMS receivers registered")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register receivers", e)
        }
    }

    private fun notifyFlutter(msgId: String, status: Map<String, Any?>) {
        channel?.invokeMethod("onSmsStatusUpdate", buildStatusMap(msgId, status))
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

    fun getStatus(msgId: String): Map<String, Any?>? {
        return messageStatusMap[msgId]?.let { buildStatusMap(msgId, it) }
    }

    fun putStatus(msgId: String, status: MutableMap<String, Any?>) {
        messageStatusMap[msgId] = status
    }

    fun removeStatus(msgId: String) {
        messageStatusMap.remove(msgId)
    }
}