import 'package:flutter/material.dart';
import '../cached_image_widget.dart';
import '../../utils/theme.dart';

class AlbumArtWidget extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final double borderRadius;

  const AlbumArtWidget({
    super.key,
    required this.imageUrl,
    required this.size,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? CachedImageWidget(imageUrl: imageUrl!, width: size, height: size)
          : Container(
              width: size,
              height: size,
              color: AppTheme.surfaceElevated,
              child: Icon(
                Icons.music_note,
                color: AppTheme.textSubdued,
                size: size * 0.4,
              ),
            ),
    );
  }
}
