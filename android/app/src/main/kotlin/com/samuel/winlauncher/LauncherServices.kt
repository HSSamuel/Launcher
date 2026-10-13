package com.samuel.winlauncher

import android.app.Notification
import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import android.util.LruCache
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

class LauncherNotificationService : NotificationListenerService() {
    
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)
    
    companion object {
        private const val TAG = "Win11NotifService"
        
        private val artworkCache = LruCache<String, String>(20)
        
        @Volatile
        var instance: LauncherNotificationService? = null
            private set
            
        @Volatile
        var eventSink: EventChannel.EventSink? = null

        @Volatile
        var activeMediaController: MediaController? = null

        fun extractNotificationData(sbn: StatusBarNotification): Map<String, Any?>? {
            return try {
                val extras = sbn.notification.extras
                val title = extras.getCharSequence("android.title")?.toString() ?: ""
                var text = extras.getCharSequence("android.text")?.toString() ?: ""

                val messages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    extras.getParcelableArray("android.messages", Bundle::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    extras.getParcelableArray("android.messages")
                }

                if (!messages.isNullOrEmpty()) {
                    val lastMessage = messages.last() as? Bundle
                    val msgText = lastMessage?.getCharSequence("text")?.toString()
                    val sender = lastMessage?.getCharSequence("sender")?.toString()
                    if (msgText != null) {
                        text = if (sender != null) "$sender: $msgText" else msgText
                    }
                } else {
                    val bigText = extras.getCharSequence("android.bigText")?.toString()
                    if (!bigText.isNullOrEmpty()) {
                        text = bigText
                    } else {
                        val textLines = extras.getCharSequenceArray("android.textLines")
                        if (!textLines.isNullOrEmpty()) {
                            text = textLines.joinToString("\n") { it.toString() }
                        }
                    }
                }

                val actionList = mutableListOf<Map<String, Any>>()
                sbn.notification.actions?.forEachIndexed { index, action ->
                    actionList.add(
                        mapOf(
                            "title" to (action.title?.toString() ?: ""),
                            "index" to index,
                            "hasRemoteInput" to (!action.remoteInputs.isNullOrEmpty())
                        )
                    )
                }

                val isMedia = extras.containsKey(Notification.EXTRA_MEDIA_SESSION)
                var isPlaying = false
                var largeIconPath: String? = null
                
                if (isMedia) {
                    try {
                        val token = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            extras.getParcelable(Notification.EXTRA_MEDIA_SESSION, MediaSession.Token::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            extras.getParcelable<MediaSession.Token>(Notification.EXTRA_MEDIA_SESSION)
                        }
                        
                        val currentInstance = instance
                        if (token != null && currentInstance != null) {
                            val controller = MediaController(currentInstance, token)
                            activeMediaController = controller
                            isPlaying = controller.playbackState?.state == PlaybackState.STATE_PLAYING
                            
                            val metadata = controller.metadata
                            if (metadata != null) {
                                val artBitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART) 
                                             ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
                                
                                if (artBitmap != null) {
                                    val titleStr = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
                                    val fileHash = "${sbn.key.hashCode()}_${titleStr.hashCode()}"
                                    
                                    val cachedPath = artworkCache.get(fileHash)
                                    if (cachedPath != null && File(cachedPath).exists()) {
                                        largeIconPath = cachedPath
                                    } else {
                                        val cacheDir = File(currentInstance.cacheDir, "notif_icons")
                                        if (!cacheDir.exists()) cacheDir.mkdirs()
                                        val iconFile = File(cacheDir, "notif_${fileHash}.jpg")
                                        
                                        if (!iconFile.exists()) {
                                            val scaledArt = Bitmap.createScaledBitmap(artBitmap, 400, 400, true)
                                            try {
                                                FileOutputStream(iconFile).use { stream ->
                                                    scaledArt.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                                                }
                                            } finally {
                                                if (scaledArt != artBitmap && !scaledArt.isRecycled) scaledArt.recycle()
                                            }
                                        }
                                        largeIconPath = iconFile.absolutePath
                                        artworkCache.put(fileHash, largeIconPath)
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) { 
                        Log.e(TAG, "Failed to get playback state or metadata", e) 
                    }

                    if (largeIconPath == null) {
                        try {
                            val icon = sbn.notification.getLargeIcon()
                            val currentInstance = instance
                            if (icon != null && currentInstance != null) {
                                val hashKey = "fallback_${sbn.key.hashCode()}"
                                val cachedFallback = artworkCache.get(hashKey)
                                
                                if (cachedFallback != null && File(cachedFallback).exists()) {
                                    largeIconPath = cachedFallback
                                } else {
                                    val cacheDir = File(currentInstance.cacheDir, "notif_icons")
                                    if (!cacheDir.exists()) cacheDir.mkdirs()
                                    val iconFile = File(cacheDir, "notif_${hashKey}.jpg")
                                    
                                    if (!iconFile.exists()) {
                                        val drawable = icon.loadDrawable(currentInstance)
                                        if (drawable != null) {
                                            val rawW = drawable.intrinsicWidth
                                            val rawH = drawable.intrinsicHeight
                                            val width = if (rawW > 0) rawW.coerceAtMost(300) else 144
                                            val height = if (rawH > 0) rawH.coerceAtMost(300) else 144

                                            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                            val canvas = Canvas(bitmap)
                                            drawable.setBounds(0, 0, canvas.width, canvas.height)
                                            drawable.draw(canvas)
                                            
                                            FileOutputStream(iconFile).use { stream ->
                                                bitmap.compress(Bitmap.CompressFormat.JPEG, 70, stream)
                                            }
                                            if (!bitmap.isRecycled) bitmap.recycle()
                                        }
                                    }
                                    largeIconPath = iconFile.absolutePath
                                    artworkCache.put(hashKey, largeIconPath)
                                }
                            }
                        } catch (e: Exception) { 
                            Log.e(TAG, "Failed to parse album art fallback", e) 
                        }
                    }
                }

                if (title.isNotEmpty() || text.isNotEmpty()) {
                    mapOf(
                        "id" to sbn.id,
                        "key" to sbn.key,
                        "package" to sbn.packageName,
                        "title" to title,
                        "text" to text,
                        "postTime" to sbn.postTime,
                        "isOngoing" to sbn.isOngoing,
                        "isMedia" to isMedia,
                        "isPlaying" to isPlaying,
                        "largeIcon" to largeIconPath,
                        "actions" to actionList,
                        "removed" to false
                    )
                } else null
            } catch (e: Exception) {
                Log.e(TAG, "Error extracting notification data: ${e.message}")
                null
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        if (instance == this) {
            instance = null
            eventSink = null
            activeMediaController = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceJob.cancel()
        if (instance == this) {
            instance = null
            eventSink = null
            activeMediaController = null
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        serviceScope.launch {
            try {
                extractNotificationData(sbn)?.let { data ->
                    Handler(Looper.getMainLooper()).post {
                        try { eventSink?.success(data) } catch (e: Exception) {}
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stream notification: ${e.message}")
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras
        if (extras.containsKey(Notification.EXTRA_MEDIA_SESSION)) {
            val removedToken = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                extras.getParcelable(
                    Notification.EXTRA_MEDIA_SESSION,
                    MediaSession.Token::class.java
                )
            } else {
                @Suppress("DEPRECATION")
                extras.getParcelable<MediaSession.Token>(
                    Notification.EXTRA_MEDIA_SESSION
                )
            }

            if (activeMediaController?.sessionToken == removedToken) {
                activeMediaController = null
            }
        }
        
        serviceScope.launch {
            try {
                val context = instance
                if (context != null) {
                    val cacheDir = File(context.cacheDir, "notif_icons")
                    val keyHash = sbn.key.hashCode().toString()
                    val prefix = "notif_${keyHash}_"
                    val fallback = "notif_fallback_${keyHash}.jpg"
                    
                    cacheDir.listFiles()?.forEach { file: File ->
                        if (file.name.startsWith(prefix) || file.name == fallback) {
                            file.delete()
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete cached notification icon: ${e.message}")
            }
            
            Handler(Looper.getMainLooper()).post {
                try { eventSink?.success(mapOf("key" to sbn.key, "removed" to true)) } catch (e: Exception) {}
            }
        }
    }
}

class LauncherAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i("Win11AdminReceiver", "Device Admin enabled successfully.")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.i("Win11AdminReceiver", "Device Admin disabled.")
    }
}