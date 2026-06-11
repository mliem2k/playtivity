import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/update_service.dart';
import '../../services/app_logger.dart';
import 'update_dialogs.dart';

class UpdateCheckerWrapper extends StatefulWidget {
  final Widget child;

  const UpdateCheckerWrapper({super.key, required this.child});

  @override
  State<UpdateCheckerWrapper> createState() => _UpdateCheckerWrapperState();
}

class _UpdateCheckerWrapperState extends State<UpdateCheckerWrapper> {
  UpdateInfo? _updateInfo;
  String? _downloadedFilePath;
  bool _hasCheckedForUpdates = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    try {
      if (_hasCheckedForUpdates) return;
      _hasCheckedForUpdates = true;

      final autoDownload = await UpdateService.getAutoDownloadPreference();
      // Use forceCheck for nightly users: the 24-hour default throttle is too
      // long — a new nightly could land within hours and the banner would never
      // appear until the user manually checks. Stable users keep the throttle so
      // we don't hit the GitHub API on every launch.
      final isNightly = await UpdateService.getNightlyBuildPreference();
      final updateResult = await UpdateService.checkForUpdates(forceCheck: isNightly);

      if (updateResult.hasUpdate && updateResult.updateInfo != null) {
        AppLogger.info('Update available: ${updateResult.updateInfo?.version}');
        setState(() {
          _updateInfo = updateResult.updateInfo;
        });
        if (autoDownload && mounted) {
          AppLogger.info('Auto-download enabled, starting download...');
          _handleUpdateDownload();
        }
      }
    } catch (e) {
      AppLogger.error('Error checking for updates', e);
    }
  }

  Future<void> _handleUpdateDownload() async {
    if (_updateInfo == null || !mounted) return;

    // Reuse a previously-downloaded file if it still exists on disk.
    String? filePath = _downloadedFilePath;
    if (filePath != null && !await File(filePath).exists()) {
      AppLogger.info('Cached APK no longer exists, will re-download');
      filePath = null;
      setState(() => _downloadedFilePath = null);
    }

    if (filePath == null) {
      if (!mounted) return;
      filePath = await showDownloadDialog(context, _updateInfo!);
      if (filePath != null) {
        setState(() => _downloadedFilePath = filePath);
      }
    } else {
      AppLogger.info('Reusing cached APK: $filePath');
    }

    if (filePath != null && mounted) {
      final installed = await showInstallDialog(context, filePath);
      if (installed) {
        setState(() {
          _updateInfo = null;
          _downloadedFilePath = null;
        });
      } else {
        // Install dialog dismissed — clear the cached APK so the next tap
        // always re-downloads a fresh copy.
        setState(() => _downloadedFilePath = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_updateInfo == null) return widget.child;

    return Material(
      child: Column(
        children: [
          Container(
            color: _updateInfo!.isNightly ? Colors.orange.shade700 : Theme.of(context).primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Icon(
                    _updateInfo!.isNightly ? Icons.science : Icons.system_update,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _updateInfo!.isNightly
                          ? 'New nightly build available: ${_updateInfo!.version}'
                          : 'Update available: ${_updateInfo!.version}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  TextButton(
                    onPressed: _handleUpdateDownload,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: const Text('Update'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _updateInfo = null;
                        _downloadedFilePath = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
