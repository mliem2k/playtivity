import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateModal {
  /// Show a loading dialog while checking for updates
  static Future<void> _showLoadingDialog(BuildContext context, String message) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        );
      },
    );
  }

  /// Hide the currently shown dialog
  static void _hideDialog(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  /// Show update available dialog
  static Future<bool> _showUpdateAvailableDialog(
    BuildContext context,
    UpdateInfo updateInfo,
    AppVersionInfo currentVersion,
  ) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: Icon(
            updateInfo.isNightly ? Icons.science : Icons.system_update,
            color: updateInfo.isNightly ? Colors.orange : Colors.blue,
            size: 32,
          ),
          title: Text(
            updateInfo.isNightly ? 'Nightly Update Available' : 'Update Available'
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new ${updateInfo.isNightly ? 'nightly' : 'release'} version is available!',
              ),
              const SizedBox(height: 16),
              
              // Version comparison
              _buildVersionComparisonCard(context, currentVersion, updateInfo),
              
              // Changelog preview if available
              if (updateInfo.changelog != null && updateInfo.changelog!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildChangelogPreview(context, updateInfo.changelog!),
              ],
              
              // Warning for nightly builds
              if (updateInfo.isNightly) ...[
                const SizedBox(height: 12),
                _buildNightlyWarning(context),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Update Now'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  /// Show no updates available dialog
  static Future<void> _showNoUpdatesDialog(
    BuildContext context,
    AppVersionInfo currentVersion,
    {String? message}
  ) async {
    final isNightly = await UpdateService.getNightlyBuildPreference();
    final latestInfo = isNightly
        ? UpdateService.getLatestNightlyInfo()
        : UpdateService.getLatestReleaseInfo();

    if (!context.mounted) return;
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 32,
          ),
          title: const Text('No Updates Available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message ?? 'You are already on the latest version!'),
              const SizedBox(height: 16),
              _buildVersionComparisonCard(
                context, 
                currentVersion, 
                latestInfo,
                showAsLatest: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Show error dialog
  static Future<void> _showErrorDialog(
    BuildContext context,
    String error,
    AppVersionInfo? currentVersion,
  ) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.error,
            color: Colors.red,
            size: 32,
          ),
          title: const Text('Update Check Failed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('An error occurred while checking for updates:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Text(
                  error,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              if (currentVersion != null) ...[
                const SizedBox(height: 16),
                _buildVersionInfoCard(context, currentVersion, 'Current Version'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Build version comparison card
  static Widget _buildVersionComparisonCard(
    BuildContext context,
    AppVersionInfo currentVersion,
    UpdateInfo? latestVersion, {
    bool showAsLatest = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version Information',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _buildVersionText(currentVersion, latestVersion, showAsLatest),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  /// Build version info card for single version
  static Widget _buildVersionInfoCard(
    BuildContext context,
    AppVersionInfo version,
    String title,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${version.version}+${version.buildNumber}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  /// Build changelog preview
  static Widget _buildChangelogPreview(BuildContext context, String changelog) {
    // Extract first few lines or first 150 characters
    final preview = changelog.length > 150 
        ? '${changelog.substring(0, 150)}...'
        : changelog;
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What\'s New',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  preview,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build nightly warning
  static Widget _buildNightlyWarning(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nightly builds may contain bugs or incomplete features.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.orange[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build version text for comparison
  static String _buildVersionText(
    AppVersionInfo currentVersion,
    UpdateInfo? latestVersion,
    bool showAsLatest,
  ) {
    String text = 'Current: ${currentVersion.version}+${currentVersion.buildNumber}\n';
    
    if (latestVersion != null) {
      final versionType = showAsLatest 
          ? 'Latest Available'
          : (latestVersion.isNightly ? 'Latest Nightly' : 'Latest Release');
      text += '$versionType: ${latestVersion.version}+${latestVersion.buildNumber}\n';
      text += 'From: GitHub Repository\n';
      text += 'Released: ${_formatDate(latestVersion.buildDate)}';
    } else {
      text += 'Checked: GitHub Repository\n';
      text += 'No newer version found';
    }
    
    return text;
  }

  /// Format date for display
  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Main method to check for updates with modal workflow
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool forceCheck = true,
    String? loadingMessage,
  }) async {
    try {
      // Show loading dialog
      await _showLoadingDialog(
        context, 
        loadingMessage ?? 'Checking for updates...'
      );

      // Get current version info
      final currentVersion = await UpdateService.getCurrentAppVersion();
      
      // Check for updates
      final updateResult = await UpdateService.checkForUpdates(
        forceCheck: forceCheck
      );
      
      // Hide loading dialog
      if (context.mounted) {
        _hideDialog(context);
      }
      
      if (!context.mounted) return;
      
      // Handle results
      if (updateResult.hasUpdate && updateResult.updateInfo != null) {
        // Update available
        final shouldUpdate = await _showUpdateAvailableDialog(
          context,
          updateResult.updateInfo!,
          currentVersion,
        );
        
        if (shouldUpdate && context.mounted) {
          // Start download process
          await _handleDownloadProcess(context, updateResult.updateInfo!);
        }
      } else if (updateResult.error != null) {
        // Error occurred
        if (!context.mounted) return;
        await _showErrorDialog(
          context,
          updateResult.error!,
          currentVersion,
        );
      } else {
        // No updates available
        if (!context.mounted) return;
        await _showNoUpdatesDialog(context, currentVersion);
      }
    } catch (e) {
      // Hide loading dialog if still showing
      if (context.mounted) {
        _hideDialog(context);
      }
      
      // Show error
      if (context.mounted) {
        AppVersionInfo? currentVersion;
        try {
          currentVersion = await UpdateService.getCurrentAppVersion();
        } catch (_) {
          // If we can't get current version, pass null
        }

        if (!context.mounted) return;
        await _showErrorDialog(
          context,
          e.toString(),
          currentVersion,
        );
      }
    }
  }

  /// Handle the download and installation process
  static Future<void> _handleDownloadProcess(
    BuildContext context,
    UpdateInfo updateInfo,
  ) async {
    try {
      // Start download with progress dialog
      final downloadedFilePath = await UpdateService.showDownloadDialog(
        context,
        updateInfo,
      );
      
      if (downloadedFilePath != null && context.mounted) {
        // Show installation dialog
        final shouldInstall = await UpdateService.showInstallDialog(
          context,
          downloadedFilePath,
        );
        
        if (shouldInstall && context.mounted) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Installing update... The app will restart.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (context.mounted) {
        // Download was cancelled or failed
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download cancelled or failed.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show nightly builds enabled dialog
  static Future<void> showNightlyEnabledDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.science,
            color: Colors.orange,
            size: 32,
          ),
          title: const Text('Nightly Builds Enabled'),
          content: const Text(
            'You\'ve enabled nightly builds! You can now check for updates to get the latest development version with new features.\n\n'
            'Note: Nightly builds may be unstable and contain bugs.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                checkForUpdates(context);
              },
              child: const Text('Check Now'),
            ),
          ],
        );
      },
    );
  }
}