import 'dart:io';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_logger.dart';

/// Utility class to handle launching APK installation
/// and other update-related functionality.
class UpdateLauncher {
  /// Platform channel for native APK installation
  static const platform = MethodChannel('com.mliem.playtivity/update_launcher');
  
  /// Check if the app has permission to install packages
  static Future<bool> canInstallPackages() async {
    try {
      if (!Platform.isAndroid) {
        return false;
      }
      
      final result = await platform.invokeMethod('canInstallPackages');
      return result == true;
    } catch (e) {
      AppLogger.error('Error checking install permission', e);
      return false;
    }
  }
  
  /// Request permission to install packages (Android 8.0+)
  static Future<bool> requestInstallPermission() async {
    try {
      if (!Platform.isAndroid) {
        return false;
      }
      
      final result = await platform.invokeMethod('requestInstallPermission');
      AppLogger.info('Install permission request result: $result');
      return result == "PERMISSION_ALREADY_GRANTED" || result == "PERMISSION_NOT_REQUIRED";
    } catch (e) {
      AppLogger.error('Error requesting install permission', e);
      return false;
    }
  }
  
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
      
      // Check file size to ensure it's not corrupted
      final fileSize = await file.length();
      AppLogger.info('Installing APK from: $filePath ($fileSize bytes)');
      
      if (fileSize < 1024 * 1024) { // Less than 1MB is suspicious for an APK
        AppLogger.warning('APK file seems too small: $fileSize bytes');
      }
      
      // Check file permissions
      final stat = await file.stat();
      AppLogger.info('File permissions: ${stat.mode}, modified: ${stat.modified}');
      
      // For Android, try multiple approaches
      Exception? lastException;
      
      // Approach 1: Try using the platform channel first
      try {
        AppLogger.info('Attempting installation via platform channel...');
        await platform.invokeMethod('installApk', {'filePath': filePath});
        AppLogger.info('Platform channel installation initiated successfully');
        return true;
      } on PlatformException catch (e) {
        lastException = e;
        AppLogger.warning('Platform channel failed: $e.message (Code: $e.code)');
        AppLogger.info('Details: $e.details');
      } catch (e) {
        lastException = Exception('Platform channel error: $e');
        AppLogger.error('Unexpected platform channel error', e);
      }
      
      // Approach 2: Fallback to URL launcher
      try {
        AppLogger.info('Attempting installation via URL launcher...');
        final uri = Uri.file(filePath);
        final canLaunch = await canLaunchUrl(uri);
        
        if (!canLaunch) {
          AppLogger.error('Cannot launch file URI: ${uri.toString()}');
          return false;
        }
        
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (launched) {
          AppLogger.info('URL launcher installation initiated successfully');
          return true;
        } else {
          AppLogger.error('URL launcher failed to launch');
          return false;
        }
      } catch (e) {
        AppLogger.error('URL launcher error', e);
        lastException = Exception('URL launcher error: $e');
      }
      
      // Approach 3: Final fallback - try Android package installer intent
      try {
        AppLogger.info('Attempting installation via direct intent...');
        await platform.invokeMethod('installApkDirect', {'filePath': filePath});
        AppLogger.info('Direct intent installation initiated successfully');
        return true;
      } on PlatformException catch (e) {
        AppLogger.warning('Direct intent failed: ${e.message}');
      } catch (e) {
        AppLogger.error('Direct intent error', e);
      }
      
      // All approaches failed
      AppLogger.error('All installation approaches failed. Last error: $lastException');
      return false;
      
    } catch (e) {
      AppLogger.error('Error installing APK', e);
      return false;
    }
  }
  

}
