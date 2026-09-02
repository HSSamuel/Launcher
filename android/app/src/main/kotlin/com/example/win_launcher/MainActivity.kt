package com.example.win_launcher

import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.app.SearchManager
import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.view.View
import android.view.WindowInsetsController
import android.view.accessibility.AccessibilityEvent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class LauncherNotificationService : NotificationListenerService() {
    companion object {
        var instance: LauncherNotificationService? = null
        var eventSink: EventChannel.EventSink? = null

        // FIX 1: Robust extractor that captures Bold text and Multi-line Inbox arrays
        fun extractNotificationData(sbn: StatusBarNotification): Map<String, Any>? {
            val extras = sbn.notification.extras
            val title = extras.getCharSequence("android.title")?.toString() ?: ""
            var text = extras.getCharSequence("android.text")?.toString() ?: ""
            
            // Extract stacked messages (like WhatsApp groups)
            val textLines = extras.getCharSequenceArray("android.textLines")
            if (!textLines.isNullOrEmpty()) {
                text = textLines.joinToString("\n") { it.toString() }
            }

            if (title.isNotEmpty() || text.isNotEmpty()) {
                return mapOf(
                    "id" to sbn.id,
                    "key" to sbn.key,
                    "package" to sbn.packageName,
                    "title" to title,
                    "text" to text,
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

class MainActivity: FlutterActivity() {
    private val CHANNEL = "win_launcher/native"
    private val NOTIF_CHANNEL = "win_launcher/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { LauncherNotificationService.eventSink = events }
                override fun onCancel(arguments: Any?) { LauncherNotificationService.eventSink = null }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getActiveNotifications" -> {
                    val service = LauncherNotificationService.instance
                    if (service != null) {
                        try {
                            val active = service.activeNotifications.mapNotNull { LauncherNotificationService.extractNotificationData(it) }
                            result.success(active)
                        } catch (e: Exception) { result.success(emptyList<Map<String, Any>>()) }
                    } else { result.success(emptyList<Map<String, Any>>()) }
                }
                
                "dismissNotification" -> {
                    val key = call.argument<String>("key")
                    if (key != null) { LauncherNotificationService.instance?.cancelNotification(key); result.success(true) } 
                    else result.success(false)
                }
                
                "clearAllNotifications" -> {
                    LauncherNotificationService.instance?.cancelAllNotifications()
                    result.success(true)
                }

                "expandNotificationPanel" -> { expandNotificationPanel(); result.success(null) }
                "openSettings" -> { openCustomSettings(call.argument<String>("type")); result.success(null) }
                "getPermissionStatuses" -> { result.success(checkAllPermissions()) }
                "lockScreen" -> { lockScreen(); result.success(null) }
                
                "launchApp" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    try {
                        val intent = packageManager.getLaunchIntentForPackage(pkg)
                        if (intent != null) { startActivity(intent); result.success(true) } 
                        else { result.success(false) }
                    } catch (e: Exception) { result.success(false) }
                }
                
                "toggleHardware" -> {
                    val key = call.argument<String>("key") ?: ""
                    val enable = call.argument<Boolean>("enable") ?: false
                    toggleHardwareDirectly(key, enable)
                    result.success(null)
                }

                "toggleRecents" -> {
                    val service = LauncherAccessibilityService.instance
                    if (service != null) {
                        service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)
                        result.success(true)
                    } else {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(false)
                    }
                }

                "searchMedia" -> {
                    val query = call.argument<String>("query") ?: ""
                    result.success(searchLocalMedia(query))
                }

                "openFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        val file = File(path)
                        if (file.exists()) {
                            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
                            val extension = file.extension.lowercase(Locale.ROOT)
                            var mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                            
                            if (mimeType == null) {
                                mimeType = when (extension) {
                                    "mp3", "m4a", "wav", "ogg", "flac", "aac" -> "audio/*"
                                    "mp4", "mkv", "avi", "mov", "wmv", "webm" -> "video/*"
                                    "jpg", "jpeg", "png", "gif", "webp", "bmp" -> "image/*"
                                    "pdf" -> "application/pdf"
                                    "doc", "docx" -> "application/msword"
                                    "xls", "xlsx" -> "application/vnd.ms-excel"
                                    "txt", "csv" -> "text/plain"
                                    "zip", "rar", "7z" -> "application/zip"
                                    else -> "*/*"
                                }
                            }
                            
                            val intent = Intent(Intent.ACTION_VIEW)
                            intent.setDataAndType(uri, mimeType)
                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            
                            if (intent.resolveActivity(packageManager) != null) {
                                startActivity(intent)
                            } else {
                                startActivity(Intent.createChooser(intent, "Open with...").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            }
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                        result.success(false)
                    }
                }

                "shareFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        val file = File(path)
                        if (file.exists()) {
                            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
                            val intent = Intent(Intent.ACTION_SEND)
                            intent.type = "*/*"
                            intent.putExtra(Intent.EXTRA_STREAM, uri)
                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            startActivity(Intent.createChooser(intent, "Share File").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } else { result.success(false) }
                    } catch (e: Exception) { result.success(false) }
                }

                "openWebSearch" -> {
                    val query = call.argument<String>("query") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_WEB_SEARCH)
                        intent.putExtra(SearchManager.QUERY, query)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) { result.success(false) }
                }

                "getStorageStats" -> {
                    try {
                        val path = Environment.getExternalStorageDirectory().path
                        val stat = StatFs(path)
                        val total = stat.blockSizeLong * stat.blockCountLong
                        val free = stat.blockSizeLong * stat.availableBlocksLong
                        result.success(mapOf("total" to total.toDouble(), "free" to free.toDouble()))
                    } catch (e: Exception) { result.success(null) }
                }
                "setStatusBarColor" -> {
                    val darkIcons = call.argument<Boolean>("darkIcons") ?: true
                    val colorHex = call.argument<String>("color") ?: "#FFFFFF"
                    try {
                        window.statusBarColor = android.graphics.Color.parseColor(colorHex)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val controller = window.insetsController
                            if (controller != null) {
                                val appearance = if (darkIcons) WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS else 0
                                controller.setSystemBarsAppearance(appearance, WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS)
                            }
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            var flags = window.decorView.systemUiVisibility
                            flags = if (darkIcons) { flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR } else { flags and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv() }
                            window.decorView.systemUiVisibility = flags
                        }
                        result.success(null)
                    } catch (e: Exception) { result.error("STATUS_BAR_ERROR", e.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun searchLocalMedia(query: String): Map<String, List<Map<String, String>>> {
        val results = mutableMapOf<String, MutableList<Map<String, String>>>(
            "Audio" to mutableListOf(), "Images" to mutableListOf(), "Video" to mutableListOf(), "Documents" to mutableListOf()
        )
        if (query.length < 2) return results

        val searchLike = "%$query%"
        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.DATA)
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
        val selectionArgs = arrayOf(searchLike)
        val sortOrder = "${MediaStore.MediaColumns.DATE_ADDED} DESC"

        try {
            contentResolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val pathCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                var count = 0
                while (cursor.moveToNext() && count < 5) { results["Audio"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to cursor.getString(pathCol))); count++ }
            }

            contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val pathCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                var count = 0
                while (cursor.moveToNext() && count < 5) { results["Images"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to cursor.getString(pathCol))); count++ }
            }

            contentResolver.query(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val pathCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                var count = 0
                while (cursor.moveToNext() && count < 5) { results["Video"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to cursor.getString(pathCol))); count++ }
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val docSelection = "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? AND (" +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE '%.pdf' OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE '%.doc' OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE '%.docx' OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE '%.xls' OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE '%.xlsx' OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE '%.txt' OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE '%.ppt' OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE '%.pptx')"

                contentResolver.query(MediaStore.Files.getContentUri("external"), projection, docSelection, arrayOf(searchLike), sortOrder)?.use { cursor ->
                    val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    val pathCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                    var count = 0
                    while (cursor.moveToNext() && count < 5) { results["Documents"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to cursor.getString(pathCol))); count++ }
                }
            }
        } catch (e: Exception) { e.printStackTrace() }

        return results
    }

    @SuppressLint("MissingPermission")
    private fun toggleHardwareDirectly(key: String, enable: Boolean) {
        try {
            when (key) {
                "Bluetooth" -> { val btAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter(); if (enable) btAdapter?.enable() else btAdapter?.disable() }
                "Rotate" -> Settings.System.putInt(contentResolver, Settings.System.ACCELEROMETER_ROTATION, if (enable) 1 else 0)
                "Adaptive Brightness" -> Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, if (enable) 1 else 0)
                "Dark Theme" -> { val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as android.app.UiModeManager; uiModeManager.nightMode = if (enable) android.app.UiModeManager.MODE_NIGHT_YES else android.app.UiModeManager.MODE_NIGHT_NO }
                "Ring" -> { val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager; audioManager.ringerMode = if (enable) android.media.AudioManager.RINGER_MODE_NORMAL else android.media.AudioManager.RINGER_MODE_VIBRATE }
                "DND" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val notifManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        if (notifManager.isNotificationPolicyAccessGranted) { notifManager.setInterruptionFilter(if (enable) android.app.NotificationManager.INTERRUPTION_FILTER_NONE else android.app.NotificationManager.INTERRUPTION_FILTER_ALL) } 
                        else { startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    }
                }
                "Airplane mode" -> startActivity(Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Location" -> startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Hotspot" -> startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        } catch (e: Exception) { e.printStackTrace() }
    }

    private fun lockScreen() {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, LauncherAdminReceiver::class.java)
        if (dpm.isAdminActive(adminComponent)) { dpm.lockNow() }
    }

    @SuppressLint("WrongConstant")
    private fun expandNotificationPanel() {
        try {
            val statusBarService = getSystemService("statusbar")
            val statusBarManager = Class.forName("android.app.StatusBarManager")
            val showMethod = statusBarManager.getMethod("expandNotificationsPanel")
            showMethod.invoke(statusBarService)
        } catch (e: Exception) { e.printStackTrace() }
    }

    private fun checkAllPermissions(): Map<String, Boolean> {
        val permissions = mutableMapOf<String, Boolean>()
        permissions["storage"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) { Environment.isExternalStorageManager() } else { true }
        val listeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        permissions["notification"] = listeners != null && listeners.contains(packageName)
        var accessEnabled = 0
        try { accessEnabled = Settings.Secure.getInt(contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED) } catch (_: Exception) {}
        val accessServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        permissions["accessibility"] = accessEnabled == 1 && accessServices != null && accessServices.contains(packageName)
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        permissions["admin"] = dpm.isAdminActive(ComponentName(this, LauncherAdminReceiver::class.java))
        permissions["write_settings"] = Settings.System.canWrite(this)
        return permissions
    }

    private fun openCustomSettings(type: String?) {
        try {
            var useNewTask = true
            val intent = when (type) {
                "wifi" -> { useNewTask = false; if (Build.VERSION.SDK_INT >= 29) Intent("android.settings.panel.action.WIFI") else Intent(Settings.ACTION_WIFI_SETTINGS) }
                "data" -> { useNewTask = false; if (Build.VERSION.SDK_INT >= 29) Intent("android.settings.panel.action.INTERNET_CONNECTIVITY") else Intent(Settings.ACTION_DATA_USAGE_SETTINGS) }
                "battery_saver" -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                "vpn" -> Intent(Settings.ACTION_VPN_SETTINGS)
                "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                "add_account" -> Intent(Settings.ACTION_ADD_ACCOUNT)
                "notification_access" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                else -> Intent(Settings.ACTION_SETTINGS)
            }
            if (useNewTask) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}