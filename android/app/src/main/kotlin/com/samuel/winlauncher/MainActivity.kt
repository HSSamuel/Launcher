package com.samuel.winlauncher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.FileObserver
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    private val TAG = "Win11MainActivity"
    
    private val CHANNEL = "win_launcher/native"
    private val NOTIF_CHANNEL = "win_launcher/notifications"
    private val HARDWARE_CHANNEL = "win_launcher/hardware_events"
    private val PACKAGE_CHANNEL = "win_launcher/package_events"
    private val FILE_EVENTS_CHANNEL = "win_launcher/file_events"

    private val hardwareManager by lazy { HardwareManager(this) }
    private val appManager by lazy { AppLauncherManager(this) }
    private val mediaManager by lazy { MediaManager(this) }
    private val notificationManager by lazy { NotificationManager(this) }
    private val widgetEngine by lazy { WidgetEngine(this) }

    private var hardwareReceiver: BroadcastReceiver? = null
    private var packageReceiver: BroadcastReceiver? = null
    private var downloadObserver: FileObserver? = null

    private val activityScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun getBackgroundMode(): BackgroundMode {
        return BackgroundMode.transparent
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        try {
            File(cacheDir, "notif_icons").deleteRecursively()
        } catch (e: Exception) {}
        
        window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER)
        window.setFormat(android.graphics.PixelFormat.TRANSPARENT)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val params = window.attributes
            params.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = params
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        
        widgetEngine.onCreate()
        hardwareManager.initPersistentReceiver()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == android.hardware.usb.UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(android.hardware.usb.UsbManager.EXTRA_DEVICE, android.hardware.usb.UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<android.hardware.usb.UsbDevice>(android.hardware.usb.UsbManager.EXTRA_DEVICE)
            }
            
            val localIntent = Intent("com.samuel.winlauncher.USB_ATTACHED_LOCAL").apply {
                putExtra("device", device)
                `package` = packageName 
            }
            sendBroadcast(localIntent)
        }
    }

    override fun onStart() {
        super.onStart()
        widgetEngine.onStart()
    }

    override fun onStop() {
        super.onStop()
        widgetEngine.onStop()
    }

    override fun onDestroy() {
        super.onDestroy()
        activityScope.cancel()
        widgetEngine.onDestroy()
        appManager.onDestroy()
        mediaManager.onDestroy()
        hardwareManager.onDestroy()
        
        hardwareReceiver?.let { try { applicationContext.unregisterReceiver(it) } catch (e: Exception) {} }
        packageReceiver?.let { try { applicationContext.unregisterReceiver(it) } catch (e: Exception) {} }
        hardwareReceiver = null
        packageReceiver = null
        
        downloadObserver?.stopWatching()
        downloadObserver = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        widgetEngine.onActivityResult(requestCode, resultCode, data)
        if (mediaManager.onActivityResult(requestCode, resultCode)) return
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        hardwareManager.registerUsbChannel(flutterEngine.dartExecutor.binaryMessenger)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "NativeWidget", widgetEngine.NativeWidgetFactory()
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { LauncherNotificationService.eventSink = events }
                override fun onCancel(arguments: Any?) { LauncherNotificationService.eventSink = null }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HARDWARE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    hardwareReceiver?.let { try { applicationContext.unregisterReceiver(it) } catch (e: Exception) {} }
                    
                    hardwareReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            if (intent == null) return

                            if (intent.action == Intent.ACTION_BATTERY_CHANGED) {
                                val level = intent.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
                                val scale = intent.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1)
                                val status = intent.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1)
                                
                                val batteryPct = if (level != -1 && scale != -1) (level * 100 / scale.toFloat()).toInt() else 100
                                val isCharging = status == android.os.BatteryManager.BATTERY_STATUS_CHARGING || status == android.os.BatteryManager.BATTERY_STATUS_FULL
                                
                                try {
                                    events?.success(mapOf(
                                        "battery_level" to batteryPct,
                                        "battery_charging" to isCharging
                                    ))
                                } catch (e: Exception) {}
                                return
                            }

                            val isScreenOff = intent.action == Intent.ACTION_SCREEN_OFF
                            activityScope.launch {
                                val state = hardwareManager.getRawHardwareState().toMutableMap()
                                if (isScreenOff) state["screen_off"] = true
                                
                                Handler(Looper.getMainLooper()).post {
                                    try { events?.success(state) } catch (e: Exception) {}
                                }
                            }
                        }
                    }
                    
                    val filter = IntentFilter().apply {
                        addAction(android.bluetooth.BluetoothAdapter.ACTION_STATE_CHANGED)
                        addAction(android.net.wifi.WifiManager.WIFI_STATE_CHANGED_ACTION)
                        addAction(android.media.AudioManager.RINGER_MODE_CHANGED_ACTION)
                        addAction(Intent.ACTION_AIRPLANE_MODE_CHANGED)
                        addAction(android.location.LocationManager.PROVIDERS_CHANGED_ACTION)
                        addAction(android.app.NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
                        addAction(Intent.ACTION_SCREEN_OFF)
                        addAction(Intent.ACTION_BATTERY_CHANGED)
                        addAction(Intent.ACTION_POWER_CONNECTED)
                        addAction(Intent.ACTION_POWER_DISCONNECTED)
                    }
                    
                    applicationContext.registerSystemReceiver(hardwareReceiver, filter, exported = false)
                    
                    activityScope.launch {
                        val initialState = hardwareManager.getRawHardwareState().toMutableMap()
                        val initBattery: Intent? = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { ifilter -> applicationContext.registerReceiver(null, ifilter) }
                        val initLevel: Int = initBattery?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
                        val initScale: Int = initBattery?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
                        initialState["battery_level"] = if (initLevel != -1 && initScale != -1) (initLevel * 100 / initScale.toFloat()).toInt() else 100
                        val initStatus: Int = initBattery?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ?: -1
                        initialState["battery_charging"] = initStatus == android.os.BatteryManager.BATTERY_STATUS_CHARGING || initStatus == android.os.BatteryManager.BATTERY_STATUS_FULL
                        Handler(Looper.getMainLooper()).post { 
                            try { events?.success(initialState) } catch (e: Exception) {}
                        }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    hardwareReceiver?.let { try { applicationContext.unregisterReceiver(it) } catch (e: Exception) {} }
                    hardwareReceiver = null
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PACKAGE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    packageReceiver?.let { try { applicationContext.unregisterReceiver(it) } catch (e: Exception) {} }

                    packageReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            val action = intent?.action
                            val data = intent?.data
                            val pkg = data?.schemeSpecificPart
                            val isReplacing = intent?.getBooleanExtra(Intent.EXTRA_REPLACING, false) ?: false
                            
                            Handler(Looper.getMainLooper()).postDelayed({
                                if ((action == Intent.ACTION_PACKAGE_ADDED || action == Intent.ACTION_PACKAGE_REPLACED) && pkg != null) {
                                    try {
                                        hardwareManager.invalidateAppCache()
                                        val pm = applicationContext.packageManager
                                        
                                        var label = pkg
                                        try {
                                            val appInfo = pm.getApplicationInfo(pkg, 0)
                                            label = pm.getApplicationLabel(appInfo).toString()
                                        } catch (e: Exception) {
                                            Log.w(TAG, "Application label not fully indexed yet for $pkg")
                                        }
                                        
                                        events?.success(mapOf(
                                            "type" to "APP_INSTALLED", 
                                            "package" to pkg, 
                                            "label" to label,
                                            "isUpdate" to isReplacing
                                        ))
                                        return@postDelayed
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Fatal error resolving package: $pkg", e)
                                    }
                                } else if (action == Intent.ACTION_PACKAGE_REMOVED && pkg != null) {
                                    if (!isReplacing) {
                                        hardwareManager.invalidateAppCache()
                                        try { events?.success(mapOf("type" to "APP_REMOVED", "package" to pkg)) } catch (e: Exception) {}
                                        return@postDelayed
                                    }
                                }
                                try { events?.success(mapOf("type" to "UNKNOWN", "action" to action)) } catch (e: Exception) {}
                            }, 800)
                        }
                    }
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_PACKAGE_ADDED)
                        addAction(Intent.ACTION_PACKAGE_REMOVED)
                        addAction(Intent.ACTION_PACKAGE_REPLACED)
                        addDataScheme("package")
                    }
                    applicationContext.registerSystemReceiver(packageReceiver, filter, exported = false)
                }
                override fun onCancel(arguments: Any?) {
                    packageReceiver?.let { try { applicationContext.unregisterReceiver(it) } catch (e: Exception) {} }
                    packageReceiver = null
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_EVENTS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val downloadPath = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath
                    val file = File(downloadPath)
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        downloadObserver = object : FileObserver(file, CLOSE_WRITE or MOVED_TO) {
                            override fun onEvent(event: Int, path: String?) {
                                if (path != null && !path.endsWith(".crdownload") && !path.endsWith(".tmp") && !path.endsWith(".pending") && !path.startsWith(".")) {
                                    val fullPath = "$downloadPath/$path"
                                    Handler(Looper.getMainLooper()).post {
                                        try { events?.success(mapOf("type" to "FILE_DOWNLOADED", "path" to fullPath, "name" to path)) } catch (e: Exception) {}
                                    }
                                }
                            }
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        downloadObserver = object : FileObserver(downloadPath, CLOSE_WRITE or MOVED_TO) {
                            override fun onEvent(event: Int, path: String?) {
                                if (path != null && !path.endsWith(".crdownload") && !path.endsWith(".tmp") && !path.endsWith(".pending") && !path.startsWith(".")) {
                                    val fullPath = "$downloadPath/$path"
                                    Handler(Looper.getMainLooper()).post {
                                        try { events?.success(mapOf("type" to "FILE_DOWNLOADED", "path" to fullPath, "name" to path)) } catch (e: Exception) {}
                                    }
                                }
                            }
                        }
                    }
                    downloadObserver?.startWatching()
                }
                override fun onCancel(arguments: Any?) {
                    downloadObserver?.stopWatching()
                    downloadObserver = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getHardwareState" -> hardwareManager.getHardwareState(result)
                "setSystemBrightness" -> hardwareManager.setSystemBrightness(call, result)
                "toggleHardware" -> hardwareManager.toggleHardware(call, result)
                "getPermissionStatuses" -> hardwareManager.getPermissionStatuses(result)
                "openSettings" -> hardwareManager.openCustomSettings(call, result)
                "lockScreen" -> hardwareManager.lockScreen(result)
                "dismissSystemLock" -> hardwareManager.dismissSystemLock(result)
                "isDeviceLocked" -> hardwareManager.isDeviceLocked(result) 
                "checkAndClearScreenOffFlag" -> hardwareManager.checkAndClearScreenOffFlag(result)
                "getStorageStats" -> hardwareManager.getStorageStats(result)
                "getDisks" -> hardwareManager.getDisks(result)
                "setStatusBarColor" -> hardwareManager.setStatusBarColor(call, result)
                
                "showPowerDialog" -> { 
                    val service = LauncherAccessibilityService.instance
                    if (service != null) {
                        result.success(service.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_POWER_DIALOG))
                    } else {
                        result.success(false) 
                    }
                }
                "toggleRecents" -> { 
                    val service = LauncherAccessibilityService.instance
                    if (service != null) {
                        result.success(service.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_RECENTS))
                    } else {
                        result.success(false) 
                    }
                }
                
                "getActiveNotifications" -> notificationManager.getActiveNotifications(result)
                "triggerNotificationAction" -> notificationManager.triggerNotificationAction(call, result)
                "dismissNotification" -> notificationManager.dismissNotification(call, result)
                "clearAllNotifications" -> notificationManager.clearAllNotifications(result)
                "expandNotificationPanel" -> notificationManager.expandNotificationPanel(result)
                
                "launchApp" -> appManager.launchApp(call, result)
                "uninstallApp" -> appManager.uninstallApp(call, result)
                "getAvailableIconPacks" -> appManager.getAvailableIconPacks(result)
                "applyIconPack" -> appManager.applyIconPack(call, result)
                
                "searchMedia" -> mediaManager.searchMedia(call, result)
                "getFilesInDirectory" -> mediaManager.getFilesInDirectory(call, result)
                "openFile" -> mediaManager.openFile(call, result)
                "shareFile" -> mediaManager.shareFile(call, result)
                "shareText" -> mediaManager.shareText(call, result) 
                "openWebSearch" -> mediaManager.openWebSearch(call, result)
                "saveToDownloads" -> mediaManager.saveToDownloads(call, result)
                "deleteFile" -> mediaManager.deleteFile(call, result)

                "openSystemDocumentPicker" -> {
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val fallback = Intent(Intent.ACTION_GET_CONTENT).apply {
                                type = "*/*"
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(fallback)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.success(false)
                        }
                    }
                }
                
                "pickWidget" -> widgetEngine.pickWidget(result)
                "removeWidget" -> widgetEngine.removeWidget(call, result)
                "updateWidgetSize" -> widgetEngine.updateWidgetSize(call, result)

                "sendMediaCommand" -> {
                    val command = call.argument<String>("command") ?: ""
                    val controller = LauncherNotificationService.activeMediaController
                    
                    if (controller != null) {
                        try {
                            when (command) {
                                "play_pause" -> {
                                    if (controller.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING) {
                                        controller.transportControls.pause()
                                    } else {
                                        controller.transportControls.play()
                                    }
                                }
                                "next" -> controller.transportControls.skipToNext()
                                "prev" -> controller.transportControls.skipToPrevious()
                            }
                            result.success(true)
                            return@setMethodCallHandler
                        } catch (e: Exception) {
                            Log.w(TAG, "MediaController failed, falling back to KeyEvent", e)
                            LauncherNotificationService.activeMediaController = null
                        }
                    }
                    
                    val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val eventTime = android.os.SystemClock.uptimeMillis()
                    val keyCode = when(command) {
                        "play_pause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                        "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                        "prev" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                        else -> KeyEvent.KEYCODE_UNKNOWN
                    }
                    if (keyCode != KeyEvent.KEYCODE_UNKNOWN) {
                        audioManager.dispatchMediaKeyEvent(KeyEvent(eventTime, eventTime, KeyEvent.ACTION_DOWN, keyCode, 0))
                        audioManager.dispatchMediaKeyEvent(KeyEvent(eventTime, eventTime, KeyEvent.ACTION_UP, keyCode, 0))
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                
                "restartApp" -> {
                    val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    }
                    if (intent != null) {
                        startActivity(intent)
                        finishAffinity() 
                    }
                    result.success(true)
                }
                
                else -> result.notImplemented()
            }
        }
    }
}