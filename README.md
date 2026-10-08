# Windows 11 PC Launcher 🪟📱

A fully functional, highly authentic Windows 11 Launcher for Android devices, built with Flutter and Kotlin. This project seamlessly bridges a beautiful, responsive Flutter frontend with deep native Android hardware intents, background isolates, and a custom multi-window manager, bringing a true desktop multitasking experience to mobile platforms.

## ✨ Key Features

*   **Responsive Multi-Window Architecture:** Fully functional window manager supporting multiple overlapping applications. Open, minimize, maximize, resize, and stack apps just like a real desktop environment. Features an intelligent `PopScope` registry to handle complex internal app navigation natively.
*   **Authentic Fluent Design:** Custom vector-built Windows 11 folder icons, system tray, Start Menu, Action Center, and context menus that strictly adhere to the Windows 11 design language.
*   **Native Android Widget Engine:** Drop real Android app widgets (Google Search, Weather, Spotify, etc.) directly onto your desktop workspace. Features fluid, grid-based resizing with live visual bounding boxes and native `AppWidgetHost` binding.
*   **Advanced File Explorer (This PC):** 
    *   **Smart Aggregation:** Automatically deduplicates and groups scattered media into unified library views.
    *   **High-Performance I/O:** Utilizes Dart background `Isolates` for heavy disk operations, including recursive directory copying and asynchronous `.zip` / `.7z` file compression to prevent UI thread blocking.
*   **Dynamic Desktop Environment:** 
    *   **Wallpaper Engine:** Live wallpaper slideshows featuring 3D Matrix page transitions (Cube, Page Flip, Carousel).
    *   **Zero-Overhead Acrylics:** Dynamically scales or disables background blurs based on device hardware capabilities to preserve GPU memory.
*   **Built-in Mini Apps:**
    *   **Edge Browser:** Desktop-class web browsing with authenticated background downloads via synchronized cookie extraction.
    *   **Calculator:** Features Standard, Scientific, Date Difference, and Live Currency Exchange (with cached background sync).
*   **Secure Lock Screen:** Custom Windows 11 lock screen fortified with cryptographic security. PINs are salted and hashed using SHA-256 via `FlutterSecureStorage`.
*   **Grouped Notification Grid:** Intercepts native Android system alerts and deduplicates them into a clean, grouped app-icon grid on the lock screen. Protects privacy by masking message contents until unlocked.
*   **Deep Hardware Integration:** Custom Kotlin MethodChannels enable direct control over system brightness, volume, Wi-Fi, Bluetooth, flashlight, screen rotation, and USB OTG Autoplay.
*   **Automated Backup & Restore:** Securely bundles launcher configurations, layouts, and custom wallpaper assets into an encrypted ZIP payload for cross-device restoration.

## 🛠️ Tech Stack & Architecture

*   **Frontend:** Flutter & Dart (`>=3.0.0`)
*   **State Management:** Provider (`DesktopState`, `AppsState`, `SystemState`, `ThemeState`)
*   **Native Bridge:** Kotlin (MethodChannels & EventChannels)
*   **Target SDK:** Android 8.0 (API 26) through Android 15 (API 35+)

### Performance Highlights
*   **Isolate Offloading:** Heavy synchronous tasks (ZIP archiving, deep folder traversal, SHA-256 PIN hashing) are offloaded to background threads.
*   **Targeted Repainting:** Hardware telemetry (battery, volume, brightness) utilizes localized `ValueNotifier` bindings to prevent massive widget tree rebuilds.
*   **Memory-Safe Caching:** Aggressive downsampling of APK byte arrays and wallpaper assets prevents Out-Of-Memory (OOM) crashes on large App Drawer grids.
*   **Edge-to-Edge Rendering:** Fully compliant with modern Android window insets, safely rendering beneath camera cutouts and OS navigation bars.

## 🔐 Permissions & System Hooks

To provide a system-level desktop experience, this launcher requests and gracefully manages advanced Android privileges:
*   `MANAGE_EXTERNAL_STORAGE` / `READ_EXTERNAL_STORAGE`: For unrestricted File Explorer navigation, media indexing, and zip archiving.
*   `BIND_DEVICE_ADMIN`: For forcing physical screen locks via desktop double-tap gestures.
*   `BIND_ACCESSIBILITY_SERVICE`: To securely trigger global OS actions (Recent Apps view, Power Dialog) without requiring Root.
*   `BIND_NOTIFICATION_LISTENER_SERVICE`: To intercept, deduplicate, and display system notifications in the Action Center.
*   `WRITE_SETTINGS`: For toggling device configurations directly from the quick settings panel.

## 🚀 Getting Started

### Prerequisites
*   Flutter SDK installed
*   Android physical device or emulator (Android 8.0+ required)

### Installation & Build

1. Clone the repository:
   ```bash
   git clone [https://github.com/yourusername/win11-launcher.git](https://github.com/yourusername/win11-launcher.git)
   ```
2. Navigate to the project directory:
   ```bash
   cd win11-launcher
   ```
3. Install dependencies (ensure `archive` is included for ZIP support):
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## 📦 Production & Play Store Deployment

To build a highly optimized, obfuscated release bundle for the Google Play Store:

```bash
flutter build aab --obfuscate --split-debug-info=./debug-info
```

### Play Console Compliance Guidelines
When submitting this launcher to the Google Play Store, prepare for strict policy reviews due to the deep system access required. Ensure you have the following ready:

1. **Permissions Declaration Form:** You must provide clear justification for `MANAGE_EXTERNAL_STORAGE` (Core File Manager functionality) and `ACCESS_FINE_LOCATION` (Live Weather Widget). 
2. **Video Demonstration:** Record a short, clear video showcasing *why* the File Explorer and Weather Widget are central to the launcher's utility. 
3. **Privacy Policy:** Ensure your external Privacy Policy explicitly details how local storage and notification data are processed natively without leaving the user's device.