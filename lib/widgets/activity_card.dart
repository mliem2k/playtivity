import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/activity.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import '../utils/friend_profile_launcher.dart';
import 'avatar_widget.dart';
import 'common/album_art_widget.dart';
import 'equalizer_icon.dart';
import 'package:timeago/timeago.dart' as timeago;

class ActivityCard extends StatelessWidget {
  final Activity activity;

  const ActivityCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async =>
          SpotifyLauncher.launchSpotifyUriAndPlay(activity.contentUri),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(activity: activity),
            const SizedBox(width: 16),
            Expanded(child: _InfoColumn(activity: activity)),
            const SizedBox(width: 12),
            AlbumArtWidget(imageUrl: activity.track?.imageUrl, size: 48),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Activity activity;
  const _Avatar({required this.activity});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async => FriendProfileLauncher.openFriendProfile(
        activity.user.id,
        friendName: activity.user.displayName,
      ),
      customBorder: const CircleBorder(),
      child: AvatarWidget(
        imageUrl: activity.user.imageUrl,
        displayName: activity.user.displayName,
        radius: 22,
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final Activity activity;
  const _InfoColumn({required this.activity});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          activity.user.displayName,
          style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        _StatusLine(
          isCurrentlyPlaying: activity.isCurrentlyPlaying,
          timestamp: activity.timestamp,
        ),
        if (activity.track != null) ...[
          const SizedBox(height: 4),
          Text(
            activity.track!.name,
            style: tt.bodyLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          _RunningText(
            text: '${activity.track!.artistsString} · ${activity.track!.album}',
            style: tt.bodyMedium,
          ),
        ],
      ],
    );
  }
}

class _RunningText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const _RunningText({required this.text, this.style});
  @override
  State<_RunningText> createState() => _RunningTextState();
}

class _RunningTextState extends State<_RunningText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _anim;
  double _overflow = 0;
  double? _lastWidth;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
    _anim = const AlwaysStoppedAnimation(0);
  }

  @override
  void didUpdateWidget(_RunningText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _ctrl.stop();
      _ctrl.reset();
      _lastWidth = null;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _measure(double containerWidth) {
    if (_lastWidth == containerWidth) return;
    _lastWidth = containerWidth;

    final style = widget.style ?? const TextStyle();
    final tp = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1))
      ..pushStyle(style.getTextStyle())
      ..addText(widget.text);
    final paragraph = tp.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
    _overflow = (paragraph.longestLine - containerWidth).clamp(0.0, double.infinity);

    _ctrl.stop();
    _ctrl.reset();
    _ctrl.removeStatusListener(_onStatus);

    if (_overflow > 0) {
      _ctrl.duration = Duration(milliseconds: (_overflow / 40 * 1000).round());
      _anim = Tween<double>(begin: 0, end: _overflow)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));
      _ctrl.addStatusListener(_onStatus);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _ctrl.reverse();
      });
    } else if (status == AnimationStatus.dismissed) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      _measure(constraints.maxWidth);
      if (_overflow <= 0) {
        return Text(widget.text, style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis);
      }
      return ClipRect(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Transform.translate(
            offset: Offset(-_anim.value, 0),
            child: child,
          ),
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
          ),
        ),
      );
    });
  }
}

class _StatusLine extends StatelessWidget {
  final bool isCurrentlyPlaying;
  final DateTime timestamp;
  const _StatusLine({required this.isCurrentlyPlaying, required this.timestamp});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (isCurrentlyPlaying) {
      return Row(
        children: [
          const EqualizerIcon(size: 12),
          const SizedBox(width: 4),
          Text(
            'Listening now',
            style: tt.labelSmall?.copyWith(color: AppTheme.primaryActive),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.history, size: 12, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          timeago.format(timestamp),
          style: tt.labelSmall,
        ),
      ],
    );
  }
}
