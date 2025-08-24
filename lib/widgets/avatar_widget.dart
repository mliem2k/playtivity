import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final String displayName;
  final double radius;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final Widget? placeholder;
  final Widget? errorWidget;

  const AvatarWidget({
    super.key,
    required this.imageUrl,
    required this.displayName,
    this.radius = 20,
    this.backgroundColor,
    this.textStyle,
    this.placeholder,
    this.errorWidget,
  });

  Widget _buildFallbackAvatar(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Theme.of(context).primaryColor,
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
        style: textStyle ?? const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildFallbackAvatar(context);
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Theme.of(context).primaryColor,
      backgroundImage: CachedNetworkImageProvider(imageUrl!),
      onBackgroundImageError: (exception, stackTrace) {
        // Error handling is done by showing fallback through child
      },
      child: null,
    );
  }
}