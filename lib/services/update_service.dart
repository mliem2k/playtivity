import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/version_utils.dart';
import '../utils/update_launcher.dart';
import 'app_logger.dart';

class UpdateService {
  // The base URL for checking updates
  // static const String _baseUrl = 'https://raw.githubusercontent.com/mliem2k/playtivity/main';
  static const String _githubReleasesApi = 'https://api.github.com/repos/mliem2k/playtivity/releases';
  // static const String _nightlyInfoPath = 'nightly/latest-nightly-info.json';
  
  // Preference keys
  static const String _prefLastCheckTime = 'last_update_check_time';
  static const String _prefEnableNightly = 'enable_nightly_builds';
  static const String _prefCheckFrequency = 'update_check_frequency_hours';
  static const String _prefAutoDownload = 'auto_download_updates';

  // Update check information
  static UpdateInfo? _latestReleaseInfo;
  static UpdateInfo? _latestNightlyInfo;
  static bool _isCheckingForUpdates = false;

  // Get the current app version information
  static Future<AppVersionInfo> getCurrentAppVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
    );
  }

  // Check if user has opted in for nightly builds
  static Future<bool> getNightlyBuildPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnableNightly) ?? false;
  }
  
  // Set the nightly build preference
  static Future<void> setNightlyBuildPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnableNightly, value);
  }

  // Get update check frequency in hours
  static Future<int> getCheckFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefCheckFrequency) ?? 24; // Default to daily
  }
  
  // Set update check frequency
  static Future<void> setCheckFrequency(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefCheckFrequency, hours);
  }
  
  // Get auto download preference
  static Future<bool> getAutoDownloadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoDownload) ?? false; // Default to manual
  }
  
  // Set auto download preference
  static Future<void> setAutoDownloadPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoDownload, value);
  }
  
  // Should we check for updates now?
  static Future<bool> shouldCheckForUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_prefLastCheckTime) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final checkFrequencyMs = await getCheckFrequency() * 60 * 60 * 1000;
    
    // Check if it's been long enough since the last check
    return (now - lastCheck) >= checkFrequencyMs;
  }
  
  // Mark that we've checked for updates
  static Future<void> _markUpdateChecked() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_prefLastCheckTime, now);
  }
  
  // Check if current version is a nightly build
  static bool isCurrentVersionNightly(String version) {
    return version.contains('-nightly-');
  }
  
  // Auto-enable nightly builds if user is already on a nightly version
  static Future<void> autoEnableNightlyIfApplicable() async {
    try {
      final currentVersion = await getCurrentAppVersion();
      final isNightly = isCurrentVersionNightly(currentVersion.version);
      final nightlyEnabled = await getNightlyBuildPreference();
      
      if (isNightly && !nightlyEnabled) {
        AppLogger.info('Current version is nightly but preference is disabled. Auto-enabling nightly builds.');
        await setNightlyBuildPreference(true);
        AppLogger.info('Nightly builds preference automatically enabled');
      }
    } catch (e) {
      AppLogger.error('Error in auto-enable nightly check', e);
    }
  }

  // Check for updates (both release and nightly)
  static Future<UpdateCheckResult> checkForUpdates({bool forceCheck = false}) async {
    // Don't check multiple times simultaneously
    if (_isCheckingForUpdates) {
      AppLogger.info('Update check already in progress, skipping duplicate check');
      return UpdateCheckResult(
        hasUpdate: false,
        isNightly: false,
        updateInfo: null,
        error: 'Update check already in progress',
      );
    }
    
    // Don't check if not enough time has passed
    if (!forceCheck && !(await shouldCheckForUpdates())) {
      AppLogger.info('Skipping update check, too soon since last check');
      return UpdateCheckResult(
        hasUpdate: false,
        isNightly: false,
        updateInfo: null,
        error: 'Too soon since last check',
      );
    }
    
    try {
      _isCheckingForUpdates = true;
      
      // Get current device information
      final currentVersion = await getCurrentAppVersion();
      
      // Auto-enable nightly builds if user is on a nightly version
      await autoEnableNightlyIfApplicable();
      
      final useNightly = await getNightlyBuildPreference();
      
      AppLogger.info('Checking for updates...');
      AppLogger.info('Current version: ${currentVersion.version}+${currentVersion.buildNumber}');
      AppLogger.info('Is nightly version: ${isCurrentVersionNightly(currentVersion.version)}');
      AppLogger.info('Nightly builds enabled: $useNightly');
      
      // Fetch GitHub releases once and share with both checkers to avoid double API call
      final releasesJson = await _fetchGithubReleases();

      // Always check for regular release updates first
      final releaseCheck = _checkReleaseUpdatesFromJson(releasesJson, currentVersion);

      // Check for nightly updates if user has opted in
      UpdateCheckResult? nightlyCheck;
      if (useNightly) {
        nightlyCheck = _checkNightlyUpdatesFromJson(releasesJson, currentVersion);
      }
      
      // Mark that we've checked
      await _markUpdateChecked();
      
      // Determine if there's an update available
      // For nightly users, prioritize nightly updates and be more selective about stable updates
      if (useNightly) {
        AppLogger.info('User has nightly builds enabled');
        
        // If there's a nightly update available, prefer it
        if (nightlyCheck != null && nightlyCheck.hasUpdate) {
          AppLogger.info('Nightly update available: ${nightlyCheck.updateInfo?.version}');
          return nightlyCheck;
        }
        
        // For nightly users, only offer stable updates if they're significantly newer
        if (releaseCheck.hasUpdate && _shouldOfferStableToNightlyUser(currentVersion, releaseCheck)) {
          AppLogger.info('Stable release update available for nightly user: ${releaseCheck.updateInfo?.version}');
          return releaseCheck;
        }
        
        AppLogger.info('No suitable updates available for nightly user');
        return UpdateCheckResult(
          hasUpdate: false,
          isNightly: false,
          updateInfo: null,
        );
      }
      
      // For stable users, only offer release updates
      if (releaseCheck.hasUpdate) {
        AppLogger.info('Release update available: ${releaseCheck.updateInfo?.version}');
        return releaseCheck;
      }
      
      // No update available
      AppLogger.info('No updates available');
      return UpdateCheckResult(
        hasUpdate: false,
        isNightly: false,
        updateInfo: null,
      );
      
    } catch (e) {
      AppLogger.error('Error checking for updates', e);
      return UpdateCheckResult(
        hasUpdate: false,
        isNightly: false,
        updateInfo: null,
        error: 'Error checking for updates: ${e.toString()}',
      );
    } finally {
      _isCheckingForUpdates = false;
    }
  }
  
  // Fetch the releases list from GitHub (single HTTP call shared by both checkers)
  static Future<List<dynamic>> _fetchGithubReleases() async {
    final response = await http.get(Uri.parse(_githubReleasesApi));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch releases: HTTP ${response.statusCode}');
    }
    return json.decode(response.body) as List<dynamic>;
  }

  // Check for stable release updates from a pre-fetched releases list
  static UpdateCheckResult _checkReleaseUpdatesFromJson(
    List<dynamic> releasesJson,
    AppVersionInfo currentVersion,
  ) {
    try {
      Map<String, dynamic>? latestReleaseJson;
      for (final releaseJson in releasesJson) {
        final tagName = releaseJson['tag_name'] as String? ?? '';
        // Accept only semver-style tags (v1.2.3 or 1.2.3), excluding nightly
        // variants and the rolling `latest-nightly` pointer tag which is
        // recreated on every nightly build and pollutes the list.
        final isStableTag = (tagName.startsWith('v') || RegExp(r'^\d+\.\d+').hasMatch(tagName)) &&
            !tagName.contains('nightly');
        if (isStableTag) {
          latestReleaseJson = releaseJson as Map<String, dynamic>;
          break;
        }
      }

      if (latestReleaseJson == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          isNightly: false,
          updateInfo: null,
          error: 'No stable releases found',
        );
      }

      final releaseInfo = UpdateInfo.fromGithubJson(latestReleaseJson, isNightly: false);
      _latestReleaseInfo = releaseInfo;

      final hasUpdate = VersionUtils.isNewerVersion(
        currentVersion: currentVersion.version,
        newVersion: releaseInfo.version,
      );

      AppLogger.info('Release check: Current=${currentVersion.version}, Latest=${releaseInfo.version}, hasUpdate=$hasUpdate');

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        isNightly: false,
        updateInfo: hasUpdate ? releaseInfo : null,
      );
    } catch (e) {
      AppLogger.error('Error checking release updates', e);
      return UpdateCheckResult(
        hasUpdate: false,
        isNightly: false,
        updateInfo: null,
        error: 'Error checking release updates: ${e.toString()}',
      );
    }
  }

  // Check for nightly updates from a pre-fetched releases list
  static UpdateCheckResult _checkNightlyUpdatesFromJson(
    List<dynamic> releasesJson,
    AppVersionInfo currentVersion,
  ) {
    try {
      // Find the latest nightly release (tagged with 'nightly-' prefix)
      Map<String, dynamic>? latestNightlyJson;
      for (final releaseJson in releasesJson) {
        final tagName = releaseJson['tag_name'] as String? ?? '';
        if (tagName.startsWith('nightly-')) {
          latestNightlyJson = releaseJson as Map<String, dynamic>;
          break; // First one is the latest since releases are sorted by date
        }
      }
      
      if (latestNightlyJson == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          isNightly: true,
          updateInfo: null,
          error: 'No nightly releases found',
        );
      }

      final nightlyInfo = UpdateInfo.fromGithubJson(latestNightlyJson, isNightly: true);
      _latestNightlyInfo = nightlyInfo;

      // For nightlies, we compare build dates or if current version doesn't contain nightly
      final hasUpdate = _shouldUpdateToNightly(currentVersion.version, nightlyInfo);
      
      AppLogger.info('Nightly check: Latest=${nightlyInfo.version}, hasUpdate=$hasUpdate');
      
      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        isNightly: true,
        updateInfo: hasUpdate ? nightlyInfo : null,
      );
    } catch (e) {
      AppLogger.error('Error checking nightly updates', e);
      return UpdateCheckResult(
        hasUpdate: false,
        isNightly: true,
        updateInfo: null,
        error: 'Error checking nightly updates: ${e.toString()}',
      );
    }
  }
  
  // Helper method to determine if we should offer a stable release to a nightly user
  static bool _shouldOfferStableToNightlyUser(AppVersionInfo currentVersion, UpdateCheckResult releaseCheck) {
    if (releaseCheck.updateInfo == null) return false;
    
    final currentVersionString = currentVersion.version;
    final releaseVersionString = releaseCheck.updateInfo!.version;
    
    AppLogger.info('Checking if should offer stable to nightly user:');
    AppLogger.info('  Current nightly: $currentVersionString');
    AppLogger.info('  Available stable: $releaseVersionString');
    
    // Extract base versions for comparison
    final currentBase = VersionUtils.extractBaseVersion(currentVersionString);
    final releaseBase = VersionUtils.extractBaseVersion(releaseVersionString);
    
    AppLogger.info('  Current base: $currentBase');
    AppLogger.info('  Release base: $releaseBase');
    
    // Only offer stable if it has a higher major or minor version
    // Don't offer for patch-level updates to avoid unnecessary downgrades
    final currentBaseParts = currentBase.split('.');
    final releaseBaseParts = releaseBase.split('.');
    
    // Normalize to have at least 3 parts
    while (currentBaseParts.length < 3) {
      currentBaseParts.add('0');
    }
    while (releaseBaseParts.length < 3) {
      releaseBaseParts.add('0');
    }
    
    final currentMajor = int.tryParse(currentBaseParts[0]) ?? 0;
    final currentMinor = int.tryParse(currentBaseParts[1]) ?? 0;
    
    final releaseMajor = int.tryParse(releaseBaseParts[0]) ?? 0;
    final releaseMinor = int.tryParse(releaseBaseParts[1]) ?? 0;
    
    // Only offer if it's a major or minor version increase
    final shouldOffer = (releaseMajor > currentMajor) || 
                       (releaseMajor == currentMajor && releaseMinor > currentMinor);
    
    AppLogger.info('Should offer stable to nightly user: $shouldOffer');
    
    return shouldOffer;
  }

  // Helper method to determine if we should update to a nightly build
  static bool _shouldUpdateToNightly(String currentVersion, UpdateInfo nightlyInfo) {
    AppLogger.info('Checking if should update to nightly:');
    AppLogger.info('  Current version: $currentVersion');
    AppLogger.info('  New nightly version: ${nightlyInfo.version}');

    if (!currentVersion.contains('nightly')) {
      // Stable user: only offer nightly if its base version is >= the current stable version.
      // Without this check a stable `0.0.2` user would be prompted to "update" to a nightly
      // built against `0.0.1`, which would be a downgrade.
      final currentBase = VersionUtils.extractBaseVersion(currentVersion);
      final nightlyBase = VersionUtils.extractBaseVersion(nightlyInfo.version);
      final nightlyIsAtLeastSameBase = VersionUtils.isNewerVersion(
            currentVersion: currentBase,
            newVersion: nightlyBase,
          ) ||
          currentBase == nightlyBase;
      AppLogger.info('Stable→nightly: currentBase=$currentBase nightlyBase=$nightlyBase offer=$nightlyIsAtLeastSameBase');
      return nightlyIsAtLeastSameBase;
    }

    // Both nightly: compare build timestamps
    final shouldUpdate = VersionUtils.isNewerNightly(
      currentVersion: currentVersion,
      newVersion: nightlyInfo.version,
    );

    AppLogger.info('Should update to nightly: $shouldUpdate');
    return shouldUpdate;
  }
  
  // Download an update file with progress tracking
  static Future<UpdateDownloadResult> downloadUpdate(
    UpdateInfo updateInfo, {
    Function(DownloadProgress)? onProgress,
  }) async {
    try {
      AppLogger.info('Downloading update: ${updateInfo.version} (${updateInfo.apkUrl})');

      // Get the download directory
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/${updateInfo.apkFileName}';

      // Reuse an already-complete download (e.g. user cancelled the Android
      // installer prompt and tries again — no need to re-download).
      final existingFile = File(filePath);
      if (updateInfo.fileSizeBytes > 0 &&
          await existingFile.exists() &&
          await existingFile.length() == updateInfo.fileSizeBytes) {
        AppLogger.info('Reusing existing download: $filePath');
        return UpdateDownloadResult(
          success: true,
          filePath: filePath,
          updateInfo: updateInfo,
        );
      }

      // Create the file
      final file = File(filePath);
      
      // Start streaming download
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(updateInfo.apkUrl));
      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        return UpdateDownloadResult(
          success: false,
          filePath: null,
          error: 'Failed to download update: HTTP ${response.statusCode}',
        );
      }
      
      // Get total file size
      final totalBytes = response.contentLength ?? updateInfo.fileSizeBytes;
      AppLogger.info('Download size: $totalBytes bytes');
      
      // Prepare for streaming download
      int downloadedBytes = 0;
      final stopwatch = Stopwatch()..start();
      final sink = file.openWrite();
      
      try {
        await for (final chunk in response.stream) {
          downloadedBytes += chunk.length;
          sink.add(chunk);
          
          // Calculate progress and speed
          final elapsedMs = stopwatch.elapsedMilliseconds;
          final progress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
          final speedBytesPerSecond = elapsedMs > 0 ? (downloadedBytes * 1000) / elapsedMs : 0.0;
          
          // Estimate remaining time
          final remainingBytes = totalBytes - downloadedBytes;
          final estimatedRemainingSeconds = speedBytesPerSecond > 0 
              ? remainingBytes / speedBytesPerSecond 
              : 0.0;
          
          // Report progress
          if (onProgress != null) {
            final progressData = DownloadProgress(
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
              progress: progress,
              speedBytesPerSecond: speedBytesPerSecond,
              estimatedRemainingSeconds: estimatedRemainingSeconds,
            );
            onProgress(progressData);
          }
        }
      } finally {
        await sink.close();
        client.close();
      }
      
      AppLogger.info('Update downloaded successfully: $filePath');
      
      return UpdateDownloadResult(
        success: true,
        filePath: filePath,
        updateInfo: updateInfo,
      );
    } catch (e) {
      AppLogger.error('Error downloading update', e);
      return UpdateDownloadResult(
        success: false,
        filePath: null,
        error: 'Error downloading update: ${e.toString()}',
      );
    }
  }
  
  // Install a downloaded update
  static Future<bool> installUpdate(String filePath) async {
    try {
      AppLogger.info('Installing update: $filePath');
      
      // Check if we have permission to install packages
      final canInstall = await UpdateLauncher.canInstallPackages();
      if (!canInstall) {
        AppLogger.warning('No permission to install packages');
        return false;
      }
      
      return await UpdateLauncher.installApk(filePath);
    } catch (e) {
      AppLogger.error('Error installing update', e);
      return false;
    }
  }
  
  // Get the latest release info (if already fetched)
  static UpdateInfo? getLatestReleaseInfo() {
    return _latestReleaseInfo;
  }
  
  // Get the latest nightly info (if already fetched)
  static UpdateInfo? getLatestNightlyInfo() {
    return _latestNightlyInfo;
  }
}

