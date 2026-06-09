import 'package:flutter/material.dart';
import 'update_modal.dart';

enum UpdateButtonStyle {
  icon,           // Just an icon button
  text,           // Text button
  elevated,       // Elevated button
  listTile,       // List tile format
}

class UpdateButton extends StatelessWidget {
  final UpdateButtonStyle style;
  final String? text;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool forceCheck;
  final Color? color;
  final double? iconSize;

  const UpdateButton({
    super.key,
    this.style = UpdateButtonStyle.icon,
    this.text,
    this.icon,
    this.tooltip,
    this.onPressed,
    this.forceCheck = true,
    this.color,
    this.iconSize,
  });

  factory UpdateButton.icon({
    Key? key,
    IconData? icon,
    String? tooltip,
    VoidCallback? onPressed,
    bool forceCheck = true,
    Color? color,
    double? iconSize,
  }) {
    return UpdateButton(
      key: key,
      style: UpdateButtonStyle.icon,
      icon: icon ?? Icons.system_update,
      tooltip: tooltip ?? 'Check for Updates',
      onPressed: onPressed,
      forceCheck: forceCheck,
      color: color,
      iconSize: iconSize,
    );
  }

  factory UpdateButton.text({
    Key? key,
    String? text,
    IconData? icon,
    VoidCallback? onPressed,
    bool forceCheck = true,
    Color? color,
  }) {
    return UpdateButton(
      key: key,
      style: UpdateButtonStyle.text,
      text: text ?? 'Check for Updates',
      icon: icon,
      onPressed: onPressed,
      forceCheck: forceCheck,
      color: color,
    );
  }

  factory UpdateButton.elevated({
    Key? key,
    String? text,
    IconData? icon,
    VoidCallback? onPressed,
    bool forceCheck = true,
    Color? color,
  }) {
    return UpdateButton(
      key: key,
      style: UpdateButtonStyle.elevated,
      text: text ?? 'Check for Updates',
      icon: icon ?? Icons.system_update,
      onPressed: onPressed,
      forceCheck: forceCheck,
      color: color,
    );
  }

  factory UpdateButton.listTile({
    Key? key,
    String? title,
    String? subtitle,
    IconData? icon,
    VoidCallback? onPressed,
    bool forceCheck = true,
    Color? color,
  }) {
    return UpdateButton(
      key: key,
      style: UpdateButtonStyle.listTile,
      text: title ?? 'Check for Updates',
      tooltip: subtitle ?? 'Look for new versions of the app',
      icon: icon ?? Icons.system_update,
      onPressed: onPressed,
      forceCheck: forceCheck,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final handlePress = onPressed ?? () => _handleUpdateCheck(context);

    switch (style) {
      case UpdateButtonStyle.icon:
        return IconButton(
          icon: Icon(
            icon ?? Icons.system_update,
            color: color,
            size: iconSize,
          ),
          onPressed: handlePress,
          tooltip: tooltip,
        );

      case UpdateButtonStyle.text:
        return TextButton.icon(
          onPressed: handlePress,
          icon: icon != null ? Icon(icon, color: color) : const SizedBox.shrink(),
          label: Text(
            text ?? 'Check for Updates',
            style: color != null ? TextStyle(color: color) : null,
          ),
        );

      case UpdateButtonStyle.elevated:
        return ElevatedButton.icon(
          onPressed: handlePress,
          icon: Icon(icon ?? Icons.system_update),
          label: Text(text ?? 'Check for Updates'),
          style: color != null 
            ? ElevatedButton.styleFrom(backgroundColor: color)
            : null,
        );

      case UpdateButtonStyle.listTile:
        return ListTile(
          leading: Icon(
            icon ?? Icons.system_update,
            color: color,
          ),
          title: Text(text ?? 'Check for Updates'),
          subtitle: tooltip != null ? Text(tooltip!) : null,
          onTap: handlePress,
        );
    }
  }

  Future<void> _handleUpdateCheck(BuildContext context) async {
    await UpdateModal.checkForUpdates(
      context,
      forceCheck: forceCheck,
    );
  }
}