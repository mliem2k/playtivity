import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/update_service.dart';
import '../../utils/update_launcher.dart';

/// Shows the download progress dialog and returns the downloaded file path,
/// or null if the download failed or was cancelled.
Future<String?> showDownloadDialog(
  BuildContext context,
  UpdateInfo updateInfo,
) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DownloadProgressDialog(updateInfo: updateInfo),
  );
}

/// Shows the install-confirmation dialog and returns true if installation
/// was initiated successfully.
Future<bool> showInstallDialog(
  BuildContext context,
  String filePath,
) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _InstallDialog(filePath: filePath),
      ) ??
      false;
}

// ---------------------------------------------------------------------------
// Download progress dialog
// ---------------------------------------------------------------------------

class _DownloadProgressDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  const _DownloadProgressDialog({required this.updateInfo});

  @override
  _DownloadProgressDialogState createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  late Future<UpdateDownloadResult> _downloadFuture;
  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>();
  DownloadProgress? _currentProgress;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  void _startDownload() {
    _downloadFuture = UpdateService.downloadUpdate(
      widget.updateInfo,
      onProgress: (p) {
        if (!_progressController.isClosed) _progressController.add(p);
      },
    );
    _downloadFuture.then((result) {
      if (mounted) {
        Navigator.of(context).pop(result.success ? result.filePath : null);
      }
    }).catchError((_) {
      if (mounted) Navigator.of(context).pop(null);
    });
  }

  @override
  void dispose() {
    _progressController.close();
    super.dispose();
  }

  String _formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatSpeed(double bps) {
    final mbps = (bps * 8) / 1000000;
    return '${mbps.toStringAsFixed(1)} Mbps';
  }

  String _formatTime(double s) {
    if (s < 60) return '${s.toStringAsFixed(0)}s';
    if (s < 3600) {
      return '${(s / 60).toStringAsFixed(0)}m ${(s % 60).toStringAsFixed(0)}s';
    }
    return '${(s / 3600).toStringAsFixed(0)}h ${((s % 3600) / 60).toStringAsFixed(0)}m';
  }

  @override
  Widget build(BuildContext context) {
    final isNightly = widget.updateInfo.isNightly;
    final accentColor = isNightly ? Colors.orange : Colors.blue;

    return AlertDialog(
      title: Row(
        children: [
          Icon(isNightly ? Icons.science : Icons.system_update, color: accentColor),
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
            Text('Version: ${widget.updateInfo.version}',
                style: Theme.of(context).textTheme.bodyMedium),
            Text('File: ${widget.updateInfo.apkFileName}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            StreamBuilder<DownloadProgress>(
              stream: _progressController.stream,
              builder: (context, snapshot) {
                if (snapshot.hasData) _currentProgress = snapshot.data!;
                if (_currentProgress == null) {
                  return const Column(children: [
                    Center(child: CircularProgressIndicator()),
                    SizedBox(height: 16),
                    Center(child: Text('Initializing download...')),
                  ]);
                }
                final p = _currentProgress!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: p.progress,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${(p.progress * 100).toStringAsFixed(1)}%',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${_formatBytes(p.downloadedBytes)} / ${_formatBytes(p.totalBytes)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.speed, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('Speed: ${_formatSpeed(p.speedBytesPerSecond)}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    if (p.estimatedRemainingSeconds > 0) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.schedule, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('Time remaining: ${_formatTime(p.estimatedRemainingSeconds)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                Icon(Icons.info_outline,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The update will be installed automatically when download completes.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        FutureBuilder<UpdateDownloadResult>(
          future: _downloadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done &&
                (snapshot.hasError ||
                    (snapshot.data != null && !snapshot.data!.success))) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Close')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                      onPressed: () => setState(_startDownload),
                      child: const Text('Retry')),
                ],
              );
            }
            return const TextButton(onPressed: null, child: Text('Cancel'));
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Install dialog
// ---------------------------------------------------------------------------

class _InstallDialog extends StatelessWidget {
  final String filePath;
  const _InstallDialog({required this.filePath});

  Future<void> _install(BuildContext context) async {
    final canInstall = await UpdateLauncher.canInstallPackages();
    if (!context.mounted) return;

    if (!canInstall) {
      final grant = await showDialog<bool>(
            context: context,
            builder: (_) => const _PermissionDialog(),
          ) ??
          false;
      if (!grant) {
        if (context.mounted) Navigator.of(context).pop(false);
        return;
      }
      await UpdateLauncher.requestInstallPermission();
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => const _PermissionInstructionsDialog(),
        );
      }
      if (context.mounted) Navigator.of(context).pop(false);
      return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: CircularProgressIndicator()),
            SizedBox(height: 16),
            Text('Starting installation...'),
          ]),
        ),
      );
    }

    try {
      final success = await UpdateService.installUpdate(filePath);
      if (context.mounted) Navigator.of(context).pop();
      if (!success && context.mounted) {
        final hasPermission = await UpdateLauncher.canInstallPackages();
        if (context.mounted) {
          await showDialog(
            context: context,
            builder: (_) => _InstallFailedDialog(hasPermission: hasPermission),
          );
        }
      }
      if (context.mounted) Navigator.of(context).pop(success);
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Installation Error'),
            content: Text('An unexpected error occurred:\n\n$e'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'))
            ],
          ),
        );
      }
      if (context.mounted) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install Update'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('The update has been downloaded and is ready to install.'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.info, color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You may need to allow "Unknown sources" in your device settings to install this update.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => _install(context), child: const Text('Install Now')),
      ],
    );
  }
}

class _PermissionDialog extends StatelessWidget {
  const _PermissionDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Permission Required'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('To install updates, Playtivity needs permission to install applications.'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.info, color: Colors.blue, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You will be taken to system settings to enable "Allow from this source" for Playtivity.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Grant Permission')),
      ],
    );
  }
}

class _PermissionInstructionsDialog extends StatelessWidget {
  const _PermissionInstructionsDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Complete Permission Setup'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('After enabling the permission:'),
        const SizedBox(height: 8),
        const Text('1. Tap the back button to return to Playtivity'),
        const Text('2. Try installing the update again'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.info, color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This permission is only used for app updates and is completely safe.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    );
  }
}

class _InstallFailedDialog extends StatelessWidget {
  final bool hasPermission;
  const _InstallFailedDialog({required this.hasPermission});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Installation Failed'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      ]),
      actions: [
        if (!hasPermission)
          TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await UpdateLauncher.requestInstallPermission();
              },
              child: const Text('Open Settings')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    );
  }
}
