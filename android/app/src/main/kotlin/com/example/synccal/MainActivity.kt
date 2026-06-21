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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
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
    private lateinit var handler: SmsMethodCallHandler
    private var permissionResult: MethodChannel.Result? = null
    private var installPermissionResult: MethodChannel.Result? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(ENGINE_ID)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
        SmsStatusTracker.setChannel(channel)
        
        handler = SmsMethodCallHandler(applicationContext, this)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSmsPermissions" -> handleRequestPermissions(result)
                "installApk" -> installApk(call.argument<String>("filePath") ?: "", result)
                "canInstallPackages" -> result.success(canInstallPackages())
                "requestInstallPermission" -> requestInstallPermission(result)
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
                else -> {
                    handler.onMethodCall(call, result)
                }
            }
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