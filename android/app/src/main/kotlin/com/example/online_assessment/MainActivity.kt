package com.example.online_assessment

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "online_assessment/lockdown"
    private lateinit var channel: MethodChannel
    private var lockdownActive: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Default to FLAG_SECURE so screenshots / recents thumbnail are blocked
        // for the lifetime of the Activity. Dart can re-toggle via the
        // MethodChannel during enable/disable.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    applyLockdownFlags()
                    lockdownActive = true
                    result.success(true)
                }
                "disable" -> {
                    clearLockdownFlags()
                    lockdownActive = false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // If the window loses focus while lockdown is active, that's likely
        // due to an overlay, notification shade, or app switch. Notify Dart
        // so it can record a violation and show the overlay UI.
        try {
            if (!hasFocus && ::channel.isInitialized && lockdownActive) {
                channel.invokeMethod("violation", "Window lost focus - possible overlay or notification shade")
            }
        } catch (e: Exception) {
            // Ignore any IPC errors
        }
    }

    /**
     * Apply the strictest realistic Android lockdown:
     *   - FLAG_SECURE: blocks screenshots, screen recording, and the
     *     recents-screen thumbnail of the app's window.
     *   - SYSTEM_UI_FLAG_IMMERSIVE_STICKY: the system bars (status bar,
     *     navigation bar) hide and re-hide automatically when the user
     *     swipes, which also suppresses the notification shade / Quick
     *     Settings pull-down.
     *   - Attempt startLockTask(): request a pinned/locked task session where
     *     available (requires device owner / provisioning). Failures are
     *     caught and ignored so the app still works on normal devices.
     */
    private fun applyLockdownFlags() {
        runOnUiThread {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                window.decorView.systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        or View.SYSTEM_UI_FLAG_FULLSCREEN
                        or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
            } else {
                window.setDecorFitsSystemWindows(false)
                val controller = window.insetsController
                if (controller != null) {
                    controller.systemBarsBehavior =
                        android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    controller.hide(
                        android.view.WindowInsets.Type.statusBars()
                            or android.view.WindowInsets.Type.navigationBars()
                    )
                }
            }

            // Try to engage Lock Task (kiosk) mode. This only succeeds on
            // devices where the app is a device owner / provisioned for this.
            try {
                startLockTask()
            } catch (e: Exception) {
                // Not a device owner or not allowed — ignore.
            }
        }
    }

    private fun clearLockdownFlags() {
        runOnUiThread {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(true)
                window.insetsController?.show(
                    android.view.WindowInsets.Type.statusBars()
                        or android.view.WindowInsets.Type.navigationBars()
                )
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
            }

            // Stop lock task if we started it
            try {
                stopLockTask()
            } catch (e: Exception) {
                // ignore
            }
        }
    }
}
