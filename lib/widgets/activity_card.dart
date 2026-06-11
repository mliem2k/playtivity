import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/activity.dart';
import '../models/playlist.dart';
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
            _AlbumArt(activity: activity),
          ],
        ),
      ),
    );
  }
}

// Album art with an inset green ring overlay when the friend is currently playing.
// The overlay is drawn on top of the image via a Stack so card dimensions never change.
class _AlbumArt extends StatelessWidget {
  final Activity activity;
  const _AlbumArt({required this.activity});

  @override
  Widget build(BuildContext context) {
    final art = AlbumArtWidget(imageUrl: activity.contentImageUrl, size: 48);
    if (!activity.isCurrentlyPlaying) return art;
    return Stack(
      children: [
        art,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.primaryActive, width: 2),
            ),
          ),
        ),
      ],
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
          _RunningText(text: activity.track!.name, style: tt.bodyLarge),
          const SizedBox(height: 2),
          _RunningText(
            text: '${activity.track!.artistsString} · ${activity.track!.album}',
            style: tt.bodyMedium,
          ),
        ] else if (activity.playlist != null) ...[
          const SizedBox(height: 4),
          _RunningText(text: activity.contentName, style: tt.bodyLarge),
          const SizedBox(height: 2),
          _RunningText(
            text: _playlistSubtitle(activity.playlist!),
            style: tt.bodyMedium,
          ),
        ],
      ],
    );
  }

  static String _playlistSubtitle(Playlist playlist) {
    final owner = playlist.ownerName.isNotEmpty ? playlist.ownerName : null;
    final count = playlist.trackCount > 0 ? '${playlist.trackCount} tracks' : null;
    if (owner != null && count != null) return '$owner · $count';
    if (owner != null) return owner;
    if (count != null) return 'Playlist · $count';
    return 'Playlist';
  }
}

// Scrolling marquee for text that overflows its container.
// When the text fits, renders a plain Text widget — no animation overhead.
// When it overflows, scrolls forward, pauses, scrolls back, pauses, repeats.
// Uses Timer instead of Future.delayed so pending callbacks are cancelled
// on dispose and on text changes, avoiding dangling closures in the event queue.
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
  Timer? _timer;

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
      _timer?.cancel();
      _ctrl.stop();
      _ctrl.reset();
      _lastWidth = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    final paragraph = tp.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    _overflow =
        (paragraph.longestLine - containerWidth).clamp(0.0, double.infinity);

    _timer?.cancel();
    _ctrl.stop();
    _ctrl.reset();
    _ctrl.removeStatusListener(_onStatus);

    if (_overflow > 0) {
      _ctrl.duration =
          Duration(milliseconds: (_overflow / 40 * 1000).round());
      _anim = Tween<double>(begin: 0, end: _overflow)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));
      _ctrl.addStatusListener(_onStatus);
      _timer = Timer(const Duration(seconds: 2), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  void _onStatus(AnimationStatus status) {
    _timer?.cancel();
    if (status == AnimationStatus.completed) {
      _timer = Timer(const Duration(seconds: 2), () {
        if (mounted) _ctrl.reverse();
      });
    } else if (status == AnimationStatus.dismissed) {
      _timer = Timer(const Duration(seconds: 1), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      _measure(constraints.maxWidth);
      if (_overflow <= 0) {
        return Text(widget.text,
            style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis);
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
            child: Text(widget.text,
                style: widget.style, maxLines: 1, softWrap: false),
          ),
        ),
      );
    });
  }
}

class _StatusLine extends StatelessWidget {
  final bool isCurrentlyPlaying;
  final DateTime timestamp;
  const _StatusLine(
      {required this.isCurrentlyPlaying, required this.timestamp});

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
