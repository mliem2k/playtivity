import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/version_utils.dart';
import '../utils/update_launcher.dart';
import 'app_logger.dart';

class UpdateService {
  // The base URL for checking updates
  static const String _baseUrl = 'https://raw.githubusercontent.com/mliem/playtivity/main';
  static const String _githubReleasesApi = 'https://api.github.com/repos/mliem/playtivity/releases';
  static const String _nightlyInfoPath = 'nightly/latest-nightly-info.json';
  
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
      final useNightly = await getNightlyBuildPreference();
      
      AppLogger.info('Checking for updates...');
      AppLogger.info('Current version: ${currentVersion.version}+${currentVersion.buildNumber}');
      AppLogger.info('Nightly builds enabled: $useNightly');
      
      // Always check for regular release updates first
      final releaseCheck = await _checkReleaseUpdates(currentVersion);
      
      // Check for nightly updates if user has opted in
      UpdateCheckResult? nightlyCheck;
      if (useNightly) {
        nightlyCheck = await _checkNightlyUpdates(currentVersion);
      }
      
      // Mark that we've checked
      await _markUpdateChecked();
      
      // Determine if there's an update available
      // Prefer nightly if user opted in and it's newer than release
      if (useNightly && nightlyCheck != null && nightlyCheck.hasUpdate) {
        AppLogger.info('Nightly update available: ${nightlyCheck.updateInfo?.version}');
        return nightlyCheck;
      }
      
      // Otherwise return the release update if available
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
  
  // Check for release updates
  static Future<UpdateCheckResult> _checkReleaseUpdates(AppVersionInfo currentVersion) async {
    try {
      // Fetch the release information from GitHub API
      final response = await http.get(Uri.parse(_githubReleasesApi));
      
      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate: false,
          isNightly: false,
          updateInfo: null,
          error: 'Failed to fetch release info: HTTP ${response.statusCode}',
        );
      }

      final List<dynamic> releasesJson = json.decode(response.body);
      
