import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

class LastUpdatedIndicator extends StatelessWidget {
  final DateTime? lastUpdated;
  final bool isRefreshing;

  const LastUpdatedIndicator({
    super.key,
    this.lastUpdated,
    required this.isRefreshing,
  });

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    // Only show "a moment ago" for times within 5 seconds
    if (difference.inSeconds <= 5) {
      return 'a moment ago';
    }
    
    // Manual formatting based on time difference
    if (difference.inHours > 0) {
      final hours = difference.inHours;
      return hours == 1 ? '1 hour ago' : '$hours hours ago';
    } else if (difference.inMinutes > 0) {
      final minutes = difference.inMinutes;
      return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
    } else {
      final seconds = difference.inSeconds;
      return seconds == 1 ? '1 second ago' : '$seconds seconds ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (lastUpdated == null && !isRefreshing) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isRefreshing ? Icons.refresh : Icons.access_time,
            size: 12,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Text(
            isRefreshing 
                ? 'Updating...' 
                : lastUpdated != null 
                    ? 'Updated ${_formatTimeAgo(lastUpdated!)}'
                    : '',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
} 