// Data classes for update information
class UpdateInfo {
  final String version;
  final String buildNumber;
  final DateTime buildDate;
  final String apkUrl;
  final String apkFileName;
  final String? changelog;
  final bool isNightly;
  final int fileSizeBytes;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.buildDate,
    required this.apkUrl,
    required this.apkFileName,
    this.changelog,
    required this.isNightly,
    required this.fileSizeBytes,
  });

  factory UpdateInfo.fromGithubJson(Map<String, dynamic> json, {required bool isNightly}) {
    // JSON structure for GitHub releases API
    final tagName = json['tag_name'] as String;
    final releaseName = json['name'] as String? ?? tagName;
    final body = json['body'] as String? ?? '';
    
    AppLogger.info('Parsing GitHub release: tag=$tagName, name=$releaseName, isNightly=$isNightly');
    AppLogger.info('Release body preview: ${body.length > 100 ? '${body.substring(0, 100)}...' : body}');
    
    // Find APK asset
    Map<String, dynamic>? apkAsset;
    if (json['assets'] != null && (json['assets'] as List).isNotEmpty) {
      apkAsset = (json['assets'] as List).firstWhere(
        (asset) => asset['name'].toString().endsWith('.apk'),
        orElse: () => null,
      ) as Map<String, dynamic>?;
    }
    
    final apkUrl = apkAsset?['browser_download_url'] as String? ?? '';
    final apkFileName = apkUrl.isNotEmpty ? Uri.parse(apkUrl).pathSegments.last : '';
    final fileSizeBytes = apkAsset?['size'] as int? ?? 0;
    
    AppLogger.info('Found APK asset: $apkFileName ($fileSizeBytes bytes)');
    
    // Parse release date
    DateTime buildDate;
    try {
      buildDate = DateTime.parse(json['published_at'] as String);
    } catch (_) {
      buildDate = DateTime.now();
    }
    
    // For nightly builds, extract version and build number from the tag name or release body
    String version;
    String buildNumber = '';

    if (isNightly && tagName.startsWith('nightly-')) {
      AppLogger.info('Processing nightly release...');
      AppLogger.info('Tag name: $tagName');

      // Look for version information in the release body with multiple patterns
      // Pattern 1: **Version**: `x.x.x-nightly-YYYYMMDD-HHMMSS+buildnum`
      RegExp versionRegex = RegExp(r'\*\*Version\*\*:\s*`([^`]+)`', caseSensitive: false);
      RegExpMatch? versionMatch = versionRegex.firstMatch(body);

      // Pattern 2: Version: x.x.x-nightly-YYYYMMDD-HHMMSS+buildnum
      if (versionMatch == null) {
        versionRegex = RegExp(r'Version:\s*([^\s\n]+)', caseSensitive: false);
        versionMatch = versionRegex.firstMatch(body);
      }

      // Pattern 3: - **Version**: `x.x.x-nightly-YYYYMMDD-HHMMSS+buildnum`
      if (versionMatch == null) {
        versionRegex = RegExp(r'-\s*\*\*Version\*\*:\s*`([^`]+)`', caseSensitive: false);
        versionMatch = versionRegex.firstMatch(body);
      }

      if (versionMatch != null) {
        final fullVersion = versionMatch.group(1)!.trim();
        AppLogger.info('Found version in release body: $fullVersion');

        // Split version and build number (format: version+buildNumber)
        final versionParts = fullVersion.split('+');
        version = versionParts[0];

        if (versionParts.length > 1) {
          buildNumber = versionParts[1];
          AppLogger.info('Parsed nightly version: $version, buildNumber: $buildNumber');
        } else {
          // Try to extract build number from version string
          final buildMatch = RegExp(r'\+(\d+)').firstMatch(fullVersion);
          if (buildMatch != null) {
            buildNumber = buildMatch.group(1) ?? '';
          }
          AppLogger.info('Parsed nightly version (no + found): $version, buildNumber: $buildNumber');
        }
      } else {
        // Fallback: construct version from tag name
        // Tag format: nightly-YYYYMMDD-HHMMSS
        // We need to extract base version from somewhere
        AppLogger.warning('Could not find version in release body, using fallback');

        // Try to find base version in body
        final baseVersionRegex = RegExp(r'\*\*Base Version\*\*:\s*`([^`]+)`', caseSensitive: false);
        final baseVersionMatch = baseVersionRegex.firstMatch(body);

        String baseVersion = '0.0.2'; // Default fallback
        if (baseVersionMatch != null) {
          baseVersion = baseVersionMatch.group(1)!.trim();
          AppLogger.info('Found base version: $baseVersion');
        }

        // Extract date-time from tag (format: nightly-YYYYMMDD-HHMMSS)
        final tagParts = tagName.substring('nightly-'.length); // Remove 'nightly-' prefix
        version = '$baseVersion-nightly-$tagParts';

        // Use published_at timestamp as build number
        buildNumber = (buildDate.millisecondsSinceEpoch ~/ 1000).toString();

        AppLogger.info('Constructed fallback version: $version, buildNumber: $buildNumber');
      }
    } else {
      // For regular/stable releases
      AppLogger.info('Processing stable release...');
      version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      AppLogger.info('Initial version from tag: $version');
      
      // Look for version information in the release body
      RegExp versionRegex = RegExp(r'Version[:\s]*`?([^`\s\n]+)`?', caseSensitive: false);
      RegExpMatch? versionMatch = versionRegex.firstMatch(body);
      
      if (versionMatch != null) {
        final bodyVersion = versionMatch.group(1)!.trim();
        AppLogger.info('Found version in release body: $bodyVersion');
        // Use body version if it's more detailed than tag name
        if (bodyVersion.length > version.length) {
          version = bodyVersion;
          AppLogger.info('Using body version instead of tag: $version');
        }
      }
      
      // Look for build number in the release body
      RegExp buildRegex = RegExp(r'Build Number[:\s]*`?(\d+)`?', caseSensitive: false);
      RegExpMatch? buildMatch = buildRegex.firstMatch(body);
      
      if (buildMatch != null) {
        buildNumber = buildMatch.group(1) ?? '';
        AppLogger.info('Found build number in release body: $buildNumber');
      } else {
        // Fallback: try to extract from release name
        final fallbackBuildMatch = RegExp(r'build\s*(\d+)', caseSensitive: false).firstMatch(releaseName);
        if (fallbackBuildMatch != null) {
          buildNumber = fallbackBuildMatch.group(1) ?? '';
          AppLogger.info('Found build number in release name: $buildNumber');
        } else {
          AppLogger.info('No build number found, using empty string');
        }
      }
      
      AppLogger.info('Parsed stable release: version=$version, buildNumber=$buildNumber');
    }
    
    return UpdateInfo(
      version: version,
      buildNumber: buildNumber,
      buildDate: buildDate,
      apkUrl: apkUrl,
      apkFileName: apkFileName,
      changelog: json['body'] as String?,
      isNightly: isNightly,
      fileSizeBytes: fileSizeBytes,
    );
  }
}

class AppVersionInfo {
  final String version;
  final String buildNumber;
  
  AppVersionInfo({
    required this.version,
    required this.buildNumber,
  });
}

class UpdateCheckResult {
  final bool hasUpdate;
  final bool isNightly;
  final UpdateInfo? updateInfo;
  final String? error;
  
  UpdateCheckResult({
    required this.hasUpdate,
    required this.isNightly,
    required this.updateInfo,
    this.error,
  });
}

class UpdateDownloadResult {
  final bool success;
  final String? filePath;
  final UpdateInfo? updateInfo;
  final String? error;
  
  UpdateDownloadResult({
    required this.success,
    required this.filePath,
    this.updateInfo,
    this.error,
  });
}

class DownloadProgress {
  final int downloadedBytes;
  final int totalBytes;
  final double progress;
  final double speedBytesPerSecond;
  final double estimatedRemainingSeconds;

  DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    required this.speedBytesPerSecond,
    required this.estimatedRemainingSeconds,
  });
}

