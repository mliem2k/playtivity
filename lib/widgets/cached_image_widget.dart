import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CachedImageWidget extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Color? placeholderColor;
  final IconData placeholderIcon;
  final double placeholderIconSize;

  const CachedImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.placeholderColor,
    this.placeholderIcon = Icons.music_note,
    this.placeholderIconSize = 24,
  });

  Widget _buildDefaultPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: placeholderColor ?? Colors.grey[300],
        borderRadius: borderRadius,
      ),
      child: Icon(
        placeholderIcon,
        size: placeholderIconSize,
        color: Colors.grey[600],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return errorWidget ?? _buildDefaultPlaceholder(context);
    }

    Widget imageWidget = CachedNetworkImage(
      imageUrl: imageUrl!,
      width: width,
      height: height,
      fit: fit,
      // Memory optimization - cache smaller versions in memory
      memCacheWidth: width?.toInt(),
      memCacheHeight: height?.toInt(),
      // Limit disk cache size for performance
      maxWidthDiskCache: 400,
      maxHeightDiskCache: 400,
      // Faster image loading
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (context, url) => placeholder ?? _buildDefaultPlaceholder(context),
      errorWidget: (context, url, error) => errorWidget ?? _buildDefaultPlaceholder(context),
    );

    if (borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}