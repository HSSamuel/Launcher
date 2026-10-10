import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../models/cloud_file_model.dart';

class CloudDriveState extends ChangeNotifier {
  // Upgraded to full driveScope so we have permission to Delete and Modify files
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveScope],
  );

  bool isGoogleDriveConnected = false;
  bool isLoading = false;
  List<CloudFile> currentCloudFiles = [];
  String activeProvider = '';

  // Google Drive uses a stack array to track breadcrumbs because it relies on unique IDs, not file paths.
  List<Map<String, String>> gDrivePathStack = [];

  String get currentFolderId => gDrivePathStack.isNotEmpty ? gDrivePathStack.last['id']! : 'root';

  CloudDriveState() {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      isGoogleDriveConnected = account != null;
      notifyListeners();
    });
    // Silently log in if the user already authenticated previously
    _googleSignIn.signInSilently();
  }

  // CRITICAL FIX: Return a boolean and directly check the account instead of waiting for the stream listener
  Future<bool> connectGoogleDrive() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        isGoogleDriveConnected = true;
        notifyListeners();
        await openDrive('gdrive', folderId: 'root');
        return true;
      }
    } catch (e) {
      debugPrint("Google Auth Error: $e");
    }
    return false;
  }

  Future<void> disconnectDrive(String provider) async {
    if (provider == 'gdrive') {
      await _googleSignIn.signOut();
      isGoogleDriveConnected = false;
      gDrivePathStack.clear();
      currentCloudFiles = [];
      activeProvider = '';
      notifyListeners();
    }
  }

  Future<void> openDrive(String provider, {String? folderId, String? folderName, bool isBack = false}) async {
    activeProvider = provider;
    isLoading = true;
    currentCloudFiles = [];
    notifyListeners();

    if (provider == 'gdrive') {
      if (folderId == null || folderId == 'root' || folderId.isEmpty) {
        gDrivePathStack = []; // Reset to root
      } else {
        if (isBack) {
          // If we clicked a breadcrumb to go back
          int idx = gDrivePathStack.indexWhere((e) => e['id'] == folderId);
          if (idx != -1) {
            gDrivePathStack = gDrivePathStack.sublist(0, idx + 1);
          }
        } else {
          // Moving forward into a new folder
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
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) return;

      final driveApi = drive.DriveApi(authClient);
      
      // Query Google Drive for items inside the target folder ID
      final fileList = await driveApi.files.list(
        q: "'$folderId' in parents and trashed = false",
        // Request the thumbnailLink property so we can display image previews
        $fields: "files(id, name, mimeType, size, modifiedTime, thumbnailLink)",
        orderBy: "folder, name"
      );

      final files = fileList.files ?? [];
      
      currentCloudFiles = files.map((f) => CloudFile(
        id: f.id ?? '',
        name: f.name ?? 'Unknown',
        path: f.id ?? '', // For GDrive, we use ID as path
        isFolder: f.mimeType == 'application/vnd.google-apps.folder',
        size: int.tryParse(f.size ?? '0') ?? 0,
        modifiedTime: f.modifiedTime,
        provider: 'gdrive',
        thumbnailLink: f.thumbnailLink,
      )).toList();
      
    } catch (e) {
      debugPrint("GDrive Fetch Error: $e");
    }
  }

  Future<void> deleteFile(String fileId) async {
    if (activeProvider == 'gdrive') {
      try {
        final authClient = await _googleSignIn.authenticatedClient();
        if (authClient == null) return;
        
        final driveApi = drive.DriveApi(authClient);
        
        // Delete the file using the official Google Drive API
        await driveApi.files.delete(fileId);
        
        // Refresh the current folder after deletion to update the UI
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
        
        // Request the raw media stream from Google Drive
        final drive.Media media = await driveApi.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;

        // Get the device's temporary cache directory
        final tempDir = await getTemporaryDirectory();
        final saveFile = File('${tempDir.path}/$fileName');

        // Stream the bytes into the local file
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