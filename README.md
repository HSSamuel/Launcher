# Win11 Launcher 🪟📱

A fully functional, highly authentic Windows 11-style Android launcher built with Flutter. This project seamlessly bridges a beautiful, responsive Flutter frontend with deep native Android Kotlin intents, bringing a true desktop experience to mobile devices.

## ✨ Key Features

*   **Authentic Fluent Design:** Custom vector-built Windows 11 folder icons, gradients, and layout structures that exactly mimic the Windows 11 aesthetic without relying on external web assets.
*   **Fully Functional File Explorer:** A complete replication of the "This PC" interface. It dynamically maps real Android system folders (DCIM, Downloads, Music) to their corresponding Windows 11 colored vector icons and supports full internal storage navigation.
*   **Deep Native System Routing:** Features a custom Kotlin `MainActivity` bridge that routes seamlessly to hidden or deep Android system settings (e.g., Printers, Locale, Keyboard, Add Account).
*   **Advanced Device Control:** Utilizes Android `DeviceAdminReceiver` to allow physical screen locking via a "Double tap to sleep" gesture on the desktop.
*   **Comprehensive Settings Suite:** 11 modular, fully functional settings categories mirroring Windows 11:
    *   System, Bluetooth & Devices, Network & Internet
    *   Personalization, Gestures, Apps, Accounts
    *   Time & Language, Accessibility
    *   Privacy & Security (with real-time native permission syncing)
    *   Launcher Updates
*   **Window Management:** Supports opening, minimizing, maximizing, and stacking applications just like a real desktop environment.

## 🛠️ Tech Stack

*   **Frontend:** Flutter & Dart
*   **Native Bridge:** Kotlin
*   **Target SDK:** Android 11 - Android 14+ (Modern Scoped Storage compliant)
*   **State Management:** Provider (via `LauncherState`)

## 🔐 Advanced Permissions Handled

To provide a true system-level experience, this launcher requests and manages advanced Android privileges:
*   `MANAGE_EXTERNAL_STORAGE`: For unrestricted File Explorer navigation.
*   `BIND_DEVICE_ADMIN`: For forcing physical screen locks.
*   `BIND_ACCESSIBILITY_SERVICE`: For advanced system toggles and desktop overlays.
*   `BIND_NOTIFICATION_LISTENER_SERVICE`: To intercept and display system notifications in the Windows 11 side panel.
*   `WRITE_SETTINGS`: For toggling device configurations directly from the launcher.

## 🚀 Getting Started

### Prerequisites
*   Flutter SDK installed (`>=3.0.0`)
*   An Android physical device or emulator (Android 11+ recommended for testing storage permissions)

### Installation & Build

1. Clone the repository:
   ```bash
   git clone [https://github.com/yourusername/win11-launcher.git](https://github.com/yourusername/win11-launcher.git)