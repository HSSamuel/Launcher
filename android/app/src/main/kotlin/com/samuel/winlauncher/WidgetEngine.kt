package com.samuel.winlauncher

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class WidgetEngine(private val activity: Activity) {
    private val TAG = "Win11WidgetEngine"
    private val APPWIDGET_HOST_ID = 1024
    private val REQUEST_PICK_APPWIDGET = 5
    private val REQUEST_CREATE_APPWIDGET = 6
    
    var appWidgetManager: AppWidgetManager? = null
    var appWidgetHost: AppWidgetHost? = null
    private var pendingWidgetResult: MethodChannel.Result? = null
    private var pendingAppWidgetId: Int = -1
    private var configuringWidgetId: Int = -1 

    fun onCreate() {
        appWidgetManager = AppWidgetManager.getInstance(activity)
        appWidgetHost = AppWidgetHost(activity, APPWIDGET_HOST_ID)
    }

    fun onStart() {
        appWidgetHost?.startListening()
    }
    
    fun onStop() {
        appWidgetHost?.stopListening()
    }
    
    fun onDestroy() {
        appWidgetHost?.stopListening()
    }

    fun pickWidget(result: MethodChannel.Result) {
        pendingWidgetResult = result
        val appWidgetId = appWidgetHost?.allocateAppWidgetId() ?: -1
        pendingAppWidgetId = appWidgetId
        val pickIntent = Intent(AppWidgetManager.ACTION_APPWIDGET_PICK).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        activity.startActivityForResult(pickIntent, REQUEST_PICK_APPWIDGET)
    }

    fun removeWidget(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("appWidgetId") ?: -1
        if (id != -1) appWidgetHost?.deleteAppWidgetId(id)
        result.success(true)
    }

    fun updateWidgetSize(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("appWidgetId") ?: -1
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        if (id != -1 && width > 0 && height > 0) {
            try {
                val options = Bundle()
                val density = activity.resources.displayMetrics.density
                val dpWidth = (width / density).toInt()
                val dpHeight = (height / density).toInt()
                
                options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, dpWidth)
                options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, dpWidth)
                options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, dpHeight)
                options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, dpHeight)
                
                appWidgetManager?.updateAppWidgetOptions(id, options)
            } catch (e: Exception) { 
                Log.e(TAG, "Error updating widget size", e) 
            }
        }
        result.success(true)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PICK_APPWIDGET) {
            val returnedId = data?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, pendingAppWidgetId) ?: pendingAppWidgetId
            
            if (resultCode == Activity.RESULT_OK && returnedId != -1) {
                configureWidget(returnedId, data ?: Intent())
            } else {
                if (pendingAppWidgetId != -1) {
                    appWidgetHost?.deleteAppWidgetId(pendingAppWidgetId)
                }
                pendingWidgetResult?.success(null)
                pendingWidgetResult = null
            }
            pendingAppWidgetId = -1
        } else if (requestCode == REQUEST_CREATE_APPWIDGET) {
            val returnedId = data?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, configuringWidgetId) ?: configuringWidgetId
            val targetId = if (returnedId != -1) returnedId else configuringWidgetId
            
            if (resultCode == Activity.RESULT_OK && targetId != -1) {
                if (pendingWidgetResult != null) {
                    finishWidgetConfiguration(targetId)
                } else {
                    appWidgetHost?.deleteAppWidgetId(targetId)
                }
            } else {
                if (targetId != -1) appWidgetHost?.deleteAppWidgetId(targetId)
                pendingWidgetResult?.success(null)
                pendingWidgetResult = null
            }
            configuringWidgetId = -1
        }
    }

    private fun configureWidget(appWidgetId: Int, data: Intent) {
        val appWidgetInfo = appWidgetManager?.getAppWidgetInfo(appWidgetId)
        if (appWidgetInfo?.configure != null) {
            try {
                configuringWidgetId = appWidgetId
                val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_CONFIGURE).apply {
                    component = appWidgetInfo.configure
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                activity.startActivityForResult(intent, REQUEST_CREATE_APPWIDGET)
            } catch (e: SecurityException) {
                Log.w(TAG, "SecurityException: Widget configure activity is not exported. Bypassing config.", e)
                configuringWidgetId = -1
                finishWidgetConfiguration(appWidgetId)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start widget configuration", e)
                configuringWidgetId = -1
                appWidgetHost?.deleteAppWidgetId(appWidgetId)
                pendingWidgetResult?.success(null)
                pendingWidgetResult = null
            }
        } else {
            finishWidgetConfiguration(appWidgetId)
        }
    }

    private fun finishWidgetConfiguration(appWidgetId: Int) {
        val appWidgetInfo = appWidgetManager?.getAppWidgetInfo(appWidgetId)
        val minWidth = appWidgetInfo?.minWidth ?: 100
        val minHeight = appWidgetInfo?.minHeight ?: 100
        
        val widgetData = mapOf(
            "appWidgetId" to appWidgetId,
            "minWidth" to minWidth,
            "minHeight" to minHeight,
            "label" to (appWidgetInfo?.loadLabel(activity.packageManager)?.toString() ?: "Widget")
        )
        pendingWidgetResult?.success(widgetData)
        pendingWidgetResult = null
    }

    inner class NativeWidgetFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val params = args as? Map<*, *>
            val appWidgetId = (params?.get("appWidgetId") as? Number)?.toInt() ?: -1
            return NativeWidgetView(activity, appWidgetId, appWidgetHost, appWidgetManager)
        }
    }

    class NativeWidgetView(
        private val activity: Activity,
        private val appWidgetId: Int,
        private val appWidgetHost: AppWidgetHost?,
        private val appWidgetManager: AppWidgetManager?
    ) : PlatformView {
        private val container = FrameLayout(activity)

        init {
            container.layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            try {
                if (appWidgetId != -1 && appWidgetHost != null && appWidgetManager != null) {
                    val info = appWidgetManager.getAppWidgetInfo(appWidgetId)
                    if (info != null) {
                        val hostView = appWidgetHost.createView(activity, appWidgetId, info)
                        hostView.layoutParams = FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                        container.addView(hostView)
                    } else { showError("Widget Info Not Found") }
                } else { showError("Host Not Ready") }
            } catch (e: Exception) { showError("Initialization Error: ${e.message}") }
        }

        private fun showError(msg: String) {
            val errorView = TextView(activity).apply {
                text = "Widget Error:\n$msg"
                setTextColor(android.graphics.Color.WHITE)
                setBackgroundColor(android.graphics.Color.parseColor("#8B0000")) 
                gravity = android.view.Gravity.CENTER
            }
            container.addView(errorView)
        }

        override fun getView(): View = container
        override fun dispose() { 
            container.removeAllViews() 
        }
    }
}