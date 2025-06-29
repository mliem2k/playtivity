import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/update_service.dart';
import '../utils/version_utils.dart';
import '../services/app_logger.dart';

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
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Consumer2<ThemeProvider, AuthProvider>(
          builder: (context, themeProvider, authProvider, child) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Appearance Section
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Appearance',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ListTile(
                        leading: Icon(
                          themeProvider.isDarkMode 
                              ? Icons.dark_mode 
                              : Icons.light_mode,
                        ),
                        title: const Text('Dark Mode'),
                        subtitle: Text(
                          themeProvider.isDarkMode ? 'Enabled' : 'Disabled',
                        ),
                        trailing: Switch(
                          value: themeProvider.isDarkMode,
                          onChanged: (value) {
                            themeProvider.toggleTheme();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Account Section
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Account',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (authProvider.currentUser != null) ...[
                        ListTile(
                          leading: const Icon(Icons.person),
                          title: const Text('Display Name'),
                          subtitle: Text(authProvider.currentUser!.displayName),
                        ),
                        ListTile(
                          leading: const Icon(Icons.email),
                          title: const Text('Email'),
                          subtitle: Text(authProvider.currentUser!.email),
                        ),
                        ListTile(
                          leading: const Icon(Icons.public),
                          title: const Text('Country'),
                          subtitle: Text(authProvider.currentUser!.country),
                        ),
                      ],
                      ListTile(
                        leading: const Icon(
                          Icons.logout,
                          color: Colors.red,
                        ),
                        title: const Text(
                          'Logout',
                          style: TextStyle(color: Colors.red),
                        ),
                        subtitle: const Text('Sign out from your Spotify account'),
                        onTap: () => _showLogoutDialog(context),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                // Updates Section
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Updates',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _buildUpdatePreferencesTile(context),
                      _buildCheckForUpdatesTile(context),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                
                // About Section
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'About',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snapshot) {
                          final version = snapshot.hasData
                              ? VersionUtils.formatVersion(snapshot.data!.version)
                              : 'Loading...';
                          return ListTile(
                            leading: Image.asset(
                              'assets/images/playtivity_logo_small_icon.png',
                              width: 24,
                              height: 24,
                            ),
                            title: const Text('Playtivity'),
                            subtitle: Text('Version $version'),
                          );
                        },
                      ),
                      const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('About'),
                        subtitle: Text('See what your friends are listening to on Spotify'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Build widget for update preferences
  Widget _buildUpdatePreferencesTile(BuildContext context) {
    // Show loading if preference not loaded yet
    if (_isNightlyEnabled == null) {
      return const ListTile(
        leading: Icon(Icons.update),
        title: Text('Nightly Builds'),
        subtitle: Text('Get early access to new features (may be unstable)'),
        trailing: CircularProgressIndicator(),
      );
    }

    return ListTile(
      leading: Icon(
        _isNightlyEnabled! ? Icons.science : Icons.update,
        color: _isNightlyEnabled! ? Colors.orange : null,
      ),
      title: const Text('Nightly Builds'),
      subtitle: const Text(
        'Get early access to new features (may be unstable)'
      ),
      trailing: Switch(
        value: _isNightlyEnabled!,
        activeColor: Colors.orange,
        onChanged: (value) async {
          // Update local state immediately for instant UI feedback
          setState(() {
            _isNightlyEnabled = value;
          });
          
          // Save to preferences
          await UpdateService.setNightlyBuildPreference(value);
          
          // Show modal dialog instead of toast if nightly enabled
          if (value && context.mounted) {
            _showNightlyEnabledDialog(context);
          }
        },
      ),
    );
  }
  
  // Build widget for checking updates
  Widget _buildCheckForUpdatesTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.system_update),
      title: const Text('Check for Updates'),
      subtitle: const Text('Look for new versions of the app'),
      onTap: () => _checkForUpdates(context),
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
          final filePath = await UpdateService.showDownloadDialog(
            context,
            updateResult.updateInfo!,
          );
          
          if (filePath != null && context.mounted) {
            // Show installation dialog
            await UpdateService.showInstallDialog(context, filePath);
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