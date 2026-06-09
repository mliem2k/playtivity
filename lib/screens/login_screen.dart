import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';
import '../widgets/spotify_webview_login.dart';
import '../services/update_service.dart';
import '../widgets/update/update_dialogs.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update),
            onPressed: () => _checkForUpdates(context),
            tooltip: 'Check for Updates',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Playtivity Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: theme.primaryColor.withAlpha(64),
                      blurRadius: 15,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/images/playtivity_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // App Title
              Text(
                'Playtivity',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Subtitle
              Text(
                'See what your friends are listening to',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.getSecondaryTextColor(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                ),
              ),
              
              const SizedBox(height: 80),
              
              // Login Button
              Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  return ElevatedButton.icon(
                    onPressed: authProvider.isLoading ? null : () => _handleLogin(context),
                    icon: authProvider.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : SizedBox(
                            width: 20,
                            height: 20,
                            child: Image.asset(
                              'assets/images/playtivity_logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                    label: Text(
                      authProvider.isLoading ? 'Connecting...' : 'Login with Spotify',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: isDark ? 0 : 3,
                      shadowColor: isDark ? Colors.transparent : theme.primaryColor.withAlpha(77),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // Info Text
              Text(
                'You\'ll be redirected to Spotify to authorize this app',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.getSecondaryTextColor(context),
                  fontSize: 14,
                ),
              ),
              
              const Spacer(),
              
              // Footer
              Text(
                'Made with ❤️ for music lovers',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.getTertiaryTextColor(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin(BuildContext context) async {
    if (!context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SpotifyWebViewLogin(
          onAuthComplete: (bearerToken, headers) async {
            final authProvider = context.read<AuthProvider>();
            await authProvider.loginComplete(bearerToken, headers);
          },
          onCancel: () => Navigator.of(context).pop(false),
        ),
      ),
    );
  }

  // Handle the update check process
  Future<void> _checkForUpdates(BuildContext context) async {
    // Show loading modal
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
    
    try {
      // Get current version info
      final currentVersion = await UpdateService.getCurrentAppVersion();
      
      // Check for updates
      final updateResult = await UpdateService.checkForUpdates(forceCheck: true);
      
      // Hide loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      if (updateResult.hasUpdate && updateResult.updateInfo != null) {
        // Show update available dialog
        if (!context.mounted) return;
        final shouldUpdate = await _showUpdateDialog(
          context,
          updateResult.updateInfo!,
          currentVersion,
        );
        
        if (shouldUpdate && context.mounted) {
          // Start download with progress dialog
          final downloadedFilePath = await showDownloadDialog(
            context,
            updateResult.updateInfo!,
          );

          if (downloadedFilePath != null && context.mounted) {
            // Show installation dialog
            final shouldInstall = await showInstallDialog(
              context,
              downloadedFilePath,
            );
            
            if (shouldInstall) {
              // Installation started, show final message
              if (!context.mounted) return;
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
        }
      } else {
        // No update available
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You\'re running the latest version!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      // Hide loading dialog and show error
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking for updates: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Show update dialog
  Future<bool> _showUpdateDialog(
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
                'A new ${updateInfo.isNightly ? 'nightly' : 'release'} version is available!',
              ),
              const SizedBox(height: 16),
              
              // Version comparison
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
                      '${updateInfo.isNightly ? 'Latest Nightly' : 'Latest Release'}: ${updateInfo.version}+${updateInfo.buildNumber}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              
              if (updateInfo.isNightly) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(26),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.withAlpha(77)),
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
} 