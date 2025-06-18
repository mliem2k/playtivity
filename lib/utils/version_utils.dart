import 'package:flutter/foundation.dart';

/// Utility class for comparing version strings and handling
/// version-related functionality.
class VersionUtils {
  /// Compares two version strings to determine if newVersion is newer than currentVersion.
  /// 
  /// Versions are expected to be in format "x.y.z" or "x.y.z-suffix".
  /// For example: "1.2.3" or "1.2.0-beta.4"
  static bool isNewerVersion({
    required String currentVersion,
    required String newVersion,
  }) {
    // Handle nightly versions by checking if they are nightlies
    if (currentVersion.contains('nightly') && newVersion.contains('nightly')) {
      // For nightlies, we should use isNewerNightly
      debugPrint('Both are nightly versions, use isNewerNightly instead');
      return false;
    } else if (currentVersion.contains('nightly') && !newVersion.contains('nightly')) {
      // If current is nightly but new is release, prefer the release
      return true;
    } else if (!currentVersion.contains('nightly') && newVersion.contains('nightly')) {
      // If current is release but new is nightly, don't update unless explicitly requested
      return false;
    }

    // Strip any build metadata (anything after +)
    final currentClean = currentVersion.split('+')[0];
    final newClean = newVersion.split('+')[0];

    // Split versions into parts (split by periods or dashes)
    final currentParts = currentClean.split('-');
    final newParts = newClean.split('-');
    
    // Compare base version parts (x.y.z)
    final currentBaseParts = currentParts[0].split('.');
    final newBaseParts = newParts[0].split('.');
    
    // Normalize to have at least 3 parts (x.y.z)
    while (currentBaseParts.length < 3) currentBaseParts.add('0');
    while (newBaseParts.length < 3) newBaseParts.add('0');
    
    // Compare major.minor.patch parts
    for (int i = 0; i < 3; i++) {
      final current = int.tryParse(currentBaseParts[i]) ?? 0;
      final next = int.tryParse(newBaseParts[i]) ?? 0;
      
      if (next > current) return true;
      if (next < current) return false;
    }
    
    // If base versions are equal, check pre-release identifiers (e.g., -beta, -rc)
    // A version with no pre-release part is greater than one with a pre-release part
    if (currentParts.length == 1 && newParts.length > 1) return false;
    if (currentParts.length > 1 && newParts.length == 1) return true;
    
    // If both have pre-release parts, compare them
    if (currentParts.length > 1 && newParts.length > 1) {
      return newParts[1].compareTo(currentParts[1]) > 0;
    }
    
    // Versions are equal
    return false;
  }
  
  /// Specifically compares nightly build versions based on build date/time
  /// 
  /// Nightly versions are expected to be in format "x.y.z-nightly-YYYYMMDD-HHMMSS"
  static bool isNewerNightly({
    required String currentVersion, 
    required String newVersion,
    required DateTime newBuildTime,
  }) {
    // Extract the build timestamp from the version string if possible
    // Nightly versions typically have format: x.y.z-nightly-YYYYMMDD-HHMMSS
    DateTime? currentBuildTime;
    
    try {
      if (currentVersion.contains('nightly')) {
        final parts = currentVersion.split('-nightly-');
        if (parts.length > 1) {
          final dateTimePart = parts[1].split('+')[0];
          
          // Try to parse the date/time part
          if (dateTimePart.length >= 8) {
            // Format is YYYYMMDD or YYYYMMDD-HHMMSS
            final datePart = dateTimePart.substring(0, 8);
            final year = int.parse(datePart.substring(0, 4));
            final month = int.parse(datePart.substring(4, 6));
            final day = int.parse(datePart.substring(6, 8));
            
            int hour = 0, minute = 0, second = 0;
            if (dateTimePart.length >= 15 && dateTimePart.contains('-')) {
              final timePart = dateTimePart.substring(9, 15);
              hour = int.parse(timePart.substring(0, 2));
              minute = int.parse(timePart.substring(2, 4));
              second = int.parse(timePart.substring(4, 6));
            }
            
            currentBuildTime = DateTime(year, month, day, hour, minute, second);
          }
        }
      }
    } catch (e) {
      debugPrint('Error parsing current nightly version: $e');
      // Fall back to normal version comparison
    }
    
    // If we can't determine build time from version string, compare normal versions
    if (currentBuildTime == null) {
      return isNewerVersion(currentVersion: currentVersion, newVersion: newVersion);
    }
    
    // Compare build times
    return newBuildTime.isAfter(currentBuildTime);
  }
  
  /// Formats the version string in a human-readable format.
  /// 
  /// For example:
  /// - "1.2.3" -> "1.2.3"
  /// - "1.2.0-beta.4" -> "1.2.0 Beta 4"
  /// - "1.2.3-nightly-20250615-030600" -> "1.2.3 Nightly (Jun 15, 2025)"
  static String formatVersion(String version) {
    // Strip any build metadata (anything after +)
    final clean = version.split('+')[0];
    
    // Check if it's a nightly build
    if (clean.contains('nightly')) {
      try {
        final parts = clean.split('-nightly-');
        final baseVersion = parts[0];
        final dateTimePart = parts.length > 1 ? parts[1] : '';
        
        // Try to parse the date part
        if (dateTimePart.length >= 8) {
          final year = int.parse(dateTimePart.substring(0, 4));
          final month = int.parse(dateTimePart.substring(4, 6));
          final day = int.parse(dateTimePart.substring(6, 8));
            final date = DateTime(year, month, day);
          return '$baseVersion Nightly (${_formatDate(date)})';
        }
        
        return '$baseVersion Nightly';
      } catch (e) {
        return clean;
      }
    }
    
    // Handle other pre-release versions
    final parts = clean.split('-');
    if (parts.length == 1) {
      return clean; // Regular version with no suffix
    }
    
    // Format pre-release part (e.g., beta.4 -> Beta 4)
    final baseVersion = parts[0];
    final preReleaseParts = parts[1].split('.');
    
    if (preReleaseParts.isEmpty) {
      return clean;
    }
    
    final preReleaseType = preReleaseParts[0].capitalize();
    if (preReleaseParts.length == 1) {
      return '$baseVersion $preReleaseType';
    }
    
    return '$baseVersion $preReleaseType ${preReleaseParts[1]}';
  }
    // Helper for formatting dates
  static String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

// Helper extension
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
