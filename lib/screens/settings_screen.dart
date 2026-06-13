import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/update_service.dart';
import '../widgets/update/update_dialogs.dart';
import '../utils/version_utils.dart';
import '../services/app_logger.dart';
import '../utils/theme.dart';
import '../services/url_launcher_service.dart';
import '../models/user.dart';
import '../utils/spotify_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _isNightlyEnabled;

  @override
  void initState() {
    super.initState();
    _loadNightlyPreference();
  }

  Future<void> _loadNightlyPreference() async {
    final isEnabled = await UpdateService.getNightlyBuildPreference();
    if (mounted) {
      setState(() {
        _isNightlyEnabled = isEnabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: SafeArea(
        child: Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            final user = authProvider.currentUser;
            return ListView(
              children: [
                _buildAccountHeader(user),
                _sectionHeader('ACCOUNT'),
                _settingsTile(
                  icon: Icons.public,
                  title: 'Country',
                  subtitle: user?.country,
                ),
                _divider(),
                _sectionHeader('UPDATES'),
                _buildNightlyTile(context),
                _divider(),
                _settingsTile(
                  icon: Icons.system_update,
                  title: 'Check for Updates',
                  subtitle: 'Look for new versions of the app',
                  onTap: () => _checkForUpdates(context),
                ),
                _sectionHeader('ABOUT'),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.hasData
                        ? VersionUtils.formatVersion(snapshot.data!.version)
                        : 'Loading...';
                    return _settingsTile(
                      icon: Icons.info_outline,
                      title: 'Playtivity',
                      subtitle: 'Version $version',
                    );
                  },
                ),
                _divider(),
                _settingsTile(
                  icon: Icons.open_in_browser,
                  title: 'GitHub Releases',
                  subtitle: 'View all releases and download APKs',
                  onTap: () => UrlLauncherService.launchWebUrl(
                    'https://github.com/mliem2k/playtivity/releases',
                  ),
                ),
                _divider(),
                _settingsTile(
                  icon: Icons.music_note,
                  title: 'About',
                  subtitle:
                      'See what your friends are listening to on Spotify',
                ),
                const SizedBox(height: 32),
                _settingsTile(
                  icon: Icons.logout,
                  title: 'Log Out',
                  isDanger: true,
                  onTap: () => _showLogoutDialog(context),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 20, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailingWidget,
    Color? iconColor,
    bool isDanger = false,
  }) {
    final effectiveIconColor =
        isDanger ? AppTheme.errorRed : (iconColor ?? AppTheme.textSecondary);
    final Widget? trailing = trailingWidget ??
        (onTap != null && !isDanger
            ? const Icon(Icons.chevron_right,
                color: AppTheme.textSubdued, size: 20)
            : null);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: effectiveIconColor, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: isDanger ? AppTheme.errorRed : AppTheme.textPrimary,
          fontWeight: isDanger ? FontWeight.w700 : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _divider() =>
      const Divider(height: 1, color: AppTheme.dividerColor, indent: 56);

  Widget _buildAccountHeader(User? user) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.primary, AppTheme.background],
          stops: [0.0, 0.7],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Row(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppTheme.surfaceElevated,
              backgroundImage: user?.imageUrl != null
                  ? CachedNetworkImageProvider(
                      user!.imageUrl!,
                      maxWidth: 240,
                      maxHeight: 240,
                    )
                  : null,
              child: user?.imageUrl == null
                  ? Text(
                      user?.displayName.isNotEmpty == true
                          ? user!.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? 'Unknown User',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  if (user?.email.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      user!.email,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (user != null)
              IconButton(
                icon: const Icon(
                  Icons.open_in_new,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
                tooltip: 'Open Spotify profile',
                onPressed: () => SpotifyLauncher.launchSpotifyUri(
                  'spotify:user:${user.id}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNightlyTile(BuildContext context) {
    if (_isNightlyEnabled == null) {
      return _settingsTile(
        icon: Icons.update,
        title: 'Nightly Builds',
        subtitle: 'Get early access to new features (may be unstable)',
        trailingWidget: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return _settingsTile(
      icon: _isNightlyEnabled! ? Icons.science : Icons.update,
      title: 'Nightly Builds',
      subtitle: 'Get early access to new features (may be unstable)',
      iconColor: _isNightlyEnabled! ? Colors.orange : null,
      trailingWidget: Switch(
        value: _isNightlyEnabled!,
        activeThumbColor: Colors.orange,
        activeTrackColor: Colors.orange.withValues(alpha: 0.4),
        onChanged: (value) async {
          setState(() => _isNightlyEnabled = value);
          await UpdateService.setNightlyBuildPreference(value);
          if (value && context.mounted) {
            _showNightlyEnabledDialog(context);
          }
        },
      ),
    );
  }

  // Show modal dialog when nightly builds are enabled
  void _showNightlyEnabledDialog(BuildContext context) {
    showDialog(
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
                _checkForUpdates(context);
              },
              child: const Text('Check Now'),
            ),
          ],
        );
      },
    );
  }

  // Show custom update dialog with GitHub version information
  Future<bool> _showCustomUpdateDialog(
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
          title: Text(updateInfo.isNightly ? 'Nightly Update Available' : 'Update Available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new ${updateInfo.isNightly ? 'nightly' : 'release'} version is available from GitHub!',
              ),
              const SizedBox(height: 16),
              
              // Version comparison container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Version Comparison',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Current: ${currentVersion.version}+${currentVersion.buildNumber}\n'
                      '${updateInfo.isNightly ? 'Latest Nightly' : 'Latest Release'}: ${updateInfo.version}+${updateInfo.buildNumber}\n'
                      'From: GitHub Repository\n'
                      'Released: ${_formatDate(updateInfo.buildDate)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              
              // Show a brief summary instead of full changelog
              if (updateInfo.changelog != null && updateInfo.changelog!.isNotEmpty) ...[
                const SizedBox(height: 16),
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
                          'This update includes bug fixes and improvements.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              if (updateInfo.isNightly) ...[
                const SizedBox(height: 12),
                Container(
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
                ),
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
  
  // Handle the update check process with modal dialog
  Future<void> _checkForUpdates(BuildContext context) async {
    // Store context.mounted in a local variable
    final isContextMounted = context.mounted;
    
    // Show loading modal
    if (isContextMounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: CircularProgressIndicator()),
                SizedBox(height: 16),
                Center(child: Text('Checking for updates...')),
              ],
            ),
          );
        },
      );
    }
    
    try {
      // Get current version info
      final currentVersion = await UpdateService.getCurrentAppVersion();
      
      // Check for updates
      final updateResult = await UpdateService.checkForUpdates(forceCheck: true);
      
      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      if (!context.mounted) return;
      
      // Handle the update result with modal dialogs
      if (updateResult.hasUpdate && updateResult.updateInfo != null) {
        // Show our custom update dialog with GitHub version information
        final shouldDownload = await _showCustomUpdateDialog(
          context,
          updateResult.updateInfo!,
          currentVersion,
        );
        
        if (shouldDownload && context.mounted) {
          // Show download dialog and get the downloaded file path
          final filePath = await showDownloadDialog(
            context,
            updateResult.updateInfo!,
          );

          if (filePath != null && context.mounted) {
            // Show installation dialog
            await showInstallDialog(context, filePath);
          }
        }
      } else if (updateResult.error != null) {
        // Show error modal with version info
        if (context.mounted) {
          _showUpdateResultDialog(
            context,
            'Update Check Failed',
            'Error: ${updateResult.error}',
            Icons.error,
            Colors.red,
            currentVersion: currentVersion,
          );
        }
      } else {
        // No updates available modal - show current and latest version info
        if (context.mounted) {
          final isNightly = await UpdateService.getNightlyBuildPreference();
          if (!context.mounted) return;
          
          final latestInfo = isNightly 
              ? UpdateService.getLatestNightlyInfo() 
              : UpdateService.getLatestReleaseInfo();
          
          _showUpdateResultDialog(
            context,
            'No Updates Available',
            'You are already on the latest version!',
            Icons.check_circle,
            Colors.green,
            currentVersion: currentVersion,
            latestVersion: latestInfo,
          );
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      // Show error modal
      if (context.mounted) {
        // Get current version for error display
        final currentVersion = await UpdateService.getCurrentAppVersion();
        if (!context.mounted) return;
        
        _showUpdateResultDialog(
          context,
          'Update Check Failed',
          'An error occurred while checking for updates: $e',
          Icons.error,
          Colors.red,
          currentVersion: currentVersion,
        );
      }
    }
  }

  // Helper method to show update result modals
  void _showUpdateResultDialog(
    BuildContext context,
    String title,
    String message,
    IconData icon,
    Color iconColor, {
    AppVersionInfo? currentVersion,
    UpdateInfo? latestVersion,
  }) {
    // Build version information text
    String versionInfo = '';
    if (currentVersion != null) {
      versionInfo += 'Current Version: ${currentVersion.version}+${currentVersion.buildNumber}\n';
    }
    if (latestVersion != null) {
      final versionType = latestVersion.isNightly ? 'Latest Nightly' : 'Latest Release';
      versionInfo += '$versionType: ${latestVersion.version}+${latestVersion.buildNumber}\n';
      versionInfo += 'From: GitHub Repository\n';
      versionInfo += 'Released: ${_formatDate(latestVersion.buildDate)}';
    } else if (currentVersion != null) {
      // If no latest version info available, show that we checked GitHub
      versionInfo += 'Checked: GitHub Repository\n';
      versionInfo += 'No newer version found';
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: Icon(
            icon,
            color: iconColor,
            size: 32,
          ),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (versionInfo.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
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
                        versionInfo,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
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

  // Helper method to format date
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout from your Spotify account?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                // Store context before async gap
                final settingsContext = context;
                
                // Close the confirmation dialog first
                Navigator.of(dialogContext).pop();
                
                // Perform logout with the stored context
                _performLogout(settingsContext);
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }  
  
  Future<void> _performLogout(BuildContext context) async {
    AppLogger.auth('Starting logout process...');
    
    // Store route name at the start, before any async operations
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    
    // Clear all data
    await authProvider.logout();
    spotifyProvider.clearData();
    
    AppLogger.auth('Checking navigation context...');
    AppLogger.auth('   - context.mounted: ${context.mounted}');
    AppLogger.auth('   - Current route: $currentRoute');
    
    // Check if still in valid context and not already on login screen
    if (context.mounted && currentRoute != '/login') {
      AppLogger.auth('Navigating to login screen...');
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    } else {
      AppLogger.auth('Navigation skipped - context not valid or already on login');
    }
  }
}