package com.samuel.winlauncher

import android.annotation.SuppressLint
import android.app.Activity
import android.app.SearchManager
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.net.TrafficStats
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

fun Context.registerSystemReceiver(receiver: BroadcastReceiver?, filter: IntentFilter, exported: Boolean = true): Intent? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        val flag = if (exported) Context.RECEIVER_EXPORTED else Context.RECEIVER_NOT_EXPORTED
        registerReceiver(receiver, filter, flag)
    } else {
        registerReceiver(receiver, filter)
    }
}

class HardwareManager(private val activity: Activity) {
    private val TAG = "Win11HardwareManager"
    private val job = SupervisorJob()
    private val scope = CoroutineScope(Dispatchers.IO + job)
    
    private var cachedApps: List<android.content.pm.ResolveInfo>? = null
    private var isReceiverRegistered = false
    
    private var screenOffReceiver: BroadcastReceiver? = null
    private var torchCallback: CameraManager.TorchCallback? = null

    private var lastNetSampleTime: Long = 0
    private var lastRxBytes: Long = 0
    private var lastTxBytes: Long = 0
    private var isTorchOn = false

    // NEW: Callback to notify MainActivity when hardware states change outside normal intents
    var onHardwareChangedListener: (() -> Unit)? = null

    companion object {
        var wasScreenOff = false
    }

