import 'package:flutter/foundation.dart';

/// Utility class for comparing version strings and handling
/// version-related functionality.
class VersionUtils {
  /// Extract base version from any version string (removes nightly suffixes)
  static String extractBaseVersion(String version) {
    // Remove build metadata first
    final withoutBuild = version.split('+')[0];
    
    // If it contains nightly, extract everything before the first -nightly-
    if (withoutBuild.contains('-nightly-')) {
      return withoutBuild.split('-nightly-')[0];
    }
    
    return withoutBuild;
  }

  /// Compares two version strings to determine if newVersion is newer than currentVersion.
  /// 
  /// Versions are expected to be in format "x.y.z" or "x.y.z-suffix".
  /// For example: "1.2.3" or "1.2.0-beta.4"
  static bool isNewerVersion({
    required String currentVersion,
    required String newVersion,
  }) {
    debugPrint('Comparing versions: current=$currentVersion, new=$newVersion');
    
    // Handle nightly versions by checking if they are nightlies
    if (currentVersion.contains('nightly') && newVersion.contains('nightly')) {
      // For nightlies, we should use isNewerNightly
      debugPrint('Both are nightly versions, use isNewerNightly instead');
      return false;
          } else if (currentVersion.contains('nightly') && !newVersion.contains('nightly')) {
      // If current is nightly but new is stable release, compare base versions
      final currentBase = extractBaseVersion(currentVersion);
      final newBase = extractBaseVersion(newVersion);
      
      debugPrint('Nightly vs Stable comparison:');
      debugPrint('  Current nightly: $currentVersion -> base: $currentBase');
      debugPrint('  New stable: $newVersion -> base: $newBase');
      
      // Only prefer stable release if it has a genuinely higher base version
      final baseVersionComparison = _compareBaseVersions(currentBase, newBase);
      debugPrint('  Base version comparison result: $baseVersionComparison (positive = stable newer)');
      
      final shouldUpdate = baseVersionComparison > 0;
      debugPrint('  Should update from nightly to stable: $shouldUpdate');
      
      return shouldUpdate; // Only true if stable has higher base version
    } else if (!currentVersion.contains('nightly') && newVersion.contains('nightly')) {
      // If current is release but new is nightly, don't update unless explicitly requested
      debugPrint('Current is stable, new is nightly - not updating');
      return false;
    }

    // Both are stable versions, do normal comparison
    return _compareBaseVersions(currentVersion, newVersion) > 0;
  }
  
  /// Compare base versions (without any suffixes)
  static int _compareBaseVersions(String version1, String version2) {
    // Strip any build metadata (anything after +)
    final v1Clean = version1.split('+')[0];
    final v2Clean = version2.split('+')[0];

    // Split versions into parts (split by periods or dashes)
    final v1Parts = v1Clean.split('-');
    final v2Parts = v2Clean.split('-');
    
    // Compare base version parts (x.y.z)
    final v1BaseParts = v1Parts[0].split('.');
    final v2BaseParts = v2Parts[0].split('.');
    
    // Normalize to have at least 3 parts (x.y.z)
    while (v1BaseParts.length < 3) v1BaseParts.add('0');
    while (v2BaseParts.length < 3) v2BaseParts.add('0');
    
    // Compare major.minor.patch parts
    for (int i = 0; i < 3; i++) {
      final v1Part = int.tryParse(v1BaseParts[i]) ?? 0;
      final v2Part = int.tryParse(v2BaseParts[i]) ?? 0;
      
      if (v2Part > v1Part) return 1;  // v2 is newer
      if (v2Part < v1Part) return -1; // v1 is newer
    }
    
    // Base versions are equal, check pre-release identifiers (e.g., -beta, -rc)
    // A version with no pre-release part is greater than one with a pre-release part
    if (v1Parts.length == 1 && v2Parts.length > 1) return -1; // v1 is newer (stable vs pre-release)
    if (v1Parts.length > 1 && v2Parts.length == 1) return 1;  // v2 is newer (stable vs pre-release)
    
    // If both have pre-release parts, compare them lexicographically
    if (v1Parts.length > 1 && v2Parts.length > 1) {
      return v2Parts[1].compareTo(v1Parts[1]);
    }
    
    // Versions are equal
    return 0;
  }
  
  /// Specifically compares nightly build versions based on build date/time
  /// 
  /// Nightly versions are expected to be in format "x.y.z-nightly-YYYYMMDD-HHMMSS"
  static bool isNewerNightly({
    required String currentVersion, 
    required String newVersion,
    required DateTime newBuildTime,
  }) {
    debugPrint('Comparing nightly versions:');
    debugPrint('  Current: $currentVersion');
    debugPrint('  New: $newVersion');
    debugPrint('  New build time: $newBuildTime');
    
    // First, check if the versions are exactly the same (ignoring build metadata after +)
    final currentClean = currentVersion.split('+')[0];
    final newClean = newVersion.split('+')[0];
    
    if (currentClean == newClean) {
      debugPrint('  Versions are identical (ignoring build metadata), no update needed');
      return false;
    }
    
    // Extract the build timestamp from the current version string if possible
    DateTime? currentBuildTime;
    
    try {
      if (currentVersion.contains('nightly')) {
        // Handle complex nightly version strings that may have multiple nightly parts
        final nightlyRegex = RegExp(r'nightly-(\d{8})-(\d{6})');
        final matches = nightlyRegex.allMatches(currentVersion);
        
        if (matches.isNotEmpty) {
          // Use the last (most recent) nightly timestamp in the version string
          final lastMatch = matches.last;
          final datePart = lastMatch.group(1)!; // YYYYMMDD
          final timePart = lastMatch.group(2)!; // HHMMSS
          
          final year = int.parse(datePart.substring(0, 4));
          final month = int.parse(datePart.substring(4, 6));
          final day = int.parse(datePart.substring(6, 8));
          final hour = int.parse(timePart.substring(0, 2));
          final minute = int.parse(timePart.substring(2, 4));
          final second = int.parse(timePart.substring(4, 6));
          
          currentBuildTime = DateTime(year, month, day, hour, minute, second);
          debugPrint('  Parsed current build time: $currentBuildTime');
        }
      }
    } catch (e) {
      debugPrint('Error parsing current nightly version: $e');
    }
    
    // If we can't determine build time from version string or they're too close, 
    // use a more lenient comparison
    if (currentBuildTime == null) {
      debugPrint('  Could not parse current build time, using version string comparison');
      return isNewerVersion(currentVersion: currentVersion, newVersion: newVersion);
    }
    
    // Compare build times with a threshold to avoid updates for very recent builds
    final timeDifference = newBuildTime.difference(currentBuildTime);
    const minimumUpdateThreshold = Duration(minutes: 5); // Minimum 5 minutes difference
    
    final isNewer = timeDifference > minimumUpdateThreshold;
    debugPrint('  Time difference: ${timeDifference.inMinutes} minutes');
    debugPrint('  Is newer: $isNewer');
    
    return isNewer;
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
