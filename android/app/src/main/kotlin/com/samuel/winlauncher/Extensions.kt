package com.samuel.winlauncher

import android.app.Activity
import android.util.Log
import io.flutter.plugin.common.MethodChannel

fun MethodChannel.Result.safeSuccess(activity: Activity, data: Any?) {
    activity.runOnUiThread {
        try {
            this.success(data)
        } catch (e: IllegalStateException) {
            Log.w("Win11Launcher", "Result already handled: ${e.message}")
        } catch (e: Exception) {
            Log.e("Win11Launcher", "Unexpected error in safeSuccess", e)
        }
    }
}

fun MethodChannel.Result.safeError(activity: Activity, code: String, msg: String?, details: Any? = null) {
    activity.runOnUiThread {
        try {
            this.error(code, msg, details)
        } catch (e: IllegalStateException) {
            Log.w("Win11Launcher", "Result already handled: ${e.message}")
        } catch (e: Exception) {
            Log.e("Win11Launcher", "Unexpected error in safeError", e)
        }
    }
}