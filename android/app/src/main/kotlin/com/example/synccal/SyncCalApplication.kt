package com.example.SynCal

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class SynCalApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        // Pre-warm FlutterEngine
        val flutterEngine = FlutterEngine(this)
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put("sync_cal_engine", flutterEngine)

        // Init SMS status tracker (registers receivers globally)
        SmsStatusTracker.init(this)
    }
}