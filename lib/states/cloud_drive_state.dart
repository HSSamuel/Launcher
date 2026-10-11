import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../models/cloud_file_model.dart';

class CloudDriveState extends ChangeNotifier {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveScope],
  );

  bool isGoogleDriveConnected = false;
  bool isLoading = false;
  List<CloudFile> currentCloudFiles = [];
  String activeProvider = '';
  String? driveErrorMessage;

  // Google Drive uses a stack array to track breadcrumbs by unique folder IDs
  List<Map<String, String>> gDrivePathStack = [];

  String get currentFolderId => gDrivePathStack.isNotEmpty ? gDrivePathStack.last['id']! : 'root';

  CloudDriveState() {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      isGoogleDriveConnected = account != null;
      notifyListeners();
    });
    _googleSignIn.signInSilently().then((account) {
      if (account != null) {
        isGoogleDriveConnected = true;
        notifyListeners();
      }
    }).catchError((_) {});
  }

  /// Connects to Google Drive. Returns null on success, or a descriptive error message on failure.
  Future<String?> connectGoogleDrive() async {
    try {
      isLoading = true;
      driveErrorMessage = null;
      notifyListeners();

      final account = await _googleSignIn.signIn();
      if (account == null) {
        isLoading = false;
        notifyListeners();
        return "Sign-in was cancelled.";
      }

      // Verify and request scopes explicitly if required by the device
      try {
        final hasScope = await _googleSignIn.canAccessScopes([drive.DriveApi.driveScope]);
        if (!hasScope) {
          final granted = await _googleSignIn.requestScopes([drive.DriveApi.driveScope]);
          if (!granted) {
            isLoading = false;
            notifyListeners();
            return "Google Drive permission was not granted.";
          }
        }
      } catch (scopeError) {
        debugPrint("Scope check note: $scopeError");
      }

      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) {
        isLoading = false;
        notifyListeners();
        return "Failed to create authenticated Google client.";
      }

      isGoogleDriveConnected = true;
      activeProvider = 'gdrive';
      notifyListeners();

      await openDrive('gdrive', folderId: 'root');
      return null; // Success
    } catch (e, stack) {
      debugPrint("Google Auth Error: $e\n$stack");
      isLoading = false;
      notifyListeners();

      final err = e.toString();
      if (err.contains('10') || err.contains('DEVELOPER_ERROR')) {
        return "Developer Error (10): Ensure your SHA-1 key and package name (com.samuel.winlauncher) are added to Google Cloud Console.";
      } else if (err.contains('12500')) {
        return "OAuth Error (12500): Check that OAuth consent screen is configured and support email is set in Google Cloud.";
      } else if (err.contains('access_denied') || err.contains('Access denied')) {
        return "Access denied: If your Google Cloud project is in 'Testing' mode, add your email as a Test User.";
      }
      return "Google Sign-in failed: ${err.replaceFirst('PlatformException(', '').replaceAll(')', '')}";
    }
  }

  Future<void> disconnectDrive(String provider) async {
    if (provider == 'gdrive') {
      try {
        await _googleSignIn.disconnect();
      } catch (_) {
        await _googleSignIn.signOut();
      }
      isGoogleDriveConnected = false;
      gDrivePathStack.clear();
      currentCloudFiles = [];
      activeProvider = '';
      driveErrorMessage = null;
      notifyListeners();
    }
  }

  Future<void> openDrive(String provider, {String? folderId, String? folderName, bool isBack = false}) async {
    activeProvider = provider;
    isLoading = true;
    driveErrorMessage = null;
    currentCloudFiles = [];
    notifyListeners();

    if (provider == 'gdrive') {
      if (folderId == null || folderId == 'root' || folderId.isEmpty) {
        gDrivePathStack = []; // Reset to root
      } else {
        if (isBack) {
          int idx = gDrivePathStack.indexWhere((e) => e['id'] == folderId);
          if (idx != -1) {
            gDrivePathStack = gDrivePathStack.sublist(0, idx + 1);
          }
        } else {
          gDrivePathStack.add({'id': folderId, 'name': folderName ?? 'Folder'});
        }
      }
      await _fetchGoogleDriveFiles(currentFolderId);
    }
    
    isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchGoogleDriveFiles(String folderId) async {
    try {
      driveErrorMessage = null;
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) {
        driveErrorMessage = "Authentication expired. Please reconnect Google Drive.";
        return;
      }

      final driveApi = drive.DriveApi(authClient);
      
      final fileList = await driveApi.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields: "files(id, name, mimeType, size, modifiedTime, thumbnailLink)",
        orderBy: "folder, name",
      );

      final files = fileList.files ?? [];
      
      currentCloudFiles = files.map((f) => CloudFile(
        id: f.id ?? '',
        name: f.name ?? 'Unknown',
        path: f.id ?? '',
        isFolder: f.mimeType == 'application/vnd.google-apps.folder',
        size: int.tryParse(f.size ?? '0') ?? 0,
        modifiedTime: f.modifiedTime,
        provider: 'gdrive',
        thumbnailLink: f.thumbnailLink,
      )).toList();
      
    } catch (e) {
      debugPrint("GDrive Fetch Error: $e");
      final err = e.toString();
      if (err.contains('Google Drive API has not been used') || err.contains('disabled')) {
        driveErrorMessage = "Google Drive API is disabled. Please enable it in your Google Cloud Console.";
      } else {
        driveErrorMessage = "Failed to load files: $e";
      }
    }
  }

  Future<void> deleteFile(String fileId) async {
    if (activeProvider == 'gdrive') {
      try {
        final authClient = await _googleSignIn.authenticatedClient();
        if (authClient == null) return;
        
        final driveApi = drive.DriveApi(authClient);
        await driveApi.files.delete(fileId);
        
        await _fetchGoogleDriveFiles(currentFolderId);
        notifyListeners();
      } catch (e) {
        debugPrint("GDrive Delete Error: $e");
      }
    }
  }

  Future<String?> downloadCloudFile(String fileId, String fileName) async {
    if (activeProvider == 'gdrive') {
      try {
        final authClient = await _googleSignIn.authenticatedClient();
        if (authClient == null) return null;

        final driveApi = drive.DriveApi(authClient);
        
        final drive.Media media = await driveApi.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;

        final tempDir = await getTemporaryDirectory();
        final sanitizedName = fileName.split('/').last.split('\\').last;
        final saveFile = File('${tempDir.path}/$sanitizedName');

        final sink = saveFile.openWrite();
        await media.stream.forEach((List<int> chunk) {
          sink.add(chunk);
        });
        await sink.flush();
        await sink.close();

        return saveFile.path;
      } catch (e) {
        debugPrint("GDrive Download Error: $e");
        return null;
      }
    }
    return null;
  }
}