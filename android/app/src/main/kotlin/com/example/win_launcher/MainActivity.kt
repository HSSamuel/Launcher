package com.example.win_launcher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "win_launcher/native"
    private val NOTIF_CHANNEL = "win_launcher/notifications"
    private val HARDWARE_CHANNEL = "win_launcher/hardware_events"

    private val intentHandler by lazy { IntentHandler(this) }
    private val widgetEngine by lazy { WidgetEngine(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // CRITICAL FIX: Tell Android to draw this Activity OVER the system lock screen and wake the screen
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
    }

    override fun onResume() {
        super.onResume()
        widgetEngine.onResume()
    }

    override fun onPause() {
        super.onPause()
        widgetEngine.onPause()
    }

    override fun onDestroy() {
        super.onDestroy()
        widgetEngine.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        widgetEngine.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                private var receiver: BroadcastReceiver? = null
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            events?.success(intentHandler.getRawHardwareState())
                        }
                    }
                    val filter = IntentFilter().apply {
                        addAction(android.bluetooth.BluetoothAdapter.ACTION_STATE_CHANGED)
                        addAction(android.net.wifi.WifiManager.WIFI_STATE_CHANGED_ACTION)
                        addAction(android.media.AudioManager.RINGER_MODE_CHANGED_ACTION)
                        addAction(Intent.ACTION_AIRPLANE_MODE_CHANGED)
                        addAction(android.location.LocationManager.PROVIDERS_CHANGED_ACTION)
                        addAction(android.app.NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
                    } else {
                        registerReceiver(receiver, filter)
                    }
                }
                override fun onCancel(arguments: Any?) {
                    receiver?.let { unregisterReceiver(it) }
                    receiver = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getHardwareState" -> intentHandler.getHardwareState(result)
                "setSystemBrightness" -> intentHandler.setSystemBrightness(call, result)
                
                "getActiveNotifications" -> intentHandler.getActiveNotifications(result)
                "triggerNotificationAction" -> intentHandler.triggerNotificationAction(call, result)
                "dismissNotification" -> intentHandler.dismissNotification(call, result)
                "clearAllNotifications" -> intentHandler.clearAllNotifications(result)
                "expandNotificationPanel" -> intentHandler.expandNotificationPanel(result)
                "getPermissionStatuses" -> intentHandler.getPermissionStatuses(result)
                "openSettings" -> intentHandler.openCustomSettings(call, result)
                "lockScreen" -> intentHandler.lockScreen(result)
                "launchApp" -> intentHandler.launchApp(call, result)
                "uninstallApp" -> intentHandler.uninstallApp(call, result)
                "toggleHardware" -> intentHandler.toggleHardware(call, result)
                "toggleRecents" -> intentHandler.toggleRecents(result)
                "showPowerDialog" -> intentHandler.showPowerDialog(result)
                "searchMedia" -> intentHandler.searchMedia(call, result)
                "openFile" -> intentHandler.openFile(call, result)
                "shareFile" -> intentHandler.shareFile(call, result)
                "openWebSearch" -> intentHandler.openWebSearch(call, result)
                "getStorageStats" -> intentHandler.getStorageStats(result)
                "setStatusBarColor" -> intentHandler.setStatusBarColor(call, result)
                
                "pickWidget" -> widgetEngine.pickWidget(result)
                "removeWidget" -> widgetEngine.removeWidget(call, result)
                "updateWidgetSize" -> widgetEngine.updateWidgetSize(call, result)
                else -> result.notImplemented()
            }
        }
    }
}