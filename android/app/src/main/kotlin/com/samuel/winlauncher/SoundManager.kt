package com.samuel.winlauncher

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.SoundPool
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

class SoundManager(private val context: Context) {
    private val TAG = "Win11SoundManager"
    private var soundPool: SoundPool
    
    private val soundIds = mutableMapOf<String, Int>()
    
    // CRITICAL FIX: Use concurrent collections to prevent thread collisions between 
    // the SoundPool decoder thread and the Flutter Main UI thread.
    private val loadedSounds: MutableSet<Int> = ConcurrentHashMap.newKeySet()
    private val pendingPlays: MutableSet<Int> = ConcurrentHashMap.newKeySet()

    init {
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
            
        soundPool = SoundPool.Builder()
            .setMaxStreams(3)
            .setAudioAttributes(audioAttributes)
            .build()

        // Listen for when sounds actually finish decoding into memory
        soundPool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0) {
                loadedSounds.add(sampleId)
                // If Flutter asked to play this sound before it was ready, play it immediately now!
                if (pendingPlays.contains(sampleId)) {
                    soundPool.play(sampleId, 1f, 1f, 1, 0, 1f)
                    pendingPlays.remove(sampleId)
                }
            } else {
                Log.e(TAG, "Failed to load sound ID: $sampleId")
            }
        }

        try {
            val loader = FlutterInjector.instance().flutterLoader()
            soundIds["startup"] = loadSound(loader.getLookupKeyForAsset("assets/sounds/startup.mp3"))
            soundIds["recycle"] = loadSound(loader.getLookupKeyForAsset("assets/sounds/recycle.mp3"))
            soundIds["error"]   = loadSound(loader.getLookupKeyForAsset("assets/sounds/error.mp3"))
            soundIds["mouse"]  = loadSound(loader.getLookupKeyForAsset("assets/sounds/mouse.mp3"))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load sound assets. Ensure assets/sounds/ directory exists.", e)
        }
    }

    private fun loadSound(key: String): Int {
        return try {
            val fd: AssetFileDescriptor = context.assets.openFd(key)
            soundPool.load(fd, 1)
        } catch (e: Exception) {
            -1
        }
    }

    fun playSound(call: MethodCall, result: MethodChannel.Result) {
        val type = call.argument<String>("type") ?: return result.success(false)
        val soundId = soundIds[type]
        
        if (soundId != null && soundId != -1) {
            if (loadedSounds.contains(soundId)) {
                // Sound is fully decoded, play it instantly
                soundPool.play(soundId, 1f, 1f, 1, 0, 1f)
            } else {
                // Flutter is asking too fast! Queue it to play the exact millisecond it finishes loading
                pendingPlays.add(soundId)
            }
            result.success(true)
        } else {
            result.success(false)
        }
    }

    fun onDestroy() {
        soundPool.release()
    }
}