      // Find the latest release (first one in the list is the latest)
      final latestReleaseJson = releasesJson.isNotEmpty ? releasesJson[0] : null;
      if (latestReleaseJson == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          isNightly: false,
          updateInfo: null,
          error: 'No releases found',
        );
      }
      
      final releaseInfo = UpdateInfo.fromGithubJson(latestReleaseJson, isNightly: false);
      _latestReleaseInfo = releaseInfo;
      
      // Compare versions
      final hasUpdate = VersionUtils.isNewerVersion(
        currentVersion: currentVersion.version, 
        newVersion: releaseInfo.version,
      );
      
      AppLogger.info('Release check: Latest=${releaseInfo.version}, hasUpdate=$hasUpdate');
      
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
    // Check for nightly updates
  static Future<UpdateCheckResult> _checkNightlyUpdates(AppVersionInfo currentVersion) async {
    try {
      // Fetch the nightly information
      final response = await http.get(Uri.parse('$_baseUrl/$_nightlyInfoPath'));
      
      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate: false,
          isNightly: true,
          updateInfo: null,
          error: 'Failed to fetch nightly info: HTTP ${response.statusCode}',
        );
      }

      final nightlyJson = json.decode(response.body);
      final nightlyInfo = UpdateInfo.fromJson(nightlyJson, isNightly: true);
      _latestNightlyInfo = nightlyInfo;

      // For nightlies, we compare build dates - nightlies have a buildDate field
      final hasUpdate = VersionUtils.isNewerNightly(
        currentVersion: currentVersion.version, 
        newVersion: nightlyInfo.version,
        newBuildTime: nightlyInfo.buildDate,
      );
      
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
  
  // Download an update file
  static Future<UpdateDownloadResult> downloadUpdate(UpdateInfo updateInfo) async {
    try {
      AppLogger.info('Downloading update: ${updateInfo.version} (${updateInfo.apkUrl})');
      
      // Get the download directory
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/${updateInfo.apkFileName}';
      
      // Create the file
      final file = File(filePath);
      
      // Download the file
      final response = await http.get(Uri.parse(updateInfo.apkUrl));
      
      if (response.statusCode != 200) {
        return UpdateDownloadResult(
          success: false,
          filePath: null,
          error: 'Failed to download update: HTTP ${response.statusCode}',
        );
      }
      
      // Write the file
      await file.writeAsBytes(response.bodyBytes);
      
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
  
  // Show update dialog to the user
  static Future<bool> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(updateInfo.isNightly ? 'Nightly Update Available' : 'Update Available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('A new ${updateInfo.isNightly ? 'nightly' : 'release'} version is available: ${updateInfo.version}'),
              const SizedBox(height: 8),
              if (updateInfo.changelog != null && updateInfo.changelog!.isNotEmpty) ...[
                const Text('Changes:'),
                const SizedBox(height: 4),
                Text(updateInfo.changelog!, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
              ],
              if (updateInfo.isNightly)
                const Text('⚠️ Nightly builds may contain bugs or incomplete features.', 
                  style: TextStyle(color: Colors.orange),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Update Now'),
            ),
          ],
        );
      },
    ) ?? false;
  }
  
  // Install a downloaded update
  static Future<bool> installUpdate(String filePath) async {
    try {
      AppLogger.info('Installing update: $filePath');
      return await UpdateLauncher.installApk(filePath);
    } catch (e) {
      AppLogger.error('Error installing update', e);
      return false;
    }
  }
  
  // Show a download progress dialog
  static Future<String?> showDownloadDialog(BuildContext context, UpdateInfo updateInfo) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return FutureBuilder<UpdateDownloadResult>(
          future: downloadUpdate(updateInfo),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                title: const Text('Downloading Update'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Please wait while we download the update...'),
                  ],
                ),
              );
            } else {
              if (snapshot.hasError || (snapshot.data != null && !snapshot.data!.success)) {
                return AlertDialog(
                  title: const Text('Download Failed'),
                  content: Text('Failed to download the update: ${snapshot.error ?? snapshot.data?.error ?? 'Unknown error'}'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(null);
                      },
                      child: const Text('OK'),
                    ),
                  ],
                );
              } else {
                // Auto-close the dialog and return the path
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.of(context).pop(snapshot.data!.filePath);
                });
                
                return const AlertDialog(
                  title: Text('Download Complete'),
                  content: Text('Update downloaded successfully!'),
                );
              }
            }
          },
        );
      },
    );
  }
  
  // Show an installation progress/instruction dialog
  static Future<bool> showInstallDialog(BuildContext context, String filePath) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Install Update'),
          content: const Text('The update has been downloaded and is ready to install. The app will close during installation.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final success = await installUpdate(filePath);
                if (!success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to install update. Please try again.')),
                  );
                }
                if (context.mounted) {
                  Navigator.of(context).pop(success);
                }
              },
              child: const Text('Install Now'),
            ),
          ],
        );
      },
    ) ?? false;
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

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {required bool isNightly}) {
    // Different JSON structure for release vs nightly
    if (isNightly) {
      final version = json['version'] as Map<String, dynamic>;
      final apk = json['apk'] as Map<String, dynamic>;
      final git = json['git'] as Map<String, dynamic>;
      
      return UpdateInfo(
        version: version['versionName'] as String,
        buildNumber: version['buildNumber'].toString(),
        buildDate: DateTime.parse(json['buildDate'] as String),
        apkUrl: 'https://github.com/mliem/playtivity/raw/main/nightly/${apk['fileName']}',
        apkFileName: apk['fileName'] as String,
        changelog: git['commitMessage'] as String?,
        isNightly: true,
        fileSizeBytes: apk['sizeBytes'] as int,
      );
    } else {
      final version = json['version'] as Map<String, dynamic>;
      final apkFile = (json['files'] as List).firstWhere(
        (f) => f['type'] == 'APK',
        orElse: () => throw Exception('No APK file found in release info'),
      ) as Map<String, dynamic>;
      
      return UpdateInfo(
        version: version['versionName'] as String,
        buildNumber: version['buildNumber'].toString(),
        buildDate: DateTime.parse(json['timestamp'] as String),
        apkUrl: 'https://github.com/mliem/playtivity/raw/main/releases/${apkFile['name']}',
        apkFileName: apkFile['name'] as String,
        changelog: json['changelog'] as String?,
        isNightly: false,
        fileSizeBytes: apkFile['sizeBytes'] as int,
      );
    }
  }
    factory UpdateInfo.fromGithubJson(Map<String, dynamic> json, {required bool isNightly}) {
    // JSON structure for GitHub releases API
    final version = json['tag_name'] as String;
    
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
    
    // Parse release date
    DateTime buildDate;
    try {
      buildDate = DateTime.parse(json['published_at'] as String);
    } catch (_) {
      buildDate = DateTime.now();
    }
    
    // Extract build number from release name if possible
    String buildNumber = '';
    final name = json['name'] as String? ?? version;
    final buildMatch = RegExp(r'build\s*(\d+)').firstMatch(name);
    if (buildMatch != null) {
      buildNumber = buildMatch.group(1) ?? '';
    }
    
    return UpdateInfo(
      version: version.startsWith('v') ? version.substring(1) : version, // Remove 'v' prefix if present
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
