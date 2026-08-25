package com.convene.convene

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.convene.convene/screen_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Convene"
                        val text = call.argument<String>("text") ?: "Meeting is active in the background"
                        val intent = Intent(this, ScreenShareForegroundService::class.java).apply {
                            putExtra("title", title)
                            putExtra("text", text)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        e.printStackTrace()
                        result.success(null)
                    }
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, ScreenShareForegroundService::class.java))
                        result.success(null)
                    } catch (e: Exception) {
                        e.printStackTrace()
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
