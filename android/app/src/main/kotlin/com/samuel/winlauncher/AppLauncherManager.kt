package com.samuel.winlauncher

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.io.FileOutputStream

class AppLauncherManager(private val activity: Activity) {
    private val TAG = "Win11AppManager"
    private val managerJob = SupervisorJob()
    private val managerScope = CoroutineScope(Dispatchers.IO + managerJob)
    private var iconPackJob: kotlinx.coroutines.Job? = null

    private val launcherLargeIconSize: Int by lazy {
        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
        am?.launcherLargeIconSize ?: 144
    }

    fun onDestroy() {
        managerJob.cancel()
    }

    fun launchApp(call: MethodCall, result: MethodChannel.Result) {
        val pkg = call.argument<String>("package") ?: ""
        try {
            if (pkg.contains("://") || pkg.startsWith("mailto:") || pkg.startsWith("tel:")) {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(pkg)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(intent)
                result.safeSuccess(activity, true)
                return
            }

            val intent = activity.packageManager.getLaunchIntentForPackage(pkg)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
                result.safeSuccess(activity, true)
            } else {
                result.safeSuccess(activity, false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error launching app: $pkg", e)
            result.safeError(activity, "APP_LAUNCH_FAILED", e.message, null)
        }
    }

    fun uninstallApp(call: MethodCall, result: MethodChannel.Result) {
        val pkg = call.argument<String>("package") ?: ""
        try {
            val intent = Intent(Intent.ACTION_DELETE).apply {
                data = Uri.parse("package:$pkg")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            result.safeSuccess(activity, true)
        } catch (e: Exception) {
            Log.e(TAG, "Error uninstalling app: $pkg", e)
            result.safeError(activity, "UNINSTALL_FAILED", e.message, null)
        }
    }

    fun getAvailableIconPacks(result: MethodChannel.Result) {
        try {
            val pm = activity.packageManager
            val intent = Intent("com.novalauncher.THEME")
            val packs = pm.queryIntentActivities(intent, 0)

            val results = packs.map {
                mapOf(
                    "name" to it.loadLabel(pm).toString(),
                    "package" to it.activityInfo.packageName
                )
            }
            result.safeSuccess(activity, results)
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching icon packs", e)
            result.safeError(activity, "ICON_PACK_FETCH_FAILED", e.message, null)
        }
    }

    fun applyIconPack(call: MethodCall, result: MethodChannel.Result) {
        val packPkg = call.argument<String>("package")

        iconPackJob?.cancel()
        iconPackJob = managerScope.launch {
            try {
                val pm = activity.packageManager
                val targetSize = launcherLargeIconSize

                val timestamp = System.currentTimeMillis()
                val cacheDir = File(activity.cacheDir, "icons_$timestamp")
                cacheDir.mkdirs()

                val iconPackMap = mutableMapOf<String, String>()
                val iconBacks = mutableListOf<String>()
                val iconMasks = mutableListOf<String>()
                val iconUpons = mutableListOf<String>()
                var scaleFactor = 1.0f
                var packRes: android.content.res.Resources? = null

                if (!packPkg.isNullOrEmpty()) {
                    try {
                        packRes = pm.getResourcesForApplication(packPkg)
                        var parser: XmlPullParser? = null
                        var inputStream: java.io.InputStream? = null

                        try {
                            inputStream = packRes.assets.open("appfilter.xml")
                            parser = android.util.Xml.newPullParser().apply { setInput(inputStream, null) }
                        } catch (e: Exception) {
                            val resId = packRes.getIdentifier("appfilter", "xml", packPkg)
                            if (resId != 0) {
                                parser = packRes.getXml(resId)
                            }
                        }

                        try {
                            if (parser != null) {
                                var eventType = parser.eventType
                                while (eventType != XmlPullParser.END_DOCUMENT) {
                                    if (eventType == XmlPullParser.START_TAG) {
                                        when (parser.name) {
                                            "item" -> {
                                                val comp = parser.getAttributeValue(null, "component")
                                                val drawable = parser.getAttributeValue(null, "drawable")
                                                if (comp != null && drawable != null) {
                                                    iconPackMap[comp] = drawable
                                                    val openBrace = comp.indexOf("{")
                                                    val slashIdx = comp.indexOf("/")
                                                    val closeBrace = comp.indexOf("}")
                                                    if (openBrace != -1 && slashIdx > openBrace && closeBrace > slashIdx) {
                                                        val pkgPart = comp.substring(openBrace + 1, slashIdx)
                                                        val clsPart = comp.substring(slashIdx + 1, closeBrace)
                                                        val normalizedCls = if (clsPart.startsWith(".")) "$pkgPart$clsPart" else clsPart
                                                        iconPackMap["ComponentInfo{$pkgPart/$normalizedCls}"] = drawable
                                                        if (!iconPackMap.containsKey(pkgPart)) {
                                                            iconPackMap[pkgPart] = drawable
                                                        }
                                                    }
                                                }
                                            }
                                            "iconback" -> {
                                                for (i in 0 until parser.attributeCount) {
                                                    val attrName = parser.getAttributeName(i)
                                                    if (attrName.startsWith("img")) {
                                                        parser.getAttributeValue(i)?.let { iconBacks.add(it) }
                                                    }
                                                }
                                            }
                                            "iconmask" -> {
                                                for (i in 0 until parser.attributeCount) {
                                                    val attrName = parser.getAttributeName(i)
                                                    if (attrName.startsWith("img")) {
                                                        parser.getAttributeValue(i)?.let { iconMasks.add(it) }
                                                    }
                                                }
                                            }
                                            "iconupon" -> {
                                                for (i in 0 until parser.attributeCount) {
                                                    val attrName = parser.getAttributeName(i)
                                                    if (attrName.startsWith("img")) {
                                                        parser.getAttributeValue(i)?.let { iconUpons.add(it) }
                                                    }
                                                }
                                            }
                                            "scale" -> {
                                                val factorStr = parser.getAttributeValue(null, "factor")
                                                factorStr?.toFloatOrNull()?.let { scaleFactor = it }
                                            }
                                        }
                                    }
                                    eventType = parser.next()
                                }
                            }
                        } finally {
                            inputStream?.close()
                            if (parser is android.content.res.XmlResourceParser) {
                                parser.close()
                            }
                        }

                        if (scaleFactor == 1.0f && iconBacks.isNotEmpty()) {
                            scaleFactor = 0.8f
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to parse appfilter.xml.", e)
                    }
                }

                val backBitmaps = mutableListOf<Bitmap>()
                var maskBitmap: Bitmap? = null
                var uponBitmap: Bitmap? = null

                try {
                    if (packRes != null && !packPkg.isNullOrEmpty()) {
                        try {
                            for (backName in iconBacks) {
                                val resId = packRes.getIdentifier(backName, "drawable", packPkg)
                                if (resId != 0) backBitmaps.add(getBitmapFromDrawable(packRes.getDrawable(resId, null), targetSize))
                            }
                            if (iconMasks.isNotEmpty()) {
                                val resId = packRes.getIdentifier(iconMasks.first(), "drawable", packPkg)
                                if (resId != 0) maskBitmap = getBitmapFromDrawable(packRes.getDrawable(resId, null), targetSize)
                            }
                            if (iconUpons.isNotEmpty()) {
                                val resId = packRes.getIdentifier(iconUpons.first(), "drawable", packPkg)
                                if (resId != 0) uponBitmap = getBitmapFromDrawable(packRes.getDrawable(resId, null), targetSize)
                            }
                        } catch (e: Exception) { Log.w(TAG, "Failed to load masking assets", e) }
                    }

                    val mainIntent = Intent(Intent.ACTION_MAIN, null).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
                    val apps = pm.queryIntentActivities(mainIntent, 0)
                    
                    val dstInPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
                    }

                    for (resolveInfo in apps) {
                        val pkg = resolveInfo.activityInfo.packageName
                        val cls = resolveInfo.activityInfo.name
                        val compString = "ComponentInfo{$pkg/$cls}"
                        val file = File(cacheDir, "$pkg.png")

                        var finalBitmap: Bitmap? = null
                        var wasThemed = false

                        if (packRes != null) {
                            val drawableName = iconPackMap[compString] ?: iconPackMap[pkg]
                            if (drawableName != null) {
                                val resId = packRes.getIdentifier(drawableName, "drawable", packPkg)
                                if (resId != 0) {
                                    try {
                                        val drawable = packRes.getDrawable(resId, null)
                                        finalBitmap = getBitmapFromDrawable(drawable, targetSize)
                                        wasThemed = true
                                    } catch (e: Exception) { Log.e(TAG, "Failed to load resource $resId", e) }
                                }
                            }
                        }

                        if (!wasThemed) {
                            try {
                                val defaultDrawable = resolveInfo.loadIcon(pm)
                                if (backBitmaps.isNotEmpty() || maskBitmap != null || uponBitmap != null) {
                                    val backBitmap = if (backBitmaps.isNotEmpty()) {
                                        val index = (pkg.hashCode() and 0x7FFFFFFF) % backBitmaps.size
                                        backBitmaps[index]
                                    } else null
                                    finalBitmap = generateMaskedIcon(defaultDrawable, backBitmap, maskBitmap, uponBitmap, scaleFactor, targetSize, dstInPaint)
                                } else {
                                    finalBitmap = getBitmapFromDrawable(defaultDrawable, targetSize)
                                }
                            } catch (e: Exception) { Log.e(TAG, "Failed to load default icon", e) }
                        }

                        finalBitmap?.let {
                            val scaled = Bitmap.createScaledBitmap(it, targetSize, targetSize, true)
                            val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP
                            FileOutputStream(file).use { out ->
                                scaled.compress(format, 95, out)
                            }
                            if (scaled != it && !scaled.isRecycled) {
                                scaled.recycle()
                            }
                            if (!it.isRecycled) {
                                it.recycle()
                            }
                        }
                    }
                } finally {
                    backBitmaps.forEach { if (!it.isRecycled) it.recycle() }
                    if (maskBitmap?.isRecycled == false) maskBitmap?.recycle()
                    if (uponBitmap?.isRecycled == false) uponBitmap?.recycle()
                }

                activity.cacheDir.listFiles()?.forEach {
                    if (it.name.startsWith("icons_") && it.name != cacheDir.name) {
                        it.deleteRecursively()
                    }
                }

                result.safeSuccess(activity, cacheDir.absolutePath)
                
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Failed to apply icon pack", e)
                result.safeSuccess(activity, null)
            }
        }
    }

    private fun generateMaskedIcon(
        defaultDrawable: Drawable,
        iconBack: Bitmap?,
        iconMask: Bitmap?,
        iconUpon: Bitmap?,
        scaleFactor: Float,
        outputSize: Int,
        paintFilter: Paint
    ): Bitmap {
        val composite = Bitmap.createBitmap(outputSize, outputSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(composite)

        if (iconBack != null) {
            val scaledBack = Bitmap.createScaledBitmap(iconBack, outputSize, outputSize, true)
            canvas.drawBitmap(scaledBack, 0f, 0f, null)
            if (scaledBack != iconBack && !scaledBack.isRecycled) scaledBack.recycle()
        }

        var iconSize = (outputSize * scaleFactor).toInt()
        if (iconSize <= 0) iconSize = outputSize

        val left = (outputSize - iconSize) / 2f
        val top = (outputSize - iconSize) / 2f

        val bounds = RectF(0f, 0f, outputSize.toFloat(), outputSize.toFloat())
        val saveCount = canvas.saveLayer(bounds, null)

        val scaledDefault = getBitmapFromDrawable(defaultDrawable, iconSize)
        canvas.drawBitmap(scaledDefault, left, top, null)
        if (!scaledDefault.isRecycled) scaledDefault.recycle()

        if (iconMask != null) {
            val scaledMask = Bitmap.createScaledBitmap(iconMask, outputSize, outputSize, true)
            canvas.drawBitmap(scaledMask, 0f, 0f, paintFilter)
            if (scaledMask != iconMask && !scaledMask.isRecycled) scaledMask.recycle()
        }

        canvas.restoreToCount(saveCount)

        if (iconUpon != null) {
            val scaledUpon = Bitmap.createScaledBitmap(iconUpon, outputSize, outputSize, true)
            canvas.drawBitmap(scaledUpon, 0f, 0f, null)
            if (scaledUpon != iconUpon && !scaledUpon.isRecycled) scaledUpon.recycle()
        }

        return composite
    }

    private fun getBitmapFromDrawable(drawable: Drawable, targetSize: Int = 144): Bitmap {
        return try {
            if (drawable is android.graphics.drawable.BitmapDrawable && drawable.bitmap != null) {
                return Bitmap.createScaledBitmap(drawable.bitmap, targetSize, targetSize, true)
            }
            val bitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, targetSize, targetSize)
            drawable.draw(canvas)
            bitmap
        } catch (e: Exception) {
            Log.e(TAG, "Failed to render drawable to bitmap", e)
            Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        }
    }
}