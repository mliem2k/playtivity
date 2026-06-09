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
    return Scaffold(
      backgroundColor: AppTheme.loginBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update, color: AppTheme.textSecondary),
            onPressed: () => _checkForUpdates(context),
            tooltip: 'Check for Updates',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              // Logo
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/images/playtivity_logo.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Playtivity',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'See what your friends are listening to',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                ),
              ),
              const Spacer(flex: 3),
              // Login button
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  if (auth.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    );
                  }
                  return ElevatedButton.icon(
                    onPressed: () => _handleLogin(context),
                    icon: Image.asset(
                      'assets/images/playtivity_logo_button_icon.png',
                      width: 20,
                      height: 20,
                      color: AppTheme.onPrimary,
                    ),
                    label: const Text('Log in with Spotify'),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Playtivity uses your Spotify account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSubdued,
                  fontSize: 12,
                ),
              ),
              const Spacer(flex: 1),
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

  Future<void> _checkForUpdates(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: CircularProgressIndicator()),
            SizedBox(height: 16),
            Center(child: Text('Checking for updates...')),
          ],
        ),
      ),
    );
    try {
      final currentVersion = await UpdateService.getCurrentAppVersion();
      final result = await UpdateService.checkForUpdates(forceCheck: true);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (result.hasUpdate && result.updateInfo != null && context.mounted) {
        final shouldUpdate = await _showUpdateDialog(
          context,
          result.updateInfo!,
          currentVersion,
        );
        if (shouldUpdate == true && context.mounted) {
          final filePath = await showDownloadDialog(context, result.updateInfo!);
          if (filePath != null && context.mounted) {
            final shouldInstall = await showInstallDialog(context, filePath);
            if (shouldInstall == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Installing update... The app will restart.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Download cancelled or failed.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You\'re running the latest version!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
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
