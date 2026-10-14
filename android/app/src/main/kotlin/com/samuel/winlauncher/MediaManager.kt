package com.samuel.winlauncher

import android.app.Activity
import android.app.SearchManager
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import java.io.InputStream
import java.util.Locale

class MediaManager(private val activity: Activity) {
    private val TAG = "Win11MediaManager"
    private val job = SupervisorJob()
    private val scope = CoroutineScope(Dispatchers.IO + job)
    private var searchJob: Job? = null
    
    private var pendingDeleteResult: MethodChannel.Result? = null
    private val REQUEST_DELETE_CODE = 4040

    fun onDestroy() {
        job.cancel()
    }

    fun getFilesInDirectory(call: MethodCall, result: MethodChannel.Result) {
        val targetPath = call.argument<String>("path")?.removeSuffix("/") ?: run {
            result.safeError(activity, "INVALID_PATH", "Directory path is required", null)
            return
        }
        
        scope.launch {
            val files = mutableListOf<Map<String, Any>>()
            val folders = mutableSetOf<String>()
            
            var standardIoSuccess = false
            try {
                val dir = File(targetPath)
                if (dir.exists() && dir.canRead()) {
                    val listFiles = dir.listFiles()
                    if (listFiles != null) {
                        standardIoSuccess = true
                        for (file in listFiles) {
                            if (file.name == ".nomedia" || file.name == ".recycle_index.json") continue
                            files.add(mapOf(
                                "name" to file.name,
                                "path" to file.absolutePath,
                                "isDir" to file.isDirectory,
                                "size" to file.length(),
                                "modified" to file.lastModified()
                            ))
                            if (file.isDirectory) folders.add(file.absolutePath)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Standard IO read failed for $targetPath, falling back to MediaStore")
            }

            if (!standardIoSuccess && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val projection = arrayOf(
                    MediaStore.Files.FileColumns.DISPLAY_NAME,
                    MediaStore.Files.FileColumns.DATA,
                    MediaStore.Files.FileColumns.SIZE,
                    MediaStore.Files.FileColumns.DATE_MODIFIED
                )
                
                val selection = "${MediaStore.Files.FileColumns.DATA} LIKE ?"
                val selectionArgs = arrayOf("$targetPath/%")
                
                try {
                    activity.contentResolver.query(
                        MediaStore.Files.getContentUri("external"),
                        projection, selection, selectionArgs, null
                    )?.use { cursor ->
                        val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                        val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATA)
                        val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                        val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                        
                        while (cursor.moveToNext()) {
                            val filePath = cursor.getString(dataCol) ?: continue
                            // CRITICAL FIX: Ensure the MediaStore ghost file actually exists on physical disk
                            if (!File(filePath).exists()) continue

                            val fileName = cursor.getString(nameCol) ?: File(filePath).name
                            
                            if (fileName == ".nomedia" || fileName == ".recycle_index.json") continue
                            
                            val relativePath = filePath.removePrefix("$targetPath/")
                            
                            if (relativePath.contains("/")) {
                                val folderName = relativePath.substringBefore("/")
                                val folderPath = "$targetPath/$folderName"
                                if (folders.add(folderPath)) {
                                    files.add(mapOf(
                                        "name" to folderName,
                                        "path" to folderPath,
                                        "isDir" to true,
                                        "size" to 0L,
                                        "modified" to System.currentTimeMillis()
                                    ))
                                }
                            } else {
                                files.add(mapOf(
                                    "name" to fileName,
                                    "path" to filePath,
                                    "isDir" to false,
                                    "size" to cursor.getLong(sizeCol),
                                    "modified" to cursor.getLong(dateCol) * 1000
                                ))
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "MediaStore directory query failed", e)
                }
            }
            
            result.safeSuccess(activity, files)
        }
    }

    fun searchMedia(call: MethodCall, result: MethodChannel.Result) {
        val query = call.argument<String>("query") ?: ""
        val limit = call.argument<Int>("limit") ?: 20
        
        val results = mutableMapOf<String, MutableList<Map<String, String>>>(
            "Audio" to mutableListOf(), "Images" to mutableListOf(), "Video" to mutableListOf(), "Documents" to mutableListOf()
        )
        if (query.length < 2) { 
            result.safeSuccess(activity, results)
            return 
        }

        searchJob?.cancel()
        searchJob = scope.launch {
            val searchLike = "%$query%"
            val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.DATA)
            val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
            val selectionArgs = arrayOf(searchLike)
            val sortOrder = "${MediaStore.MediaColumns.DATE_ADDED} DESC"

            try {
                activity.contentResolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                    val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    val dataCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                    var count = 0
                    while (cursor.moveToNext() && count < limit) { 
                        val path = cursor.getString(dataCol)
                        // CRITICAL FIX: Eliminate ghost files from global search results
                        if (path != null && File(path).exists()) {
                            results["Audio"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to path))
                            count++ 
                        }
                    }
                }

                activity.contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                    val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    val dataCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                    var count = 0
                    while (cursor.moveToNext() && count < limit) { 
                        val path = cursor.getString(dataCol)
                        if (path != null && File(path).exists()) {
                            results["Images"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to path))
                            count++ 
                        }
                    }
                }

                activity.contentResolver.query(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                    val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    val dataCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                    var count = 0
                    while (cursor.moveToNext() && count < limit) { 
                        val path = cursor.getString(dataCol)
                        if (path != null && File(path).exists()) {
                            results["Video"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to path))
                            count++ 
                        }
                    }
                }

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
                    val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    val dataCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                    var count = 0
                    while (cursor.moveToNext() && count < limit) { 
                        val path = cursor.getString(dataCol)
                        if (path != null && File(path).exists()) {
                            results["Documents"]?.add(mapOf("name" to cursor.getString(nameCol), "path" to path))
                            count++ 
                        }
                    }
                }

