package com.quintus.dev

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val APP_EXIT_CHANNEL = "com.quintus.dev/app_exit"
        private const val WORK_STATUS_NOTIFICATION_CHANNEL =
            "com.quintus.dev/work_status_notification"
        private const val BUILD_OPTIMIZATION_CHANNEL =
            "com.quintus.dev/build_optimization"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_EXIT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "finishAndRemoveTask" -> {
                    result.success(null)
                    finishAndRemoveTask()
                }
                "restartApp" -> {
                    try {
                        val restartIntent = Intent(this, MainActivity::class.java).apply {
                            action = Intent.ACTION_MAIN
                            addCategory(Intent.CATEGORY_LAUNCHER)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                        }
                        startActivity(restartIntent)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "restart_failed",
                            error.javaClass.simpleName,
                            null
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WORK_STATUS_NOTIFICATION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pinForegroundNotification" -> {
                    val serviceId = call.argument<Int>("serviceId")
                    val channelId = call.argument<String>("channelId")
                    if (serviceId == null) {
                        result.error("invalid_service_id", "serviceId is required", null)
                        return@setMethodCallHandler
                    }
                    result.success(pinForegroundNotification(serviceId, channelId))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BUILD_OPTIMIZATION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBuildOptimizationStatus" -> {
                    result.success(buildOptimizationStatus())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun buildOptimizationStatus(): Map<String, Any?> {
        return mapOf(
            "applicationId" to BuildConfig.APPLICATION_ID,
            "buildType" to BuildConfig.BUILD_TYPE,
            "debug" to BuildConfig.DEBUG,
            "versionName" to BuildConfig.VERSION_NAME,
            "versionCode" to BuildConfig.VERSION_CODE,
            "minifyEnabled" to BuildConfig.R8_MINIFY_ENABLED,
            "optimizeRulesEnabled" to BuildConfig.R8_OPTIMIZE_ENABLED,
            "resourceShrinkEnabled" to BuildConfig.RESOURCE_SHRINK_ENABLED
        )
    }

    private fun pinForegroundNotification(
        serviceId: Int,
        channelId: String?
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "pinned" to true,
                "notificationFound" to true,
                "notificationId" to serviceId,
                "reason" to "legacy_ongoing",
                "flags" to null
            )
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val target = manager.activeNotifications.firstOrNull { it.id == serviceId }
            ?: manager.activeNotifications.firstOrNull { statusBarNotification ->
                val notification = statusBarNotification.notification
                val foregroundService =
                    notification.flags and Notification.FLAG_FOREGROUND_SERVICE != 0
                val channelMatches = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    channelId.isNullOrEmpty() || notification.channelId == channelId
                } else {
                    true
                }
                foregroundService && channelMatches
            }

        if (target == null) {
            return mapOf(
                "pinned" to false,
                "notificationFound" to false,
                "notificationId" to null,
                "reason" to "notification_not_found",
                "flags" to null
            )
        }

        val notification = target.notification
        notification.flags = notification.flags or
            Notification.FLAG_ONGOING_EVENT or
            Notification.FLAG_NO_CLEAR
        manager.notify(target.id, notification)

        return mapOf(
            "pinned" to true,
            "notificationFound" to true,
            "notificationId" to target.id,
            "reason" to if (target.id == serviceId) "service_id" else "channel_fallback",
            "flags" to notification.flags
        )
    }
}
