# Keep all our custom Kotlin Native bridge classes intact
-keep class com.samuel.winlauncher.** { *; }

# Keep Flutter core classes intact
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Nova Launcher icon pack intent structures
-keep class com.novalauncher.** { *; }

# Ignore missing Google Play Core classes (used by Flutter's deferred components)
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Ignore Flutter's internal references to those missing classes
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication

# Keep Device Calendar plugin classes intact
-keep class com.builttoroam.devicecalendar.** { *; }
-keep class android.provider.CalendarContract.** { *; }

# Flutter InAppWebView JavaScript bridge protection
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview_android.**

# CRITICAL FIX: Keep legacy reflective pathways for SD Card resolution
-keepclassmembers class android.os.storage.StorageVolume {
    public java.lang.String getPath();
}