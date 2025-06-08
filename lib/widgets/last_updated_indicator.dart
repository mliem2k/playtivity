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
                    ? 'Updated ${timeago.format(lastUpdated!)}'
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