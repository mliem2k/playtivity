import 'package:flutter/material.dart';
import '../utils/theme.dart';

class EqualizerIcon extends StatefulWidget {
  final Color color;
  final double size;

  const EqualizerIcon({
    super.key,
    this.color = AppTheme.primaryActive,
    this.size = 14,
  });

  @override
  State<EqualizerIcon> createState() => _EqualizerIconState();
}

class _EqualizerIconState extends State<EqualizerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _animations;
  late BoxDecoration _barDecoration;
  late double _barWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // Original delays: bar 0 = 0ms, bar 1 = 200ms, bar 2 = 100ms
    // Expressed as fractions of the 600ms cycle: 200/600 = 0.333, 100/600 = 0.167
    _animations = [
      Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
        ),
      ),
      Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.333, 1.0, curve: Curves.easeInOut),
        ),
      ),
      Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.167, 1.0, curve: Curves.easeInOut),
        ),
      ),
    ];

    _barDecoration = BoxDecoration(
      color: widget.color,
      borderRadius: BorderRadius.circular(1),
    );
    _barWidth = (widget.size - 4) / 3;
  }

  @override
  void didUpdateWidget(EqualizerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color || oldWidget.size != widget.size) {
      _barDecoration = BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(1),
      );
      _barWidth = (widget.size - 4) / 3;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          3,
          (i) => AnimatedBuilder(
            animation: _animations[i],
            builder: (_, _) => Container(
              width: _barWidth,
              height: widget.size * _animations[i].value,
              decoration: _barDecoration,
            ),
          ),
        ),
      ),
    );
  }
}
