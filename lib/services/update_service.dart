import 'dart:convert';
import 'dart:io';
import 'dart:async';
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
  static const String _baseUrl = 'https://raw.githubusercontent.com/mliem2k/playtivity/main';
  static const String _githubReleasesApi = 'https://api.github.com/repos/mliem2k/playtivity/releases';
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
      
      // Find the latest stable release (exclude nightly releases)
      Map<String, dynamic>? latestReleaseJson;
      for (final releaseJson in releasesJson) {
        final tagName = releaseJson['tag_name'] as String? ?? '';
        // Skip nightly releases - we only want stable releases here
        if (!tagName.startsWith('nightly-')) {
          latestReleaseJson = releaseJson as Map<String, dynamic>;
          break; // First non-nightly release is the latest stable
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
      
      // Compare versions
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
    // Check for nightly updates
  static Future<UpdateCheckResult> _checkNightlyUpdates(AppVersionInfo currentVersion) async {
    try {
      // Fetch nightly releases from GitHub API
      final response = await http.get(Uri.parse(_githubReleasesApi));
      
      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate: false,
          isNightly: true,
          updateInfo: null,
          error: 'Failed to fetch nightly releases: HTTP ${response.statusCode}',
        );
      }

      final List<dynamic> releasesJson = json.decode(response.body);
      
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
    while (currentBaseParts.length < 3) currentBaseParts.add('0');
    while (releaseBaseParts.length < 3) releaseBaseParts.add('0');
    
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
    AppLogger.info('  New nightly build date: ${nightlyInfo.buildDate}');
    
    // If current version is not a nightly, always offer nightly update
    if (!currentVersion.contains('nightly')) {
      AppLogger.info('Current version is not nightly, offering nightly update');
      return true;
    }
    
    // If both are nightly, compare build dates
    final shouldUpdate = VersionUtils.isNewerNightly(
      currentVersion: currentVersion,
      newVersion: nightlyInfo.version,
      newBuildTime: nightlyInfo.buildDate,
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
  
  // Show a download progress dialog with enhanced UI
  static Future<String?> showDownloadDialog(BuildContext context, UpdateInfo updateInfo) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _DownloadProgressDialog(updateInfo: updateInfo);
      },
    );
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
  
  // Show an installation progress/instruction dialog
  static Future<bool> showInstallDialog(BuildContext context, String filePath) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Install Update'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The update has been downloaded and is ready to install.'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You may need to allow "Unknown sources" in your device settings to install this update.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                // First, check if we have permission to install packages
                final canInstall = await UpdateLauncher.canInstallPackages();
                
                if (!canInstall && context.mounted) {
                  // Show permission request dialog
                  final shouldRequestPermission = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Permission Required'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('To install updates, Playtivity needs permission to install applications.'),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info, color: Colors.blue, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'You will be taken to system settings where you can enable "Allow from this source" for Playtivity.',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Grant Permission'),
                        ),
                      ],
                    ),
                  ) ?? false;
                  
                  if (!shouldRequestPermission) {
                    Navigator.of(context).pop(false);
                    return;
                  }
                  
                  // Request permission
                  await UpdateLauncher.requestInstallPermission();
                  
                  // Show instruction dialog
                  if (context.mounted) {
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Complete Permission Setup'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('After enabling the permission:'),
                            const SizedBox(height: 8),
                            const Text('1. Tap the back button to return to Playtivity'),
                            const Text('2. Try installing the update again'),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info, color: Colors.orange, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'This permission is only used for app updates and is completely safe.',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  if (context.mounted) {
                    Navigator.of(context).pop(false);
                  }
                  return;
                }
                
                // Show loading state
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const AlertDialog(
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(child: CircularProgressIndicator()),
                        SizedBox(height: 16),
                        Text('Starting installation...'),
                      ],
                    ),
                  ),
                );
                
                try {
                  final success = await installUpdate(filePath);
                  
                  // Close loading dialog
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  
                  if (!success && context.mounted) {
                    // Check permission again to provide better error message
                    final hasPermission = await UpdateLauncher.canInstallPackages();
                    
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Installation Failed'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(hasPermission 
                              ? 'Failed to start APK installation. This could be due to:'
                              : 'Installation permission is not granted.'),
                            const SizedBox(height: 8),
                            if (hasPermission) ...[
                              const Text('• File permissions issue'),
                              const Text('• Corrupted download file'),
                              const Text('• Device storage space'),
                              const SizedBox(height: 12),
                              const Text('Please try:'),
                              const Text('1. Re-download the update'),
                              const Text('2. Check device storage space'),
                              const Text('3. Restart the app and try again'),
                            ] else ...[
                              const Text('Please enable "Allow from this source" for Playtivity in:'),
                              const Text('Settings > Apps > Special access > Install unknown apps'),
                            ],
                          ],
                        ),
                        actions: [
                          if (!hasPermission)
                            TextButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await UpdateLauncher.requestInstallPermission();
                              },
                              child: const Text('Open Settings'),
                            ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  } else {
                    // Installation started successfully
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Installation started! Follow the on-screen prompts.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  
                  if (context.mounted) {
                    Navigator.of(context).pop(success);
                  }
                } catch (e) {
                  // Close loading dialog
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  
                  // Show error dialog
                  if (context.mounted) {
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Installation Error'),
                        content: Text('An unexpected error occurred:\n\n$e'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    
                    Navigator.of(context).pop(false);
                  }
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
    final tagName = json['tag_name'] as String;
    final releaseName = json['name'] as String? ?? tagName;
    final body = json['body'] as String? ?? '';
    
    AppLogger.info('Parsing GitHub release: tag=$tagName, name=$releaseName, isNightly=$isNightly');
    AppLogger.info('Release body preview: ${body.length > 100 ? body.substring(0, 100) + '...' : body}');
    
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
    
    AppLogger.info('Found APK asset: $apkFileName (${fileSizeBytes} bytes)');
    
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
      
      // Look for version information in the release body with improved regex patterns
      RegExp versionRegex = RegExp(r'\*\*Version\*\*:\s*`?([^`\s\n]+)`?', caseSensitive: false);
      RegExpMatch? versionMatch = versionRegex.firstMatch(body);
      
      // Try alternative patterns if the first one doesn't match
      if (versionMatch == null) {
        versionRegex = RegExp(r'Version[:\s]*`?([^`\s\n]+)`?', caseSensitive: false);
        versionMatch = versionRegex.firstMatch(body);
      }
      
      if (versionMatch != null) {
        version = versionMatch.group(1)!.trim();
        AppLogger.info('Parsed nightly version from release body: $version');
        
        // Extract build number from version string (after +)
        final buildMatch = RegExp(r'\+(\d+)').firstMatch(version);
        if (buildMatch != null) {
          buildNumber = buildMatch.group(1) ?? '';
          AppLogger.info('Extracted build number: $buildNumber');
        }
      } else {
        // Fallback: use tag name as version
        version = tagName;
        AppLogger.info('Using tag name as version fallback: $version');
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

class _DownloadProgressDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const _DownloadProgressDialog({Key? key, required this.updateInfo}) : super(key: key);

  @override  
  _DownloadProgressDialogState createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  late Future<UpdateDownloadResult> _downloadFuture;
  final StreamController<DownloadProgress> _progressController = StreamController<DownloadProgress>();
  DownloadProgress? _currentProgress;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  void _startDownload() {
    _downloadFuture = UpdateService.downloadUpdate(
      widget.updateInfo,
      onProgress: (progress) {
        if (!_progressController.isClosed) {
          _progressController.add(progress);
        }
      },
    );
    
    // Handle download completion
    _downloadFuture.then((result) {
      if (mounted) {
        if (result.success) {
          Navigator.of(context).pop(result.filePath);
        } else {
          Navigator.of(context).pop(null);
        }
      }
    }).catchError((error) {
      if (mounted) {
        Navigator.of(context).pop(null);
      }
    });
  }

  @override
  void dispose() {
    _progressController.close();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatSpeed(double bytesPerSecond) {
    // Convert bytes/s to megabits/s (1 byte = 8 bits, then divide by 1,000,000 for mega)
    final megabitsPerSecond = (bytesPerSecond * 8) / 1000000;
    return '${megabitsPerSecond.toStringAsFixed(1)} Mbps';
  }

  String _formatTime(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(0)}m ${(seconds % 60).toStringAsFixed(0)}s';
    return '${(seconds / 3600).toStringAsFixed(0)}h ${((seconds % 3600) / 60).toStringAsFixed(0)}m';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.updateInfo.isNightly ? Icons.science : Icons.system_update,
            color: widget.updateInfo.isNightly ? Colors.orange : Colors.blue,
          ),
          const SizedBox(width: 8),
          const Text('Downloading Update'),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version: ${widget.updateInfo.version}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'File: ${widget.updateInfo.apkFileName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            
            StreamBuilder<DownloadProgress>(
              stream: _progressController.stream,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  _currentProgress = snapshot.data!;
                }
                
                if (_currentProgress == null) {
                  return Column(
                    children: [
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 16),
                      const Center(child: Text('Initializing download...')),
                    ],
                  );
                }
                
                final progress = _currentProgress!;
                final progressPercent = (progress.progress * 100).toStringAsFixed(1);
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progress bar
                    LinearProgressIndicator(
                      value: progress.progress,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.updateInfo.isNightly ? Colors.orange : Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Progress percentage and size
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$progressPercent%',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_formatBytes(progress.downloadedBytes)} / ${_formatBytes(progress.totalBytes)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Download speed
                    Row(
                      children: [
                        const Icon(Icons.speed, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          'Speed: ${_formatSpeed(progress.speedBytesPerSecond)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    
                    // Estimated time remaining
                    if (progress.estimatedRemainingSeconds > 0) ...[
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            'Time remaining: ${_formatTime(progress.estimatedRemainingSeconds)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
            
            const SizedBox(height: 16),
            
            // Download info
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The update will be installed automatically when download completes.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FutureBuilder<UpdateDownloadResult>(
          future: _downloadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              if (snapshot.hasError || (snapshot.data != null && !snapshot.data!.success)) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _startDownload();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }
            }
            
            return TextButton(
              onPressed: null, // Disable cancel during download for now
              child: const Text('Cancel'),
            );
          },
        ),
      ],
    );
  }
}
