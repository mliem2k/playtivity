import 'package:flutter/material.dart';
import '../utils/theme.dart';

class ActivitySkeleton extends StatelessWidget {
  final Animation<double> animation;

  const ActivitySkeleton({super.key, required this.animation});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: const _SkeletonRow(),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _block(44, 44, isCircle: true),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _block(120, 12),
                const SizedBox(height: 6),
                _block(80, 10),
                const SizedBox(height: 6),
                _block(double.infinity, 12),
                const SizedBox(height: 4),
                _block(160, 10),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _block(48, 48, radius: 4),
        ],
      ),
    );
  }

  Widget _block(double width, double height,
      {bool isCircle = false, double radius = 4}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}
