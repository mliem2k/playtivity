import 'package:home_widget/home_widget.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import '../models/activity.dart';
import '../models/user.dart';
import 'app_logger.dart';

@pragma('vm:entry-point')
class WidgetService {
  static const String _androidWidgetName = 'com.mliem.playtivity.widget.PlaytivityWidgetReceiver';
  static const String _iOSWidgetName = 'PlaytivityWidget';

  static const MethodChannel _channel = MethodChannel('playtivity_widget');

  @pragma('vm:entry-point')
  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId('group.com.mliem.playtivity');
    HomeWidget.registerInteractivityCallback(backgroundCallback);
  }

  @pragma('vm:entry-point')
  static FutureOr<void> backgroundCallback(Uri? data) async {
    if (data != null && data.host != 'openApp' && data.host != 'refreshData') {
      AppLogger.warning('Unknown widget action: ${data.host}');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> updateWidget({
    User? currentUser,
    List<Activity>? friendsActivities,
  }) async {
    try {
      final activities = friendsActivities ?? [];
      final count = activities.length;
      final slotsToProcess = math.max(count, 10);

      // Write active slots and clear stale slots in one parallel batch.
      // Count is written only after all slot data is committed so the widget
      // never reads a new count against stale slot values.
      final writes = <Future<void>>[];
      for (int i = 0; i < slotsToProcess; i++) {
        if (i < count) {
          final a = activities[i];
          writes.addAll([
            HomeWidget.saveWidgetData('friend_${i}_name', a.user.displayName),
            HomeWidget.saveWidgetData('friend_${i}_track', a.contentName),
            HomeWidget.saveWidgetData('friend_${i}_artist', a.contentSubtitle),
            HomeWidget.saveWidgetData('friend_${i}_album_art', a.contentImageUrl ?? ''),
            HomeWidget.saveWidgetData('friend_${i}_image', a.user.imageUrl ?? ''),
            HomeWidget.saveWidgetData('friend_${i}_user_id', a.user.id),
            HomeWidget.saveWidgetData('friend_${i}_timestamp', a.timestamp.millisecondsSinceEpoch.toString()),
            HomeWidget.saveWidgetData('friend_${i}_is_currently_playing', a.isCurrentlyPlaying.toString()),
            HomeWidget.saveWidgetData('friend_${i}_activity_type', a.type == ActivityType.playlist ? 'playlist' : 'track'),
          ]);
        } else {
          writes.addAll([
            HomeWidget.saveWidgetData('friend_${i}_name', ''),
            HomeWidget.saveWidgetData('friend_${i}_track', ''),
            HomeWidget.saveWidgetData('friend_${i}_artist', ''),
            HomeWidget.saveWidgetData('friend_${i}_album_art', ''),
            HomeWidget.saveWidgetData('friend_${i}_image', ''),
            HomeWidget.saveWidgetData('friend_${i}_user_id', ''),
            HomeWidget.saveWidgetData('friend_${i}_timestamp', ''),
            HomeWidget.saveWidgetData('friend_${i}_is_currently_playing', ''),
            HomeWidget.saveWidgetData('friend_${i}_activity_type', ''),
          ]);
        }
      }
      await Future.wait(writes);

      await Future.wait([
        HomeWidget.saveWidgetData('activities_count', count.toString()),
        HomeWidget.saveWidgetData('last_update', DateTime.now().toIso8601String()),
      ]);

      await Future.delayed(const Duration(milliseconds: 100));

      try {
        await HomeWidget.updateWidget(
          qualifiedAndroidName: _androidWidgetName,
          iOSName: _iOSWidgetName,
        );
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await _channel.invokeMethod('cacheImages');
          } catch (e) {
            AppLogger.error('Image caching failed', e);
          }
        });
      } catch (e) {
        AppLogger.error('Widget update failed', e);
      }
    } catch (e) {
      AppLogger.error('Error updating widget', e);
    }
  }

  static Future<void> setOnWidgetTapCallback(Function(Uri?) callback) async {
    HomeWidget.widgetClicked.listen(callback);
  }

  static Future<bool> isWidgetSupported() async {
    try {
      await HomeWidget.setAppGroupId('group.com.mliem.playtivity');
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> clearWidgetData() async {
    try {
      final writes = <Future<void>>[];
      for (int i = 0; i < 20; i++) {
        writes.addAll([
          HomeWidget.saveWidgetData('friend_${i}_name', ''),
          HomeWidget.saveWidgetData('friend_${i}_track', ''),
          HomeWidget.saveWidgetData('friend_${i}_artist', ''),
          HomeWidget.saveWidgetData('friend_${i}_album_art', ''),
          HomeWidget.saveWidgetData('friend_${i}_image', ''),
          HomeWidget.saveWidgetData('friend_${i}_user_id', ''),
          HomeWidget.saveWidgetData('friend_${i}_timestamp', ''),
          HomeWidget.saveWidgetData('friend_${i}_is_currently_playing', ''),
          HomeWidget.saveWidgetData('friend_${i}_activity_type', ''),
        ]);
      }
      await Future.wait(writes);
      await Future.wait([
        HomeWidget.saveWidgetData('activities_count', '0'),
        HomeWidget.saveWidgetData('last_update', ''),
      ]);
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidWidgetName,
        iOSName: _iOSWidgetName,
      );
    } catch (e) {
      AppLogger.error('Error clearing widget data', e);
    }
  }
}