                result.safeSuccess(activity, results)
            } catch (e: Exception) { 
                Log.e(TAG, "Error searching media", e)
                result.safeError(activity, "MEDIA_SEARCH_ERROR", e.message, null)
            }
        }
    }

    fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: ""
        try {
            var uri: Uri
            var mimeType: String? = "*/*"

            if (path.startsWith("content://")) {
                uri = Uri.parse(path)
                mimeType = activity.contentResolver.getType(uri) ?: "*/*"
            } else {
                val file = File(path)
                if (file.exists()) {
                    try {
                        uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
                    } catch (e: IllegalArgumentException) {
                        Log.e(TAG, "File path not supported by FileProvider: ${file.absolutePath}", e)
                        result.safeError(activity, "OPEN_FILE_FAILED", "Path not within allowed directories", null)
                        return
                    }
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
                    result.safeSuccess(activity, false)
                    return
                }
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            if (intent.resolveActivity(activity.packageManager) != null) {
                activity.startActivity(intent)
            } else {
                activity.startActivity(Intent.createChooser(intent, "Open with...").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            result.safeSuccess(activity, true)
        } catch (e: Exception) { 
            Log.e(TAG, "Error opening file: $path", e)
            result.safeError(activity, "OPEN_FILE_FAILED", e.message, null)
        }
    }

    fun shareFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: ""
        try {
            val uri: Uri = if (path.startsWith("content://")) {
                Uri.parse(path)
            } else {
                val file = File(path)
                if (!file.exists()) { 
                    result.safeSuccess(activity, false)
                    return 
                }
                try {
                    FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
                } catch (e: IllegalArgumentException) {
                    Log.e(TAG, "File path not supported by FileProvider: ${file.absolutePath}", e)
                    result.safeError(activity, "SHARE_FILE_FAILED", "Path not within allowed directories", null)
                    return
                }
            }
            
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "*/*"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(Intent.createChooser(intent, "Share File").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.safeSuccess(activity, true)
        } catch (e: Exception) { 
            Log.e(TAG, "Error sharing file: $path", e)
            result.safeError(activity, "SHARE_FILE_FAILED", e.message, null)
        }
    }

    fun shareText(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(Intent.createChooser(intent, "Share").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.safeSuccess(activity, true)
        } catch (e: Exception) { 
            Log.e(TAG, "Error sharing text", e)
            result.safeError(activity, "SHARE_TEXT_FAILED", e.message, null)
        }
    }

    fun openWebSearch(call: MethodCall, result: MethodChannel.Result) {
        val query = call.argument<String>("query") ?: ""
        try {
            val intent = Intent(Intent.ACTION_WEB_SEARCH).apply {
                putExtra(SearchManager.QUERY, query)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            result.safeSuccess(activity, true)
        } catch (e: Exception) { 
            Log.e(TAG, "Error opening web search", e)
            result.safeError(activity, "WEB_SEARCH_FAILED", e.message, null)
        }
    }

    fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: ""
        val fileName = call.argument<String>("fileName") ?: "downloaded_file"
        scope.launch {
            var insertedUri: Uri? = null
            try {
                var success = false
                val sourceFile = File(path)
                val inputStream: InputStream? = if (sourceFile.exists()) {
                    sourceFile.inputStream()
                } else if (path.startsWith("content://")) {
                    activity.contentResolver.openInputStream(Uri.parse(path))
                } else null

                if (inputStream == null) {
                    result.safeSuccess(activity, false)
                    return@launch
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val resolver = activity.contentResolver
                    val contentValues = android.content.ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                        put(MediaStore.Downloads.RELATIVE_PATH, android.os.Environment.DIRECTORY_DOWNLOADS)
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                    insertedUri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                    if (insertedUri != null) {
                        resolver.openOutputStream(insertedUri)?.use { out ->
                            inputStream.use { it.copyTo(out) }
                        }
                        contentValues.clear()
                        contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
                        resolver.update(insertedUri, contentValues, null, null)
                        success = true
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val downloadsDir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)
                    val destFile = File(downloadsDir, fileName)
                    destFile.outputStream().use { out ->
                        inputStream.use { it.copyTo(out) }
                    }
                    success = true
                }
                result.safeSuccess(activity, success)
            } catch (e: Exception) {
                Log.e(TAG, "Error saving to downloads via MediaStore", e)
                if (insertedUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try { activity.contentResolver.delete(insertedUri, null, null) } catch (_: Exception) {}
                }
                result.safeSuccess(activity, false)
            }
        }
    }

    private fun getUriAndTypeFromPath(path: String): Pair<Uri?, Boolean> {
        val extension = File(path).extension.lowercase(Locale.ROOT)
        val isMedia = extension in listOf("jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "mp4", "mkv", "avi", "mov", "webm", "3gp", "mp3", "wav", "ogg", "flac", "m4a", "aac")
        
        val contentUri = when (extension) {
            "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "mp4", "mkv", "avi", "mov", "webm", "3gp" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            "mp3", "wav", "ogg", "flac", "m4a", "aac" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Files.getContentUri("external")
        }

        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.DATA} = ?"
        
        try {
            val cursor = activity.contentResolver.query(contentUri, projection, selection, arrayOf(path), null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val id = it.getLong(it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                    return Pair(ContentUris.withAppendedId(contentUri, id), isMedia)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to query MediaStore for path: $path", e)
        }
        return Pair(null, isMedia)
    }

    fun deleteFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: run {
            result.safeSuccess(activity, false)
            return
        }
        val file = File(path)

        if (path.contains(activity.packageName)) {
            result.safeSuccess(activity, file.deleteRecursively())
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) {
            val deleted = file.deleteRecursively()
            result.safeSuccess(activity, deleted)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.safeSuccess(activity, file.deleteRecursively())
            return
        }

        try {
            val (uri, isMedia) = getUriAndTypeFromPath(path)
            
            if (uri != null && isMedia) {
                val pi = MediaStore.createDeleteRequest(activity.contentResolver, listOf(uri))
                pendingDeleteResult = result
                activity.startIntentSenderForResult(pi.intentSender, REQUEST_DELETE_CODE, null, 0, 0, 0)
            } else {
                val deleted = file.deleteRecursively()
                result.safeSuccess(activity, deleted)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete file via MediaStore", e)
            result.safeSuccess(activity, false) 
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode == REQUEST_DELETE_CODE) {
            pendingDeleteResult?.safeSuccess(activity, resultCode == Activity.RESULT_OK)
            pendingDeleteResult = null
            return true
        }
        return false
    }
}