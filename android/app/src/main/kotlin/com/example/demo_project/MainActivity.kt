package com.mostafizur.expense.tracker

import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreenForAlarm(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        showOverLockScreenForAlarm(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "messbook/task_alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> {
                        val allowed = if (Build.VERSION.SDK_INT >= 34) {
                            getSystemService(NotificationManager::class.java)
                                .canUseFullScreenIntent()
                        } else {
                            true
                        }
                        result.success(allowed)
                    }
                    "releaseLockScreen" -> {
                        setOverLockScreen(false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// A task alarm's full-screen intent — or a tap on one — lands here with
    /// the plugin's SELECT_NOTIFICATION action and the alarm's payload. Only
    /// then is the activity let over the lock screen and the screen woken, so
    /// the alarm screen comes up the way the clock's does; the rest of the
    /// app never shows without an unlock. The Dart side hands it back through
    /// `releaseLockScreen` once the alarm is dealt with.
    private fun showOverLockScreenForAlarm(intent: Intent?) {
        if (intent?.action != "SELECT_NOTIFICATION") return
        val payload = intent.getStringExtra("payload") ?: return
        if (!payload.contains("\"kind\":\"alarm\"")) return
        setOverLockScreen(true)
    }

    private fun setOverLockScreen(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        }
    }
}
