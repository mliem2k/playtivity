import 'package:flutter/material.dart';
import '../providers/auth_provider.dart';

class AuthLoadingScreen extends StatelessWidget {
  final AuthProvider authProvider;
  const AuthLoadingScreen({super.key, required this.authProvider});

  @override
  Widget build(BuildContext context) {
    final events = authProvider.authEvents;
    final lastError = authProvider.lastAuthError;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Spacer(),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading...', style: TextStyle(fontSize: 16)),
              const Spacer(),
              _AuthDebugPanel(events: events, lastError: lastError),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthDebugPanel extends StatefulWidget {
  final List<String> events;
  final String? lastError;
  const _AuthDebugPanel({required this.events, required this.lastError});

  @override
  State<_AuthDebugPanel> createState() => _AuthDebugPanelState();
}

class _AuthDebugPanelState extends State<_AuthDebugPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: 0.45);
    final errorColor = Colors.red.shade400;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 10);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.lastError != null
                ? errorColor.withValues(alpha: 0.5)
                : dimColor.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report, size: 12, color: dimColor),
                const SizedBox(width: 4),
                Text(
                  'Auth Debug  ${_expanded ? "▲" : "▼"}',
                  style: mono.copyWith(color: dimColor, fontWeight: FontWeight.bold),
                ),
                if (widget.lastError != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.error_outline, size: 12, color: errorColor),
                  const SizedBox(width: 2),
                  Text('error', style: mono.copyWith(color: errorColor)),
                ],
              ],
            ),
            if (widget.lastError != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.lastError!,
                style: mono.copyWith(color: errorColor),
                maxLines: _expanded ? null : 2,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            ],
            if (_expanded && widget.events.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 4),
              ...widget.events.reversed.take(15).map(
                (e) => Text(e, style: mono.copyWith(color: dimColor), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
            if (!_expanded && widget.events.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.events.last,
                style: mono.copyWith(color: dimColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
