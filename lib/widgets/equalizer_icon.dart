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
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  static const List<int> _delays = [0, 200, 100];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    _animations = _controllers
        .map(
          (c) => Tween<double>(begin: 0.3, end: 1.0).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut),
          ),
        )
        .toList();

    for (int i = 0; i < 3; i++) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_delays[i] > 0) {
          Future.delayed(Duration(milliseconds: _delays[i]), () {
            if (mounted) _controllers[i].repeat(reverse: true);
          });
        } else {
          if (mounted) _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
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
            builder: (_, __) => Container(
              width: (widget.size - 4) / 3,
              height: widget.size * _animations[i].value,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