    fun initPersistentReceiver() {
        if (!isReceiverRegistered) {
            screenOffReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                        wasScreenOff = true
                    }
                }
            }
            val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
            activity.applicationContext.registerSystemReceiver(screenOffReceiver, filter, exported = false)
            isReceiverRegistered = true
        }

        runCatching {
            val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            torchCallback = object : CameraManager.TorchCallback() {
                override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
                    isTorchOn = enabled
                    // Trigger instant broadcast to Flutter
                    onHardwareChangedListener?.invoke() 
                }
            }
            cameraManager.registerTorchCallback(torchCallback!!, Handler(Looper.getMainLooper()))
        }
    }

    fun checkAndClearScreenOffFlag(result: MethodChannel.Result) {
        val flag = wasScreenOff
        wasScreenOff = false
        result.safeSuccess(activity, flag)
    }

    fun onDestroy() {
        job.cancel()
        if (isReceiverRegistered && screenOffReceiver != null) {
            try { 
                activity.applicationContext.unregisterReceiver(screenOffReceiver) 
            } catch (e: Exception) {}
            isReceiverRegistered = false
            screenOffReceiver = null
        }
        runCatching {
            val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            torchCallback?.let { cameraManager.unregisterTorchCallback(it) }
        }
    }

    fun invalidateAppCache() {
        cachedApps = null
    }

    fun registerUsbChannel(messenger: BinaryMessenger) {
        try {
            EventChannel(messenger, "win_launcher/usb_events").setStreamHandler(
                object : EventChannel.StreamHandler {
                    private var usbReceiver: BroadcastReceiver? = null
                    
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        usbReceiver = object : BroadcastReceiver() {
                            override fun onReceive(context: Context, intent: Intent) {
                                when (intent.action) {
                                    UsbManager.ACTION_USB_DEVICE_ATTACHED,
                                    "com.samuel.winlauncher.USB_ATTACHED_LOCAL" -> {
                                        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                                                ?: intent.getParcelableExtra("device", UsbDevice::class.java)
                                        } else {
                                            @Suppress("DEPRECATION")
                                            intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                                                ?: intent.getParcelableExtra<UsbDevice>("device")
                                        }
                                                  
                                        val isMassStorage = device?.deviceClass == 8 || (0 until (device?.interfaceCount ?: 0)).any { idx ->
                                            device?.getInterface(idx)?.interfaceClass == 8
                                        }

                                        if (isMassStorage) {
                                            try {
                                                events?.success(mapOf(
                                                    "type" to "USB_ATTACHED",
                                                    "deviceName" to (device?.productName ?: "USB Drive")
                                                ))
                                            } catch (e: Exception) {}
                                        }
                                    }
                                    UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                                        try { events?.success(mapOf("type" to "USB_DETACHED")) } catch (e: Exception) {}
                                    }
                                }
                            }
                        }
                        val filter = IntentFilter().apply {
                            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
                            addAction("com.samuel.winlauncher.USB_ATTACHED_LOCAL")
                        }
                        activity.registerSystemReceiver(usbReceiver, filter, exported = false)
                    }

                    override fun onCancel(arguments: Any?) {
                        usbReceiver?.let { activity.unregisterReceiver(it) }
                        usbReceiver = null
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize USB event channel", e)
        }
    }

    fun getSystemPerformanceStats(result: MethodChannel.Result) {
        scope.launch {
            try {
                val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
                val memInfo = android.app.ActivityManager.MemoryInfo()
                am?.getMemoryInfo(memInfo)
                val totalRamMb = (memInfo.totalMem / (1024 * 1024)).toInt()
                val availRamMb = (memInfo.availMem / (1024 * 1024)).toInt()
                val usedRamMb = totalRamMb - availRamMb
                val ramPercent = if (totalRamMb > 0) ((usedRamMb.toFloat() / totalRamMb.toFloat()) * 100).toInt() else 0

                val now = System.currentTimeMillis()
                val currentRx = TrafficStats.getTotalRxBytes()
                val currentTx = TrafficStats.getTotalTxBytes()

                var rxSpeedKbps = 0.0
                var txSpeedKbps = 0.0

                if (lastNetSampleTime > 0 && now > lastNetSampleTime) {
                    val timeDiffSec = (now - lastNetSampleTime) / 1000.0
                    if (timeDiffSec > 0 && currentRx >= lastRxBytes && currentTx >= lastTxBytes) {
                        rxSpeedKbps = ((currentRx - lastRxBytes) / 1024.0) / timeDiffSec
                        txSpeedKbps = ((currentTx - lastTxBytes) / 1024.0) / timeDiffSec
                    }
                }
                lastNetSampleTime = now
                lastRxBytes = currentRx
                lastTxBytes = currentTx

                var tempCelsius = 35.0
                try {
                    val batteryIntent = activity.applicationContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                    val rawTemp = batteryIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
                    if (rawTemp > 0) {
                        tempCelsius = rawTemp / 10.0
                    }
                } catch (e: Exception) {}

                val stats = mapOf(
                    "ram_used_mb" to usedRamMb,
                    "ram_total_mb" to totalRamMb,
                    "ram_percent" to ramPercent,
                    "rx_kbps" to rxSpeedKbps,
                    "tx_kbps" to txSpeedKbps,
                    "cpu_temp" to tempCelsius
                )
                result.safeSuccess(activity, stats)
            } catch (e: Exception) {
                result.safeError(activity, "PERF_STATS_ERROR", e.message, null)
            }
        }
    }

    private suspend fun launchAppByName(nameQuery: String, packageQuery: String = ""): Boolean = withContext(Dispatchers.IO) {
        try {
            val pm = activity.packageManager
            if (cachedApps == null) {
                val mainIntent = Intent(Intent.ACTION_MAIN, null).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
                cachedApps = pm.queryIntentActivities(mainIntent, 0)
            }
            val apps = cachedApps!!
            val nameQueryLower = nameQuery.lowercase(Locale.ROOT)
            val packageQueryLower = packageQuery.lowercase(Locale.ROOT)

            for (resolveInfo in apps) {
                val label = resolveInfo.loadLabel(pm).toString().lowercase(Locale.ROOT)
                if (label == nameQueryLower) {
                    val intent = pm.getLaunchIntentForPackage(resolveInfo.activityInfo.packageName)
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(intent)
                        return@withContext true
                    }
                }
            }

            for (resolveInfo in apps) {
                val label = resolveInfo.loadLabel(pm).toString().lowercase(Locale.ROOT)
                if (label.startsWith(nameQueryLower)) {
                    val intent = pm.getLaunchIntentForPackage(resolveInfo.activityInfo.packageName)
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(intent)
                        return@withContext true
                    }
                }
            }

            for (resolveInfo in apps) {
                val label = resolveInfo.loadLabel(pm).toString().lowercase(Locale.ROOT)
                val pkgName = resolveInfo.activityInfo.packageName.lowercase(Locale.ROOT)
                
                if (label.contains(nameQueryLower) || (packageQueryLower.isNotEmpty() && pkgName.contains(packageQueryLower))) {
                    val intent = pm.getLaunchIntentForPackage(resolveInfo.activityInfo.packageName)
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(intent)
                        return@withContext true
                    }
                }
            }
            false
        } catch (e: Exception) { 
            Log.e(TAG, "Error resolving app intent for $nameQuery", e)
            false 
        }
    }

    @SuppressLint("MissingPermission")
    fun getRawHardwareState(): Map<String, Any> {
        val states = mutableMapOf<String, Any>()
        
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val hasPermission = ContextCompat.checkSelfPermission(
                    activity,
                    android.Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED

                if (hasPermission) {
                    val btManager = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager
                    states["Bluetooth"] = btManager?.adapter?.isEnabled == true
                } else {
                    states["Bluetooth"] = false
                }
            } else {
                @Suppress("DEPRECATION")
                val btAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
                states["Bluetooth"] = btAdapter?.isEnabled == true
            }
        }.onFailure { states["Bluetooth"] = false }

        runCatching {
            val wifiManager = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as? android.net.wifi.WifiManager
            states["Wi-Fi"] = wifiManager?.isWifiEnabled == true
        }.onFailure { states["Wi-Fi"] = false }

        runCatching {
            val wifiManager = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as? android.net.wifi.WifiManager
            val method = wifiManager?.javaClass?.getMethod("isWifiApEnabled")
            states["Hotspot"] = method?.invoke(wifiManager) as? Boolean == true
        }.onFailure { states["Hotspot"] = false }

        states["Flash"] = isTorchOn

        runCatching {
            states["Rotate"] = Settings.System.getInt(activity.contentResolver, Settings.System.ACCELEROMETER_ROTATION, 0) == 1
        }.onFailure { states["Rotate"] = false }

        runCatching {
            states["Airplane mode"] = Settings.Global.getInt(activity.contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0) == 1
        }.onFailure { states["Airplane mode"] = false }

        runCatching {
            states["Data"] = Settings.Global.getInt(activity.contentResolver, "mobile_data", 0) == 1
        }.onFailure { states["Data"] = false }

        runCatching {
            val notifManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
            states["DND"] = notifManager?.currentInterruptionFilter != android.app.NotificationManager.INTERRUPTION_FILTER_ALL
        }.onFailure { states["DND"] = false }

        runCatching {
            val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
            states["Ring"] = audioManager?.ringerMode == android.media.AudioManager.RINGER_MODE_NORMAL
        }.onFailure { states["Ring"] = true }

        runCatching {
            val locationManager = activity.getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
            states["Location"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) { locationManager?.isLocationEnabled == true } else {
                @Suppress("DEPRECATION")
                Settings.Secure.getInt(activity.contentResolver, Settings.Secure.LOCATION_MODE, Settings.Secure.LOCATION_MODE_OFF) != Settings.Secure.LOCATION_MODE_OFF
            }
        }.onFailure { states["Location"] = false }

        runCatching {
            val currentNightMode = activity.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
            states["Dark Theme"] = currentNightMode == android.content.res.Configuration.UI_MODE_NIGHT_YES
        }.onFailure { states["Dark Theme"] = false }

        runCatching {
            states["Brightness"] = Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, 0) == 1
            val brightnessInt = Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128)
            states["sys_brightness"] = (brightnessInt / 255.0).coerceIn(0.0, 1.0)
        }.onFailure { states["Brightness"] = false; states["sys_brightness"] = 0.5 }

        // Fetch real-time battery status directly from the sticky intent for instant synchronization
        runCatching {
            val batteryIntent = activity.applicationContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1

            states["battery_level"] = if (level != -1 && scale != -1) (level * 100 / scale.toFloat()).toInt() else 100
            states["battery_charging"] = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        }.onFailure {
            states["battery_level"] = 100
            states["battery_charging"] = false
        }

        return states
    }

    fun getHardwareState(result: MethodChannel.Result) {
        result.safeSuccess(activity, getRawHardwareState())
    }

    fun setSystemBrightness(call: MethodCall, result: MethodChannel.Result) {
        val brightness = call.argument<Double>("brightness") ?: 0.5
        try {
            if (!Settings.System.canWrite(activity)) {
                val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                    data = Uri.parse("package:" + activity.packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(intent)
                result.safeSuccess(activity, null)
                return
            }
            val brightnessInt = (brightness * 255).toInt().coerceIn(0, 255)
            Settings.System.putInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, brightnessInt)
            result.safeSuccess(activity, null)
        } catch (e: Exception) { 
            Log.e(TAG, "Error setting system brightness", e)
            result.safeError(activity, "BRIGHTNESS_ERROR", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    fun toggleHardware(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key") ?: ""
        val enable = call.argument<Boolean>("enable") ?: false
        
        scope.launch(Dispatchers.Main) {
            try {
                when (key) {
                    "Flash" -> {
                        val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                        val cameraId = cameraManager.cameraIdList.firstOrNull { 
                            cameraManager.getCameraCharacteristics(it).get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE) == true 
                        }
                        if (cameraId != null) cameraManager.setTorchMode(cameraId, enable)
                    }
                    "Rotate", "Brightness" -> {
                        if (!Settings.System.canWrite(activity)) {
                            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                                data = Uri.parse("package:" + activity.packageName)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            activity.startActivity(intent)
                            result.safeSuccess(activity, null)
                            return@launch
                        }
                        if (key == "Rotate") {
                            Settings.System.putInt(activity.contentResolver, Settings.System.ACCELEROMETER_ROTATION, if (enable) 1 else 0)
                        } else {
                            Settings.System.putInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, if (enable) 1 else 0)
                        }
                    }
                    "Bluetooth" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        } else {
                            @Suppress("DEPRECATION")
                            val btAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
                            if (enable) btAdapter?.enable() else btAdapter?.disable()
                        }
                    }
                    "Wi-Fi" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            activity.startActivity(Intent("android.settings.panel.action.WIFI").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        } else {
                            try {
                                val wifiManager = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as? android.net.wifi.WifiManager
                                @Suppress("DEPRECATION")
                                wifiManager?.isWifiEnabled = enable
                            } catch (e: Exception) {
                                activity.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            }
                        }
                    }
                    "Data" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            activity.startActivity(Intent("android.settings.panel.action.INTERNET_CONNECTIVITY").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        } else {
                            activity.startActivity(Intent(Settings.ACTION_DATA_USAGE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                    }
                    "Dark Theme" -> {
                        val uiModeManager = activity.getSystemService(Context.UI_MODE_SERVICE) as? android.app.UiModeManager
                        try {
                            uiModeManager?.nightMode = if (enable) android.app.UiModeManager.MODE_NIGHT_YES else android.app.UiModeManager.MODE_NIGHT_NO
                        } catch (e: SecurityException) {
                            activity.startActivity(Intent(Settings.ACTION_DISPLAY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                    }
                    "Ring" -> {
                        val notifManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !notifManager.isNotificationPolicyAccessGranted) {
                            activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.safeSuccess(activity, null)
                            return@launch
                        }
                        val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                        audioManager?.ringerMode = if (enable) android.media.AudioManager.RINGER_MODE_NORMAL else android.media.AudioManager.RINGER_MODE_VIBRATE
                    }
                    "DND" -> {
                        val notifManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (!notifManager.isNotificationPolicyAccessGranted) {
                                activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.safeSuccess(activity, null)
                                return@launch
                            } else {
                                notifManager.setInterruptionFilter(
                                    if (enable) android.app.NotificationManager.INTERRUPTION_FILTER_NONE 
                                    else android.app.NotificationManager.INTERRUPTION_FILTER_ALL
                                )
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
                        val intent = Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_MUSIC).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        activity.startActivity(intent)
                    }
                    "Song Search" -> {
                        val intent = Intent("com.google.android.googlequicksearchbox.MUSIC_SEARCH").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        try {
                            activity.startActivity(intent)
                        } catch (e: Exception) {
                            val fallback = Intent(Intent.ACTION_WEB_SEARCH).apply {
                                putExtra(SearchManager.QUERY, "what song is this")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            activity.startActivity(fallback)
                        }
                    }
                    "Scan QR Code" -> {
                        var launched = launchAppByName("scanner", "scanner")
                        if (!launched) {
                            try {
                                val lensIntent = Intent(Intent.ACTION_VIEW, Uri.parse("googleapp://lens")).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                activity.startActivity(lensIntent)
                            } catch (e: Exception) {
                                try {
                                    val fallback = Intent("com.google.zxing.client.android.SCAN").apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    activity.startActivity(fallback)
                                } catch (e2: Exception) {
                                    val playStore = Intent(Intent.ACTION_VIEW, Uri.parse("market://search?q=qr scanner")).apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    activity.startActivity(playStore)
                                }
                            }
                        }
                    }
                }
                result.safeSuccess(activity, null)
            } catch (e: Exception) { 
                Log.e(TAG, "Error toggling hardware state: $key", e)
                result.safeError(activity, "TOGGLE_ERROR", e.message, null)
            }
        }
    }

    fun getPermissionStatuses(result: MethodChannel.Result) {
        val permissions = mutableMapOf<String, Boolean>()
        
        permissions["storage"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val images = ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.READ_MEDIA_IMAGES
            ) == PackageManager.PERMISSION_GRANTED
            val video = ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.READ_MEDIA_VIDEO
            ) == PackageManager.PERMISSION_GRANTED
            images && video
        } else {
            val readGranted = ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
            val writeGranted = ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
            readGranted && writeGranted
        }

        val listeners = Settings.Secure.getString(activity.contentResolver, "enabled_notification_listeners")
        val expectedComponent = ComponentName(activity, LauncherNotificationService::class.java).flattenToString()
        permissions["notification"] = listeners?.split(":")?.any { it == expectedComponent } == true

        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        permissions["admin"] = dpm.isAdminActive(ComponentName(activity, LauncherAdminReceiver::class.java))
        permissions["write_settings"] = Settings.System.canWrite(activity)

        result.safeSuccess(activity, permissions)
    }

    fun openCustomSettings(call: MethodCall, result: MethodChannel.Result) {
        val type = call.argument<String>("type") ?: ""
        try {
            var useNewTask = true
            val intent = when (type) {
                "home" -> Intent(Settings.ACTION_HOME_SETTINGS)
                "wifi" -> { 
                    useNewTask = false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        Intent("android.settings.panel.action.WIFI") 
                    } else {
                        Intent(Settings.ACTION_WIFI_SETTINGS) 
                    }
                }
                "data" -> { 
                    useNewTask = false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        Intent("android.settings.panel.action.INTERNET_CONNECTIVITY") 
                    } else {
                        Intent(Settings.ACTION_DATA_USAGE_SETTINGS) 
                    }
                }
                "battery_saver" -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                "vpn" -> Intent(Settings.ACTION_VPN_SETTINGS)
                "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                "add_account" -> Intent(Settings.ACTION_ADD_ACCOUNT)
                "notification_access", "notification_listener" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                "manage_apps" -> Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS)
                "default_apps" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS) else Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS)
                "print_settings" -> Intent(Settings.ACTION_PRINT_SETTINGS)
                "storage" -> {
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:" + activity.packageName)
                    }
                }
                "display" -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
                "sound" -> Intent(Settings.ACTION_SOUND_SETTINGS)
                "airplane" -> Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS)
                "location" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                "hotspot" -> Intent(Settings.ACTION_WIRELESS_SETTINGS)
                "locale" -> Intent(Settings.ACTION_LOCALE_SETTINGS)
                "keyboard" -> Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                "write_settings" -> {
                    Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                        data = Uri.parse("package:" + activity.packageName)
                    }
                }
                "admin" -> {
                    useNewTask = false
                    Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, ComponentName(activity, LauncherAdminReceiver::class.java))
                        putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Required to enable double tap to lock functionality.")
                    }
                }
                else -> Intent(Settings.ACTION_SETTINGS)
            }
            if (useNewTask) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            activity.startActivity(intent)
            result.safeSuccess(activity, null)
        } catch (e: Exception) { 
            Log.e(TAG, "Error opening custom settings: $type", e)
            try {
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:" + activity.packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                result.safeSuccess(activity, null)
            } catch (e2: Exception) {
                result.safeError(activity, "SETTINGS_OPEN_FAILED", e2.message, null)
            }
        }
    }

    fun lockScreen(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val service = LauncherAccessibilityService.instance
                if (service != null) {
                    val success = service.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
                    if (success) {
                        result.safeSuccess(activity, true)
                        return
                    }
                }
            }

            val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminComponent = ComponentName(activity, LauncherAdminReceiver::class.java)
            if (dpm.isAdminActive(adminComponent)) {
                dpm.lockNow()
                result.safeSuccess(activity, true)
            } else {
                try {
                    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                        putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Required to enable double tap to lock functionality.")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    activity.startActivity(intent)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to launch Device Admin intent", e)
                }
                result.safeSuccess(activity, false)
            }
        } catch (e: Exception) { 
            Log.e(TAG, "Error locking device", e)
            result.safeError(activity, "LOCK_DEVICE_FAILED", e.message, null)
        }
    }

    fun dismissSystemLock(result: MethodChannel.Result) {
        val keyguardManager = activity.getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (keyguardManager.isKeyguardLocked) {
                keyguardManager.requestDismissKeyguard(activity, object : android.app.KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissSucceeded() {
                        result.safeSuccess(activity, true)
                    }
                    override fun onDismissCancelled() {
                        result.safeSuccess(activity, false)
                    }
                    override fun onDismissError() {
                        result.safeSuccess(activity, false)
                    }
                })
            } else {
                result.safeSuccess(activity, true)
            }
        } else {
            @Suppress("DEPRECATION")
            activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
            result.safeSuccess(activity, true)
        }
    }

    fun isDeviceLocked(result: MethodChannel.Result) {
        val keyguardManager = activity.getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
        result.safeSuccess(activity, keyguardManager.isKeyguardLocked)
    }

    fun getStorageStats(result: MethodChannel.Result) {
        scope.launch {
            try {
                val path = Environment.getExternalStorageDirectory().path
                val stat = StatFs(path)
                val total = stat.blockSizeLong * stat.blockCountLong
                val free = stat.blockSizeLong * stat.availableBlocksLong
                result.safeSuccess(activity, mapOf("total" to total.toDouble(), "free" to free.toDouble()))
            } catch (e: Exception) { 
                Log.e(TAG, "Error getting storage stats", e)
                result.safeError(activity, "STORAGE_STATS_FAILED", e.message, null)
            }
        }
    }

    fun getDisks(result: MethodChannel.Result) {
        scope.launch {
            try {
                val storageManager = activity.getSystemService(Context.STORAGE_SERVICE) as StorageManager
                val disks = mutableListOf<Map<String, Any>>()
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    val volumes: List<StorageVolume> = storageManager.storageVolumes
                    var driveLetterCode = 'D'
                    for (volume in volumes) {
                        if (volume.state == Environment.MEDIA_MOUNTED) {
                            val file = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                volume.directory
                            } else {
                                try {
                                    val getPathMethod = volume.javaClass.getMethod("getPath")
                                    File(getPathMethod.invoke(volume) as String)
                                } catch (e: Exception) { null }
                            }

                            if (file != null && file.exists() && file.canRead()) {
                                val stat = StatFs(file.path)
                                val total = stat.blockSizeLong * stat.blockCountLong
                                val free = stat.blockSizeLong * stat.availableBlocksLong
                                val isPrimary = volume.isPrimary
                                val label = if (isPrimary) {
                                    "Local Disk (C:)"
                                } else {
                                    val driveType = if (volume.isRemovable) "Removable Disk" else "Local Disk"
                                    "$driveType ($driveLetterCode:)"
                                }

                                if (!isPrimary) {
                                    driveLetterCode++
                                }

                                disks.add(mapOf(
                                    "path" to file.path,
                                    "label" to label,
                                    "isRemovable" to volume.isRemovable,
                                    "isPrimary" to isPrimary,
                                    "total" to total.toDouble(),
                                    "free" to free.toDouble()
                                ))
                            }
                        }
                    }
                }
                
                if (disks.isEmpty()) {
                    val path = Environment.getExternalStorageDirectory().path
                    val stat = StatFs(path)
                    val total = stat.blockSizeLong * stat.blockCountLong
                    val free = stat.blockSizeLong * stat.availableBlocksLong
                    disks.add(mapOf(
                        "path" to path,
                        "label" to "Local Disk (C:)",
                        "isRemovable" to false,
                        "isPrimary" to true,
                        "total" to total.toDouble(),
                        "free" to free.toDouble()
                    ))
                }
                result.safeSuccess(activity, disks)
            } catch (e: Exception) { 
                Log.e(TAG, "Error getting disks", e)
                result.safeError(activity, "DISKS_ERROR", e.message, null)
            }
        }
    }

    fun setStatusBarColor(call: MethodCall, result: MethodChannel.Result) {
        val darkIcons = call.argument<Boolean>("darkIcons") ?: true
        val colorHex = call.argument<String>("color") ?: "#FFFFFF"
        try {
            if (Build.VERSION.SDK_INT < 35) {
                try {
                    @Suppress("DEPRECATION")
                    activity.window.statusBarColor = android.graphics.Color.parseColor(colorHex)
                } catch (e: Exception) {
                    Log.w(TAG, "Legacy status bar coloring skipped: ${e.message}")
                }
            }

            val windowInsetsController = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
            windowInsetsController.isAppearanceLightStatusBars = darkIcons
            result.safeSuccess(activity, null)
        } catch (e: Exception) { 
            Log.e(TAG, "Error configuring status bar appearance", e)
            result.safeError(activity, "STATUS_BAR_ERROR", e.message, null) 
        }
    }
}