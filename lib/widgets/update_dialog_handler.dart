import 'package:flutter/material.dart';
import '../utils/update_launcher.dart';

class UpdateDialogHandler extends StatefulWidget {
  final Widget child;
  final Function(BuildContext) onUpdateAvailable;

  const UpdateDialogHandler({
    super.key,
    required this.child,
    required this.onUpdateAvailable,
  });

  @override
  State<UpdateDialogHandler> createState() => _UpdateDialogHandlerState();
}

class _UpdateDialogHandlerState extends State<UpdateDialogHandler> {
  Future<bool> showInstallPermissionDialog() async {
    if (!mounted) return false;
    
    return await showDialog<bool>(
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
                color: Colors.blue.withAlpha(26),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.withAlpha(77)),
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
  }

  Future<void> showPermissionInstructionsDialog() async {
    if (!mounted) return;
    
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
                color: Colors.orange.withAlpha(26),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.withAlpha(77)),
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

  Future<void> showInstallationLoadingDialog() async {
    if (!mounted) return;
    
    await showDialog(
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
  }

  Future<void> showInstallationFailedDialog(bool hasPermission) async {
    if (!mounted) return;
    
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
  }

  void showInstallationStartedSnackBar() {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Installation started. Please follow the system prompts.'),
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
} 