import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/update_service.dart';
import '../utils/version_utils.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),      body: SafeArea(
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
              ),            ],
          );
        },
        ),
      ),
    );
  } 
    // Build widget for update preferences
  Widget _buildUpdatePreferencesTile(BuildContext context) {
    return FutureBuilder<bool>(
      future: UpdateService.getNightlyBuildPreference(),
      builder: (context, snapshot) {
        final isNightlyEnabled = snapshot.data ?? false;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return ListTile(
              leading: Icon(
                isNightlyEnabled ? Icons.science : Icons.update,
                color: isNightlyEnabled ? Colors.orange : null,
              ),
              title: const Text('Nightly Builds'),
              subtitle: const Text(
                'Get early access to new features (may be unstable)'
              ),
              trailing: Switch(
                value: isNightlyEnabled,
                activeColor: Colors.orange,
                onChanged: (value) async {
                  await UpdateService.setNightlyBuildPreference(value);
                  setState(() {}); // Refresh the widget
                  
                  if (value && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nightly builds enabled. Check for updates to get the latest version.'))
                    );
                  }
                },
              ),
            );
          }
        );
      },
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
  
  // Handle the update check process
  Future<void> _checkForUpdates(BuildContext context) async {
    // Show loading indicator
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Checking for updates...'))
    );
    
    // Check for updates
    final updateResult = await UpdateService.checkForUpdates(forceCheck: true);
    
    // Hide the loading snackbar
    scaffoldMessenger.hideCurrentSnackBar();
    
    if (!context.mounted) return;
    
    // Handle the update result
    if (updateResult.hasUpdate && updateResult.updateInfo != null) {
      // Show the update dialog
      final shouldDownload = await UpdateService.showUpdateDialog(
        context,
        updateResult.updateInfo!,
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
      // Show error
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error: ${updateResult.error}'))
      );
    } else {
      // No updates available
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('You are already on the latest version!'))
      );
    }
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
              onPressed: () async {
                // Close the confirmation dialog first
                Navigator.of(dialogContext).pop();
                
                // Perform logout with the settings screen context, not dialog context
                await _performLogout(context);
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
    print('🚪 Starting logout process...');
    
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    
    // Clear all data
    await authProvider.logout();
    spotifyProvider.clearData();
    
    print('🔍 Checking navigation context...');
    print('   - context.mounted: ${context.mounted}');
    print('   - Current route: ${ModalRoute.of(context)?.settings.name}');
    
    // Check if still in valid context and not already on login screen
    if (context.mounted && ModalRoute.of(context)?.settings.name != '/login') {
      print('✅ Navigating to login screen...');
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    } else {
      print('⚠️ Navigation skipped - context not valid or already on login');
    }
  }
}