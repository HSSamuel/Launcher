package com.example.win_launcher

import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.app.Activity
import android.app.SearchManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle 
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import android.view.View
import android.view.WindowInsetsController
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class IntentHandler(private val activity: Activity) {

    // CRITICAL FIX: Deep scans the package manager to bypass unknown OEM package names
    private fun launchAppByName(nameQuery: String, packageQuery: String = ""): Boolean {
        try {
            val pm = activity.packageManager
            val mainIntent = Intent(Intent.ACTION_MAIN, null)
            mainIntent.addCategory(Intent.CATEGORY_LAUNCHER)
            val apps = pm.queryIntentActivities(mainIntent, 0)
            
            for (resolveInfo in apps) {
                val pkgName = resolveInfo.activityInfo.packageName.lowercase(Locale.ROOT)
                val label = resolveInfo.loadLabel(pm).toString().lowercase(Locale.ROOT)
                
                if (label.contains(nameQuery.lowercase(Locale.ROOT)) || 
                    (packageQuery.isNotEmpty() && pkgName.contains(packageQuery.lowercase(Locale.ROOT)))) {
                    
                    val intent = pm.getLaunchIntentForPackage(resolveInfo.activityInfo.packageName)
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(intent)
                        return true
                    }
                }
            }
        } catch (e: Exception) { e.printStackTrace() }
        return false
    }

    @SuppressLint("MissingPermission")
    fun getRawHardwareState(): Map<String, Any> {
        val states = mutableMapOf<String, Any>()
        try {
            val btAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
            states["Bluetooth"] = btAdapter?.isEnabled == true
            
            val wifiManager = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
            states["Wi-Fi"] = wifiManager.isWifiEnabled
            
            states["Rotate"] = Settings.System.getInt(activity.contentResolver, Settings.System.ACCELEROMETER_ROTATION, 0) == 1
            states["Airplane mode"] = Settings.Global.getInt(activity.contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0) == 1
            
            val notifManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            states["DND"] = notifManager.currentInterruptionFilter != android.app.NotificationManager.INTERRUPTION_FILTER_ALL
            
            val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            states["Ring"] = audioManager.ringerMode == android.media.AudioManager.RINGER_MODE_NORMAL
            
            val locationManager = activity.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
            states["Location"] = if (Build.VERSION.SDK_INT >= 28) {
                locationManager.isLocationEnabled
            } else {
                Settings.Secure.getInt(activity.contentResolver, Settings.Secure.LOCATION_MODE, Settings.Secure.LOCATION_MODE_OFF) != Settings.Secure.LOCATION_MODE_OFF
            }
            
            val uiModeManager = activity.getSystemService(Context.UI_MODE_SERVICE) as android.app.UiModeManager
            states["Dark Theme"] = uiModeManager.nightMode == android.app.UiModeManager.MODE_NIGHT_YES
            states["Brightness"] = Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, 0) == 1
            
            val brightnessInt = Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128)
            states["sys_brightness"] = brightnessInt / 255.0
            
        } catch (e: Exception) { e.printStackTrace() }
        return states
    }

    fun getHardwareState(result: MethodChannel.Result) {
        result.success(getRawHardwareState())
    }

    fun setSystemBrightness(call: MethodCall, result: MethodChannel.Result) {
        val brightness = call.argument<Double>("brightness") ?: 0.5
        try {
            if (!Settings.System.canWrite(activity)) {
                val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                intent.data = Uri.parse("package:" + activity.packageName)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
                result.success(null)
                return
            }
            val brightnessInt = (brightness * 255).toInt()
            Settings.System.putInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, brightnessInt)
        } catch (e: Exception) { e.printStackTrace() }
        result.success(null)
    }

    @SuppressLint("MissingPermission")
    fun toggleHardware(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key") ?: ""
        val enable = call.argument<Boolean>("enable") ?: false
        try {
            when (key) {
                "Rotate", "Brightness" -> {
                    if (!Settings.System.canWrite(activity)) {
                        val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                        intent.data = Uri.parse("package:" + activity.packageName)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(intent)
                        result.success(null)
                        return
                    }
                    if (key == "Rotate") {
                        Settings.System.putInt(activity.contentResolver, Settings.System.ACCELEROMETER_ROTATION, if (enable) 1 else 0)
                    } else {
                        Settings.System.putInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, if (enable) 1 else 0)
                    }
                }
                "Bluetooth" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } else {
                        val btAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
                        if (enable) btAdapter?.enable() else btAdapter?.disable()
                    }
                }
                "Wi-Fi" -> {
                    if (Build.VERSION.SDK_INT >= 29) {
                        activity.startActivity(Intent("android.settings.panel.action.WIFI").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } else {
                        val wifiManager = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
                        wifiManager.isWifiEnabled = enable
                    }
                }
                "Data" -> {
                    if (Build.VERSION.SDK_INT >= 29) {
                        activity.startActivity(Intent("android.settings.panel.action.INTERNET_CONNECTIVITY").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } else {
                        activity.startActivity(Intent(Settings.ACTION_DATA_USAGE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                }
                "Dark Theme" -> {
                    val uiModeManager = activity.getSystemService(Context.UI_MODE_SERVICE) as android.app.UiModeManager
                    uiModeManager.nightMode = if (enable) android.app.UiModeManager.MODE_NIGHT_YES else android.app.UiModeManager.MODE_NIGHT_NO
                }
                "Ring" -> {
                    val notifManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !notifManager.isNotificationPolicyAccessGranted) {
                        activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                        return
                    }
                    val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                    audioManager.ringerMode = if (enable) android.media.AudioManager.RINGER_MODE_NORMAL else android.media.AudioManager.RINGER_MODE_VIBRATE
                }
                "DND" -> {
                    val notifManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (!notifManager.isNotificationPolicyAccessGranted) {
                            activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(null)
                            return
                        } else {
                            notifManager.setInterruptionFilter(if (enable) android.app.NotificationManager.INTERRUPTION_FILTER_NONE else android.app.NotificationManager.INTERRUPTION_FILTER_ALL)
                        }
                    }
                }
                "Airplane mode" -> activity.startActivity(Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Location" -> activity.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Hotspot" -> activity.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Battery saver" -> activity.startActivity(Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Accessibility" -> activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Storage" -> activity.startActivity(Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Screen Cast" -> activity.startActivity(Intent("android.settings.CAST_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Eye Care" -> activity.startActivity(Intent(Settings.ACTION_NIGHT_DISPLAY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                
                "Users & Account" -> activity.startActivity(Intent(Settings.ACTION_SYNC_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                
                "Kids Mode" -> {
                    var launched = launchAppByName("kids", "childmode")
                    if (!launched) launched = launchAppByName("child", "kidsmode")
                    
                    if (!launched) {
                        activity.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                }
                
                "Play" -> {
                    val intent = Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_MUSIC)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(intent)
                }
                "Song Search" -> {
                    val intent = Intent("com.google.android.googlequicksearchbox.MUSIC_SEARCH")
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        activity.startActivity(intent)
                    } catch (e: Exception) {
                        val fallback = Intent(Intent.ACTION_WEB_SEARCH)
                        fallback.putExtra(SearchManager.QUERY, "what song is this")
                        fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(fallback)
                    }
                }
                "Scan QR Code" -> {
                    var launched = launchAppByName("scanner", "scanner")
                    
                    if (!launched) {
                        try {
                            val lensIntent = Intent(Intent.ACTION_VIEW, Uri.parse("googleapp://lens"))
                            lensIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            activity.startActivity(lensIntent)
                        } catch (e: Exception) {
                            try {
                                val fallback = Intent("com.google.zxing.client.android.SCAN")
                                fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                activity.startActivity(fallback)
                            } catch (e2: Exception) {
                                val playStore = Intent(Intent.ACTION_VIEW, Uri.parse("market://search?q=qr scanner"))
                                playStore.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                activity.startActivity(playStore)
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) { e.printStackTrace() }
        result.success(null)
    }

    fun getActiveNotifications(result: MethodChannel.Result) {
        val service = LauncherNotificationService.instance
        if (service != null) {
            try {
                val active = service.activeNotifications.mapNotNull { LauncherNotificationService.extractNotificationData(it) }
                result.success(active)
            } catch (e: Exception) { result.success(emptyList<Map<String, Any>>()) }
        } else { result.success(emptyList<Map<String, Any>>()) }
    }

    fun triggerNotificationAction(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key") ?: ""
        val actionIndex = call.argument<Int>("actionIndex") ?: -1
        val service = LauncherNotificationService.instance
        
        if (service != null) {
            val sbn = service.activeNotifications.find { it.key == key }
            if (sbn != null) {
                try {
                    val intent = Intent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    var optionsBundle: Bundle? = null
                    if (Build.VERSION.SDK_INT >= 34) {
                        try {
                            val options = android.app.ActivityOptions.makeBasic()
                            options.setPendingIntentBackgroundActivityStartMode(android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                            optionsBundle = options.toBundle()
                        } catch (e: Exception) { e.printStackTrace() }
                    }

                    if (actionIndex == -1) {
                        if (sbn.notification.contentIntent != null) {
                            sbn.notification.contentIntent.send(activity, 0, intent, null, null, null, optionsBundle)
                            service.cancelNotification(key)
                            result.success(true)
                        } else {
                            val launchIntent = activity.packageManager.getLaunchIntentForPackage(sbn.packageName)
                            if (launchIntent != null) {
                                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                activity.startActivity(launchIntent)
                                service.cancelNotification(key)
                                result.success(true)
                            } else { result.success(false) }
                        }
                    } else {
                        val action = sbn.notification.actions?.get(actionIndex)
                        if (action?.actionIntent != null) {
                            action.actionIntent.send(activity, 0, intent, null, null, null, optionsBundle)
                            result.success(true)
                        } else { result.success(false) }
                    }
                } catch (e: Exception) { 
                    val launchIntent = activity.packageManager.getLaunchIntentForPackage(sbn.packageName)
                    if (launchIntent != null) {
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(launchIntent)
                        service.cancelNotification(key)
                        result.success(true)
                    } else { result.success(false) }
                }
            } else result.success(false)
        } else result.success(false)
    }

    fun dismissNotification(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        if (key != null) {
            LauncherNotificationService.instance?.cancelNotification(key)
            result.success(true)
        } else result.success(false)
    }

    fun clearAllNotifications(result: MethodChannel.Result) {
        LauncherNotificationService.instance?.cancelAllNotifications()
        result.success(true)
    }

    @SuppressLint("WrongConstant")
    fun expandNotificationPanel(result: MethodChannel.Result) {
        val service = LauncherAccessibilityService.instance
        if (service != null && service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)) {
            result.success(null)
            return
        }
        try {
            val statusBarService = activity.getSystemService("statusbar")
            val statusBarManager = Class.forName("android.app.StatusBarManager")
            val showMethod = statusBarManager.getMethod("expandNotificationsPanel")
            showMethod.invoke(statusBarService)
        } catch (e: Exception) { e.printStackTrace() }
        result.success(null)
    }

    fun getPermissionStatuses(result: MethodChannel.Result) {
        val permissions = mutableMapOf<String, Boolean>()
        permissions["storage"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager() else true
        val listeners = Settings.Secure.getString(activity.contentResolver, "enabled_notification_listeners")
        
        val expectedComponent = ComponentName(activity, LauncherNotificationService::class.java).flattenToString()
        permissions["notification"] = listeners?.split(":")?.any { it == expectedComponent } == true

        var accessEnabled = 0
        try { accessEnabled = Settings.Secure.getInt(activity.contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED) } catch (_: Exception) {}
        val accessServices = Settings.Secure.getString(activity.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        val expectedAccessComponent = ComponentName(activity, LauncherAccessibilityService::class.java).flattenToString()
        permissions["accessibility"] = accessEnabled == 1 && accessServices?.split(":")?.any { it == expectedAccessComponent } == true

        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        permissions["admin"] = dpm.isAdminActive(ComponentName(activity, LauncherAdminReceiver::class.java))
        permissions["write_settings"] = Settings.System.canWrite(activity)

        result.success(permissions)
    }

    fun openCustomSettings(call: MethodCall, result: MethodChannel.Result) {
        val type = call.argument<String>("type")
        try {
            var useNewTask = true
            val intent = when (type) {
                "home" -> Intent(Settings.ACTION_HOME_SETTINGS)
                "wifi" -> { useNewTask = false; if (Build.VERSION.SDK_INT >= 29) Intent("android.settings.panel.action.WIFI") else Intent(Settings.ACTION_WIFI_SETTINGS) }
                "data" -> { useNewTask = false; if (Build.VERSION.SDK_INT >= 29) Intent("android.settings.panel.action.INTERNET_CONNECTIVITY") else Intent(Settings.ACTION_DATA_USAGE_SETTINGS) }
                "battery_saver" -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                "vpn" -> Intent(Settings.ACTION_VPN_SETTINGS)
                "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                "add_account" -> Intent(Settings.ACTION_ADD_ACCOUNT)
                "notification_access" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                "manage_apps" -> Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS)
                "default_apps" -> if (Build.VERSION.SDK_INT >= 24) Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS) else Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS)
                "print_settings" -> Intent(Settings.ACTION_PRINT_SETTINGS)
                "storage" -> Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
                "display" -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
                "airplane" -> Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS)
                "location" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                "hotspot" -> Intent(Settings.ACTION_WIRELESS_SETTINGS)
                "locale" -> Intent(Settings.ACTION_LOCALE_SETTINGS)
                "keyboard" -> Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                else -> Intent(Settings.ACTION_SETTINGS)
            }
            if (useNewTask) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) { activity.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        result.success(null)
    }

    fun lockScreen(result: MethodChannel.Result) {
        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(activity, LauncherAdminReceiver::class.java)
        if (dpm.isAdminActive(adminComponent)) dpm.lockNow()
        result.success(null)
    }

    fun launchApp(call: MethodCall, result: MethodChannel.Result) {
        val pkg = call.argument<String>("package") ?: ""
        try {
            val intent = activity.packageManager.getLaunchIntentForPackage(pkg)
            if (intent != null) { activity.startActivity(intent); result.success(true) }
            else result.success(false)
        } catch (e: Exception) { result.success(false) }
    }

    fun uninstallApp(call: MethodCall, result: MethodChannel.Result) {
        val pkg = call.argument<String>("package") ?: ""
        try {
            val intent = Intent(Intent.ACTION_DELETE)
            intent.data = Uri.parse("package:$pkg")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            result.success(true)
        } catch (e: Exception) { result.success(false) }
    }

    fun toggleRecents(result: MethodChannel.Result) {
        val service = LauncherAccessibilityService.instance
        if (service != null) {
            service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)
            result.success(true)
        } else result.success(false)
    }

    fun showPowerDialog(result: MethodChannel.Result) {
        val service = LauncherAccessibilityService.instance
        if (service != null) {
            service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_POWER_DIALOG)
            result.success(true)
        } else result.success(false)
    }

    fun searchMedia(call: MethodCall, result: MethodChannel.Result) {
        val query = call.argument<String>("query") ?: ""
        val results = mutableMapOf<String, MutableList<Map<String, String>>>(
            "Audio" to mutableListOf(), "Images" to mutableListOf(), "Video" to mutableListOf(), "Documents" to mutableListOf()
        )
        if (query.length < 2) { result.success(results); return }

        val searchLike = "%$query%"
        val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME)
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
        val selectionArgs = arrayOf(searchLike)
        val sortOrder = "${MediaStore.MediaColumns.DATE_ADDED} DESC"

        try {
            activity.contentResolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                var count = 0
                while (cursor.moveToNext() && count < 5) { 
                    val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, cursor.getLong(idCol))
                    results["Audio"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to uri.toString())); count++ 
                }
            }

            activity.contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                var count = 0
                while (cursor.moveToNext() && count < 5) { 
                    val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cursor.getLong(idCol))
                    results["Images"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to uri.toString())); count++ 
                }
            }

            activity.contentResolver.query(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                var count = 0
                while (cursor.moveToNext() && count < 5) { 
                    val uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, cursor.getLong(idCol))
                    results["Video"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to uri.toString())); count++ 
                }
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

                activity.contentResolver.query(MediaStore.Files.getContentUri("external"), projection, docSelection, arrayOf(searchLike), sortOrder)?.use { cursor ->
                    val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                    val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    var count = 0
                    while (cursor.moveToNext() && count < 5) { 
                        val uri = ContentUris.withAppendedId(MediaStore.Files.getContentUri("external"), cursor.getLong(idCol))
                        results["Documents"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to uri.toString())); count++ 
                    }
                }
            }
        } catch (e: Exception) { e.printStackTrace() }
        result.success(results)
    }

    fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: ""
        try {
            val uri: Uri
            var mimeType: String? = "*/*"

            if (path.startsWith("content://")) {
                uri = Uri.parse(path)
                mimeType = activity.contentResolver.getType(uri) ?: "*/*"
            } else {
                val file = File(path)
                if (file.exists()) {
                    uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
                    val extension = file.extension.lowercase(Locale.ROOT)
                    mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)

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
                } else {
                    result.success(false)
                    return
                }
            }

            val intent = Intent(Intent.ACTION_VIEW)
            intent.setDataAndType(uri, mimeType)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            if (intent.resolveActivity(activity.packageManager) != null) activity.startActivity(intent)
            else activity.startActivity(Intent.createChooser(intent, "Open with...").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(true)
        } catch (e: Exception) { e.printStackTrace(); result.success(false) }
    }

    fun shareFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: ""
        try {
            val uri: Uri = if (path.startsWith("content://")) {
                Uri.parse(path)
            } else {
                val file = File(path)
                if (!file.exists()) { result.success(false); return }
                FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
            }
            
            val intent = Intent(Intent.ACTION_SEND)
            intent.type = "*/*"
            intent.putExtra(Intent.EXTRA_STREAM, uri)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivity(Intent.createChooser(intent, "Share File").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(true)
        } catch (e: Exception) { result.success(false) }
    }

    fun openWebSearch(call: MethodCall, result: MethodChannel.Result) {
        val query = call.argument<String>("query") ?: ""
        try {
            val intent = Intent(Intent.ACTION_WEB_SEARCH)
            intent.putExtra(SearchManager.QUERY, query)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            result.success(true)
        } catch (e: Exception) { result.success(false) }
    }

    fun getStorageStats(result: MethodChannel.Result) {
        try {
            val path = Environment.getExternalStorageDirectory().path
            val stat = StatFs(path)
            val total = stat.blockSizeLong * stat.blockCountLong
            val free = stat.blockSizeLong * stat.availableBlocksLong
            result.success(mapOf("total" to total.toDouble(), "free" to free.toDouble()))
        } catch (e: Exception) { result.success(null) }
    }

    fun setStatusBarColor(call: MethodCall, result: MethodChannel.Result) {
        val darkIcons = call.argument<Boolean>("darkIcons") ?: true
        val colorHex = call.argument<String>("color") ?: "#FFFFFF"
        try {
            activity.window.statusBarColor = android.graphics.Color.parseColor(colorHex)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val controller = activity.window.insetsController
                if (controller != null) {
                    val appearance = if (darkIcons) WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS else 0
                    controller.setSystemBarsAppearance(appearance, WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS)
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                var flags = activity.window.decorView.systemUiVisibility
                flags = if (darkIcons) { flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR } else { flags and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv() }
                activity.window.decorView.systemUiVisibility = flags
            }
            result.success(null)
        } catch (e: Exception) { result.error("STATUS_BAR_ERROR", e.message, null) }
    }
}