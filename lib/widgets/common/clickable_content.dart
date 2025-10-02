import 'package:flutter/material.dart';

class ClickableContent extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? splashColor;
  final bool enabled;

  const ClickableContent({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.borderRadius,
    this.hoverColor,
    this.splashColor,
    this.enabled = true,
  });

  factory ClickableContent.compact({
    required Widget child,
    VoidCallback? onTap,
    BorderRadius? borderRadius,
  }) {
    return ClickableContent(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      borderRadius: borderRadius ?? BorderRadius.circular(4),
      child: child,
    );
  }

  factory ClickableContent.standard({
    required Widget child,
    VoidCallback? onTap,
    BorderRadius? borderRadius,
  }) {
    return ClickableContent(
      onTap: onTap,
      padding: const EdgeInsets.all(8),
      borderRadius: borderRadius ?? BorderRadius.circular(8),
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
      onTap: onTap,
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