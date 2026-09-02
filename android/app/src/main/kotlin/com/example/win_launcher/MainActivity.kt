package com.example.win_launcher

import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import android.view.View
import android.view.WindowInsetsController
import android.view.accessibility.AccessibilityEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class LauncherAccessibilityService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}
}

class LauncherAdminReceiver : DeviceAdminReceiver()

class MainActivity: FlutterActivity() {
    private val CHANNEL = "win_launcher/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "expandNotificationPanel" -> { expandNotificationPanel(); result.success(null) }
                "openSettings" -> { openCustomSettings(call.argument<String>("type")); result.success(null) }
                "getPermissionStatuses" -> { result.success(checkAllPermissions()) }
                "lockScreen" -> { lockScreen(); result.success(null) }
                "getStorageStats" -> {
                    try {
                        val path = Environment.getExternalStorageDirectory().path
                        val stat = StatFs(path)
                        val total = stat.blockSizeLong * stat.blockCountLong
                        val free = stat.blockSizeLong * stat.availableBlocksLong
                        result.success(mapOf("total" to total.toDouble(), "free" to free.toDouble()))
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "setStatusBarColor" -> {
                    // NATIVE FIX: Physically turns the Android status bar white with dark icons
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
                            flags = if (darkIcons) {
                                flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                            } else {
                                flags and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv()
                            }
                            window.decorView.systemUiVisibility = flags
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("STATUS_BAR_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun lockScreen() {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, LauncherAdminReceiver::class.java)
        if (dpm.isAdminActive(adminComponent)) {
            dpm.lockNow()
        }
    }

    @SuppressLint("WrongConstant")
    private fun expandNotificationPanel() {
        try {
            val statusBarService = getSystemService("statusbar")
            val statusBarManager = Class.forName("android.app.StatusBarManager")
            val showMethod = statusBarManager.getMethod("expandNotificationsPanel")
            showMethod.invoke(statusBarService)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun checkAllPermissions(): Map<String, Boolean> {
        val permissions = mutableMapOf<String, Boolean>()
        permissions["storage"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else { true }

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
                "storage" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName"))
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                    }
                }
                "notification_access" -> Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                "admin" -> {
                    useNewTask = false
                    Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, ComponentName(this@MainActivity, LauncherAdminReceiver::class.java))
                        putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Required to enable double tap to sleep and screen lock.")
                    }
                }
                "write_settings" -> Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:$packageName"))
                "print_settings" -> Intent(Settings.ACTION_PRINT_SETTINGS)
                "manage_apps" -> Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS)
                "default_apps" -> Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                "add_account" -> Intent(Settings.ACTION_ADD_ACCOUNT)
                "locale" -> Intent(Settings.ACTION_LOCALE_SETTINGS)
                "keyboard" -> Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                else -> Intent(Settings.ACTION_SETTINGS)
            }
            if (useNewTask) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}