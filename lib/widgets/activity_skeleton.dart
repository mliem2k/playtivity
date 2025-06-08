import 'package:flutter/material.dart';

class ActivitySkeleton extends StatefulWidget {
  const ActivitySkeleton({super.key});

  @override
  State<ActivitySkeleton> createState() => _ActivitySkeletonState();
}

class _ActivitySkeletonState extends State<ActivitySkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User Info Row Skeleton
                Row(
                  children: [
                    // User Avatar Skeleton
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[300]?.withOpacity(_animation.value),
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // User Name and Status Skeleton
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 120,
                            height: 16,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.grey[300]?.withOpacity(_animation.value),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 80,
                            height: 12,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.grey[300]?.withOpacity(_animation.value),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Content Info Row Skeleton
                Row(
                  children: [
                    // Content Image Skeleton
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[300]?.withOpacity(_animation.value),
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // Content Details Skeleton
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            height: 16,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.grey[300]?.withOpacity(_animation.value),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 150,
                            height: 14,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.grey[300]?.withOpacity(_animation.value),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 100,
                            height: 12,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.grey[300]?.withOpacity(_animation.value),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Play button skeleton
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[300]?.withOpacity(_animation.value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 