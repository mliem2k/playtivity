import 'package:flutter/material.dart';

class RefreshIndicatorBar extends StatelessWidget {
  final bool isRefreshing;
  final String? message;

  const RefreshIndicatorBar({
    super.key,
    required this.isRefreshing,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    if (!isRefreshing) {
      return const SizedBox.shrink();
    }

    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: primaryColor.withAlpha((0.1 * 255).round()),
        border: Border(
          bottom: BorderSide(
            color: primaryColor.withAlpha((0.2 * 255).round()),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            message ?? 'Refreshing...',
            style: TextStyle(
              color: primaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
} 