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
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Classes required by Android to display the app in system settings
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
                "expandNotificationPanel" -> {
                    expandNotificationPanel()
                    result.success(null)
                }
                "openSettings" -> {
                    val type = call.argument<String>("type")
                    openCustomSettings(type)
                    result.success(null)
                }
                "getPermissionStatuses" -> {
                    result.success(checkAllPermissions())
                }
                "lockScreen" -> {
                    lockScreen()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // NEW: Physically turns off the phone screen
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

        // 1. Storage Check (Android 11-14)
        permissions["storage"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }

        // 2. Notification Listener Check
        val listeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        permissions["notification"] = listeners != null && listeners.contains(packageName)

        // 3. Accessibility Check
        var accessEnabled = 0
        try {
            accessEnabled = Settings.Secure.getInt(contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED)
        } catch (_: Exception) {}
        val accessServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        permissions["accessibility"] = accessEnabled == 1 && accessServices != null && accessServices.contains(packageName)

        // 4. Device Admin Check
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, LauncherAdminReceiver::class.java)
        permissions["admin"] = dpm.isAdminActive(adminComponent)

        // 5. Write Settings Check
        permissions["write_settings"] = Settings.System.canWrite(this)

        return permissions
    }

    private fun openCustomSettings(type: String?) {
        try {
            var useNewTask = true // Controls the intent flag
            
            val intent = when (type) {
                "storage" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                            data = Uri.parse("package:$packageName")
                        }
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                    }
                }
                "notification_access" -> Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                "admin" -> {
                    useNewTask = false // CRITICAL: Disables the flag for Admin
                    val adminComponent = ComponentName(this, LauncherAdminReceiver::class.java)
                    Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                        putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Required to enable double tap to sleep and screen lock.")
                    }
                }
                "write_settings" -> {
                    Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                }
                "print_settings" -> Intent(Settings.ACTION_PRINT_SETTINGS)
                "manage_apps" -> Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS)
                "default_apps" -> Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                "add_account" -> Intent(Settings.ACTION_ADD_ACCOUNT)
                "locale" -> Intent(Settings.ACTION_LOCALE_SETTINGS)
                "keyboard" -> Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                else -> Intent(Settings.ACTION_SETTINGS)
            }
            
            // Only applies the flag if it's NOT the Admin intent
            if (useNewTask) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}