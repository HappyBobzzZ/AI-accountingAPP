package com.example.ai_accounting

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val hapticChannel = "ai_accounting/haptic"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, hapticChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "vibrate" -> {
                        val ms = (call.argument<Number>("ms")?.toLong() ?: 30L)
                        result.success(vibrate(ms))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 直接调系统振动器。
     *
     * Flutter 自带的 HapticFeedback 走 View.performHapticFeedback，
     * 受"系统触感反馈"开关限制、且部分华为/鸿蒙机型上 CONTEXT_CLICK 无效果，
     * 所以这里自己来。返回 false 表示设备没有振动器。
     */
    private fun vibrate(ms: Long): Boolean {
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

        if (vibrator == null || !vibrator.hasVibrator()) return false

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(
                        ms.coerceIn(1L, 400L),
                        VibrationEffect.DEFAULT_AMPLITUDE
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(ms.coerceIn(1L, 400L))
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
