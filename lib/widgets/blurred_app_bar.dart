import 'dart:ui';
import 'package:flutter/material.dart';

/// Reusable blurred app bar component
/// Eliminates duplicate backdrop filter and styling code
class BlurredAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final double blurSigma;
  final double backgroundAlpha;
  final VoidCallback? onLeadingPressed;
  final TextStyle? titleStyle;

  const BlurredAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.blurSigma = 15.0,
    this.backgroundAlpha = 230.0,
    this.onLeadingPressed,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveBlurSigma = isDark ? blurSigma + 5 : blurSigma;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: effectiveBlurSigma,
          sigmaY: effectiveBlurSigma,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: theme.appBarTheme.backgroundColor ?? 
                   theme.scaffoldBackgroundColor.withValues(alpha: backgroundAlpha),
            boxShadow: const [], // Empty box shadow for clean look
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              title,
              style: titleStyle ?? const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: leading,
            actions: actions,
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Factory methods for common app bar configurations
extension BlurredAppBarFactory on BlurredAppBar {
  /// Creates a simple blurred app bar with just a title
  static BlurredAppBar simple(String title) {
    return BlurredAppBar(title: title);
  }

  /// Creates a blurred app bar with settings action
  static BlurredAppBar withSettings(String title, VoidCallback onSettingsPressed) {
    return BlurredAppBar(
      title: title,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: onSettingsPressed,
        ),
      ],
    );
  }

  /// Creates a blurred app bar with custom actions
  static BlurredAppBar withActions(String title, List<Widget> actions) {
    return BlurredAppBar(
      title: title,
      actions: actions,
    );
  }
}