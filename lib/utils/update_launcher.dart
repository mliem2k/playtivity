import 'dart:io';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_logger.dart';

/// Utility class to handle launching APK installation
/// and other update-related functionality.
class UpdateLauncher {
  /// Platform channel for native APK installation
  static const platform = MethodChannel('com.mliem.playtivity/update_launcher');
  
  /// Installs an APK file from the provided path.
  /// 
  /// Returns true if the installation was started successfully.
  /// Note: The app will be terminated by the Android system during installation.
  static Future<bool> installApk(String filePath) async {
    try {
      if (!Platform.isAndroid) {
        AppLogger.error('APK installation is only supported on Android');
        return false;
      }
      
      // Check if the file exists
      final file = File(filePath);
      if (!await file.exists()) {
        AppLogger.error('APK file does not exist: $filePath');
        return false;
      }
      
      // Log information
      AppLogger.info('Installing APK from: $filePath');
      
      // For Android, use platform-specific code to install the APK
      try {
        // Try using the platform channel first
        await platform.invokeMethod('installApk', {'filePath': filePath});
        return true;
      } on PlatformException catch (e) {
        // If platform channel fails, fallback to opening the file with Intent
        AppLogger.warning('Platform channel failed, falling back to file intent: ${e.message}');
        
        // Convert file path to URI and launch it
        final uri = Uri.file(filePath);
        return await _launchFileIntent(uri);
      }
    } catch (e) {
      AppLogger.error('Error installing APK', e);
      return false;
    }
  }
  
  /// Launches a URI to open a file with the appropriate intent.
  /// 
  /// Used for APK installation when the platform channel is not available.
  static Future<bool> _launchFileIntent(Uri uri) async {
    try {
      // For APKs, we need to add the mime type and ensure proper intent flags
      final canLaunch = await canLaunchUrl(uri);
      
      if (!canLaunch) {
        AppLogger.error('Cannot launch file: ${uri.toString()}');
        return false;
      }
      
      // Launch with specific parameters for APK files
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      AppLogger.error('Error launching file intent', e);
      return false;
    }
  }
}
