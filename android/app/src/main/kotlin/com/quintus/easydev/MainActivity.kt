package com.quintus.dev

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val APP_EXIT_CHANNEL = "com.quintus.dev/app_exit"
        private const val WORK_STATUS_NOTIFICATION_CHANNEL =
            "com.quintus.dev/work_status_notification"
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
    }

    private fun pinForegroundNotification(
        serviceId: Int,
        channelId: String?
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "pinned" to true,
                "notificationId" to serviceId,
                "reason" to "legacy_ongoing",
                "flags" to null
            )
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notifications = manager.activeNotifications
        val target = notifications.firstOrNull { it.id == serviceId }
            ?: notifications.firstOrNull { statusBarNotification ->
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
            "notificationId" to target.id,
            "reason" to if (target.id == serviceId) "service_id" else "channel_fallback",
            "flags" to notification.flags
        )
    }
}
