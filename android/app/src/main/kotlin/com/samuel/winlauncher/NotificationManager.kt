package com.samuel.winlauncher

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.Locale

class NotificationManager(private val activity: Activity) {
    private val TAG = "Win11NotifManager"

    fun getActiveNotifications(result: MethodChannel.Result) {
        val service = LauncherNotificationService.instance
        if (service == null) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val active = service.activeNotifications.mapNotNull { 
                    LauncherNotificationService.extractNotificationData(it) 
                }
                activity.runOnUiThread { result.success(active) }
            } catch (e: Exception) { 
                Log.e(TAG, "Error fetching active notifications", e)
                activity.runOnUiThread { result.success(emptyList<Map<String, Any>>()) }
            }
        }
    }

    private fun executePendingIntent(pendingIntent: android.app.PendingIntent, fillInIntent: Intent? = null): Boolean {
        return try {
            val isActivity = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && pendingIntent.isActivity
            
            var optionsBundle: Bundle? = null
            if (isActivity && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                optionsBundle = android.app.ActivityOptions.makeBasic().apply {
                    pendingIntentBackgroundActivityStartMode = android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                }.toBundle()
            }

            if (fillInIntent != null) {
                if (optionsBundle != null) {
                    pendingIntent.send(activity, 0, fillInIntent, null, null, null, optionsBundle)
                } else {
                    pendingIntent.send(activity, 0, fillInIntent)
                }
            } else {
                if (optionsBundle != null) {
                    pendingIntent.send(null, 0, null, null, null, null, optionsBundle)
                } else {
                    pendingIntent.send()
                }
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "PendingIntent execution failed", e)
            try {
                pendingIntent.send() 
                true
            } catch (fallbackEx: Exception) {
                Log.e(TAG, "Fallback execution failed", fallbackEx)
                false
            }
        }
    }

    fun triggerNotificationAction(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key") ?: ""
        val actionIndex = call.argument<Int>("actionIndex") ?: -1
        val replyText = call.argument<String>("replyText")
        
        val service = LauncherNotificationService.instance
        if (service == null) {
            result.success(false)
            return
        }

        try {
            val activeNotifs = service.activeNotifications
            val sbn = activeNotifs.find { it.key == key }
            
            if (sbn == null) {
                result.success(false)
                return
            }

            if (actionIndex == -1) {
                if (sbn.notification.contentIntent != null) {
                    val success = executePendingIntent(sbn.notification.contentIntent)
                    result.success(success)
                } else {
                    val launchIntent = activity.packageManager.getLaunchIntentForPackage(sbn.packageName)
                    if (launchIntent != null) {
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        activity.startActivity(launchIntent)
                        service.cancelNotification(key)
                        result.success(true)
                    } else { 
                        result.success(false) 
                    }
                }
            } else {
                val action = sbn.notification.actions?.getOrNull(actionIndex)
                if (action?.actionIntent != null) {
                    val remoteInputs = action.remoteInputs
                    if (remoteInputs != null && remoteInputs.isNotEmpty() && !replyText.isNullOrEmpty()) {
                        val localIntent = Intent()
                        val results = Bundle()
                        for (remoteInput in remoteInputs) {
                            results.putCharSequence(remoteInput.resultKey, replyText)
                        }
                        android.app.RemoteInput.addResultsToIntent(remoteInputs, localIntent, results)
                        val success = executePendingIntent(action.actionIntent, localIntent)
                        result.success(success)
                    } else {
                        val success = executePendingIntent(action.actionIntent)
                        val titleStr = action.title?.toString()?.lowercase(Locale.ROOT) ?: ""
                        if (success && (titleStr.contains("read") || titleStr.contains("delete") || titleStr.contains("mute") || titleStr.contains("clear"))) {
                            service.cancelNotification(key)
                        }
                        result.success(success)
                    }
                } else { 
                    result.success(false) 
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error triggering notification action", e)
            result.success(false)
        }
    }

    fun dismissNotification(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        if (key != null) {
            LauncherNotificationService.instance?.cancelNotification(key)
            result.success(true)
        } else {
            result.success(false)
        }
    }

    fun clearAllNotifications(result: MethodChannel.Result) {
        LauncherNotificationService.instance?.cancelAllNotifications()
        result.success(true)
    }

    fun expandNotificationPanel(result: MethodChannel.Result) {
        try {
            val service = LauncherAccessibilityService.instance
            if (service != null) {
                val success = service.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)
                if (success) {
                    result.success(null)
                } else {
                    result.error("EXPAND_PANEL_FAILED", "Accessibility Service could not execute the action.", null)
                }
            } else {
                result.error("ACCESSIBILITY_REQUIRED", "Accessibility Service is not running or enabled.", null)
            }
        } catch (e: Exception) { 
            Log.e(TAG, "Error expanding notification panel", e)
            result.error("EXPAND_PANEL_FAILED", e.message, null)
        }
    }
}