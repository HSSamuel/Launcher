package com.example.win_launcher

import android.accessibilityservice.AccessibilityService
import android.app.admin.DeviceAdminReceiver
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.view.accessibility.AccessibilityEvent
import io.flutter.plugin.common.EventChannel

class LauncherNotificationService : NotificationListenerService() {
    companion object {
        var instance: LauncherNotificationService? = null
        var eventSink: EventChannel.EventSink? = null

        fun extractNotificationData(sbn: StatusBarNotification): Map<String, Any>? {
            val extras = sbn.notification.extras
            val title = extras.getCharSequence("android.title")?.toString() ?: ""
            var text = extras.getCharSequence("android.text")?.toString() ?: ""

            // CRITICAL FIX: Explicitly handle MessagingStyle for WhatsApp, Telegram, and SMS
            val messages = extras.getParcelableArray("android.messages")
            if (messages != null && messages.isNotEmpty()) {
                val lastMessage = messages.last() as? Bundle
                val msgText = lastMessage?.getCharSequence("text")?.toString()
                val sender = lastMessage?.getCharSequence("sender")?.toString()
                if (msgText != null) {
                    text = if (sender != null) "$sender: $msgText" else msgText
                }
            } else {
                val bigText = extras.getCharSequence("android.bigText")?.toString()
                if (!bigText.isNullOrEmpty()) {
                    text = bigText
                } else {
                    val textLines = extras.getCharSequenceArray("android.textLines")
                    if (!textLines.isNullOrEmpty()) {
                        text = textLines.joinToString("\n") { it.toString() }
                    }
                }
            }

            val actionList = mutableListOf<Map<String, Any>>()
            sbn.notification.actions?.forEachIndexed { index, action ->
                actionList.add(mapOf(
                    "title" to (action.title?.toString() ?: ""),
                    "index" to index
                ))
            }

            if (title.isNotEmpty() || text.isNotEmpty()) {
                return mapOf(
                    "id" to sbn.id,
                    "key" to sbn.key,
                    "package" to sbn.packageName,
                    "title" to title,
                    "text" to text,
                    "postTime" to sbn.postTime, // Syncs exact Android arrival time
                    "actions" to actionList,
                    "removed" to false
                )
            }
            return null
        }
    }

    override fun onListenerConnected() { instance = this }
    override fun onListenerDisconnected() { instance = null }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        extractNotificationData(sbn)?.let { eventSink?.success(it) }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        eventSink?.success(mapOf("key" to sbn.key, "removed" to true))
    }
}

class LauncherAccessibilityService : AccessibilityService() {
    companion object { var instance: LauncherAccessibilityService? = null }
    override fun onServiceConnected() { super.onServiceConnected(); instance = this }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}
    override fun onUnbind(intent: Intent?): Boolean { instance = null; return super.onUnbind(intent) }
}

class LauncherAdminReceiver : DeviceAdminReceiver()