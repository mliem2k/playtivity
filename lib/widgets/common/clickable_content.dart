import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ClickableContent extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? splashColor;
  final bool enabled;
  final bool useHaptics;

  const ClickableContent({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.borderRadius,
    this.hoverColor,
    this.splashColor,
    this.enabled = true,
    this.useHaptics = false,
  });

  factory ClickableContent.compact({
    required Widget child,
    VoidCallback? onTap,
    BorderRadius? borderRadius,
    bool useHaptics = false,
  }) {
    return ClickableContent(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      borderRadius: borderRadius ?? BorderRadius.circular(4),
      useHaptics: useHaptics,
      child: child,
    );
  }

  factory ClickableContent.standard({
    required Widget child,
    VoidCallback? onTap,
    BorderRadius? borderRadius,
    bool useHaptics = false,
  }) {
    return ClickableContent(
      onTap: onTap,
      padding: const EdgeInsets.all(8),
      borderRadius: borderRadius ?? BorderRadius.circular(8),
      useHaptics: useHaptics,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (onTap == null || !enabled) {
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      );
    }

    return InkWell(
      onTap: () {
        if (useHaptics) HapticFeedback.lightImpact();
        onTap!();
      },
      borderRadius: borderRadius,
      hoverColor: hoverColor,
      splashColor: splashColor,
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }
}
