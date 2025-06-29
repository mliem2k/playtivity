import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  
  // Method channel for direct widget updates
  static const MethodChannel _channel = MethodChannel('playtivity_widget');
  
  // Initialize the widget
  @pragma('vm:entry-point')
  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId('group.com.mliem.playtivity');
    // Register interactive callback for widget clicks
    HomeWidget.registerInteractivityCallback(backgroundCallback);
  }

  // Background callback for interactive widget actions
  @pragma("vm:entry-point")
  static FutureOr<void> backgroundCallback(Uri? data) async {
    if (data != null) {
      final action = data.host;
      
      switch (action) {
        case 'openApp':
        case 'refreshData':
          break;
        default:
          AppLogger.warning('Unknown widget action: $action');
      }
    }
  }
  
  // Save data directly to SharedPreferences as fallback
  static Future<void> _saveToSharedPreferences(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Save to both flutter prefix and regular HomeWidget prefix for maximum compatibility
      await prefs.setString('flutter.$key', value);
      await prefs.setString(key, value); // Also save without flutter prefix
    } catch (e) {
      AppLogger.error('Error saving to SharedPreferences', e);
    }
  }
  
  // Update widget with friends' activities only
  @pragma('vm:entry-point')
  static Future<void> updateWidget({
    User? currentUser,
    List<Activity>? friendsActivities,
  }) async {
    try {
      // Save friends' activities (show all activities, no longer limited to 5)
      if (friendsActivities != null && friendsActivities.isNotEmpty) {
        // Remove the take(5) limitation to show all friends
        final activities = friendsActivities.toList();
        
        // Optimize: Only clear necessary slots based on current activity count
        final maxSlotsToProcess = math.max(activities.length, 10); // Process at least 10 to clear old data
        for (int i = 0; i < maxSlotsToProcess; i++) {
          await HomeWidget.saveWidgetData('friend_${i}_name', '');
          await HomeWidget.saveWidgetData('friend_${i}_track', '');
          await HomeWidget.saveWidgetData('friend_${i}_artist', '');
          await HomeWidget.saveWidgetData('friend_${i}_album_art', '');
          await HomeWidget.saveWidgetData('friend_${i}_image', '');
          await HomeWidget.saveWidgetData('friend_${i}_user_id', '');
          await HomeWidget.saveWidgetData('friend_${i}_timestamp', '');
          await HomeWidget.saveWidgetData('friend_${i}_is_currently_playing', '');
          await HomeWidget.saveWidgetData('friend_${i}_activity_type', '');
          
          await _saveToSharedPreferences('friend_${i}_name', '');
          await _saveToSharedPreferences('friend_${i}_track', '');
          await _saveToSharedPreferences('friend_${i}_artist', '');
          await _saveToSharedPreferences('friend_${i}_album_art', '');
          await _saveToSharedPreferences('friend_${i}_image', '');
          await _saveToSharedPreferences('friend_${i}_user_id', '');
          await _saveToSharedPreferences('friend_${i}_timestamp', '');
          await _saveToSharedPreferences('friend_${i}_is_currently_playing', '');
          await _saveToSharedPreferences('friend_${i}_activity_type', '');
        }
        
        // Now save all the actual activities
        for (int i = 0; i < activities.length; i++) {
          final activity = activities[i];
          
          // Save via HomeWidget - batch operations for better performance
          await HomeWidget.saveWidgetData('friend_${i}_name', activity.user.displayName);
          await HomeWidget.saveWidgetData('friend_${i}_track', activity.contentName);
          await HomeWidget.saveWidgetData('friend_${i}_artist', activity.contentSubtitle);
          await HomeWidget.saveWidgetData('friend_${i}_album_art', activity.contentImageUrl ?? '');
          await HomeWidget.saveWidgetData('friend_${i}_image', activity.user.imageUrl ?? '');
          await HomeWidget.saveWidgetData('friend_${i}_user_id', activity.user.id);
          await HomeWidget.saveWidgetData('friend_${i}_timestamp', activity.timestamp.millisecondsSinceEpoch.toString());
          await HomeWidget.saveWidgetData('friend_${i}_is_currently_playing', activity.isCurrentlyPlaying.toString());
          await HomeWidget.saveWidgetData('friend_${i}_activity_type', activity.type == ActivityType.playlist ? 'playlist' : 'track');
          
          // Save directly to SharedPreferences as fallback - reduced logging
          await _saveToSharedPreferences('friend_${i}_name', activity.user.displayName);
          await _saveToSharedPreferences('friend_${i}_track', activity.contentName);
          await _saveToSharedPreferences('friend_${i}_artist', activity.contentSubtitle);
          await _saveToSharedPreferences('friend_${i}_album_art', activity.contentImageUrl ?? '');
          await _saveToSharedPreferences('friend_${i}_image', activity.user.imageUrl ?? '');
          await _saveToSharedPreferences('friend_${i}_user_id', activity.user.id);
          await _saveToSharedPreferences('friend_${i}_timestamp', activity.timestamp.millisecondsSinceEpoch.toString());
          await _saveToSharedPreferences('friend_${i}_is_currently_playing', activity.isCurrentlyPlaying.toString());
          await _saveToSharedPreferences('friend_${i}_activity_type', activity.type == ActivityType.playlist ? 'playlist' : 'track');
        }
        
        // Save activity count AFTER all activities are saved for atomic updates
        await HomeWidget.saveWidgetData('activities_count', activities.length.toString());
        await _saveToSharedPreferences('activities_count', activities.length.toString());
      } else {
        // No activities - clear all slots and set count to 0
        await HomeWidget.saveWidgetData('activities_count', '0');
        await _saveToSharedPreferences('activities_count', '0');
        
        // Clear only necessary slots for performance
        for (int i = 0; i < 10; i++) {
          await HomeWidget.saveWidgetData('friend_${i}_name', '');
          await HomeWidget.saveWidgetData('friend_${i}_track', '');
          await HomeWidget.saveWidgetData('friend_${i}_artist', '');
          await HomeWidget.saveWidgetData('friend_${i}_album_art', '');
          await HomeWidget.saveWidgetData('friend_${i}_image', '');
          await HomeWidget.saveWidgetData('friend_${i}_user_id', '');
          await HomeWidget.saveWidgetData('friend_${i}_timestamp', '');
          await HomeWidget.saveWidgetData('friend_${i}_is_currently_playing', '');
          await HomeWidget.saveWidgetData('friend_${i}_activity_type', '');
          
          await _saveToSharedPreferences('friend_${i}_name', '');
          await _saveToSharedPreferences('friend_${i}_track', '');
          await _saveToSharedPreferences('friend_${i}_artist', '');
          await _saveToSharedPreferences('friend_${i}_album_art', '');
          await _saveToSharedPreferences('friend_${i}_image', '');
          await _saveToSharedPreferences('friend_${i}_user_id', '');
          await _saveToSharedPreferences('friend_${i}_timestamp', '');
          await _saveToSharedPreferences('friend_${i}_is_currently_playing', '');
          await _saveToSharedPreferences('friend_${i}_activity_type', '');
        }
      }
      
      await _saveToSharedPreferences('last_update', DateTime.now().toIso8601String());
      
      // Reduced delay for faster widget updates
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Trigger simple widget update
      try {
        await HomeWidget.updateWidget(
          qualifiedAndroidName: _androidWidgetName,
          iOSName: _iOSWidgetName,
        );
        // Force image caching after a short delay
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
  
  // Handle widget taps
  static Future<void> setOnWidgetTapCallback(Function(Uri?) callback) async {
    HomeWidget.widgetClicked.listen(callback);
  }
  
  // Check if widget is supported on this device
  static Future<bool> isWidgetSupported() async {
    try {
      await HomeWidget.setAppGroupId('group.com.mliem.playtivity');
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // Clear widget data
  static Future<void> clearWidgetData() async {
    try {
      // Clear activities count
      await HomeWidget.saveWidgetData('activities_count', '0');
      await HomeWidget.saveWidgetData('last_update', '');
      
      // Optimized: Clear only necessary slots to improve performance
      for (int i = 0; i < 20; i++) {
        await HomeWidget.saveWidgetData('friend_${i}_name', '');
        await HomeWidget.saveWidgetData('friend_${i}_track', '');
        await HomeWidget.saveWidgetData('friend_${i}_artist', '');
        await HomeWidget.saveWidgetData('friend_${i}_album_art', '');
        await HomeWidget.saveWidgetData('friend_${i}_image', '');
        await HomeWidget.saveWidgetData('friend_${i}_user_id', '');
        await HomeWidget.saveWidgetData('friend_${i}_timestamp', '');
        await HomeWidget.saveWidgetData('friend_${i}_is_currently_playing', '');
        await HomeWidget.saveWidgetData('friend_${i}_activity_type', '');
      }
      
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidWidgetName,
        iOSName: _iOSWidgetName,
      );
    } catch (e) {
      AppLogger.error('Error clearing widget data', e);
    }
  }
  
  // Debug method to test widget data and update
  static Future<void> debugWidgetData() async {
    try {
      AppLogger.widget('=== WIDGET DEBUG TEST ===');
      
      // Check what's currently in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      AppLogger.widget('Current SharedPreferences data:');
      
      final activitiesCount = prefs.getString('flutter.activities_count') ?? 'null';
      AppLogger.widget('activities_count: $activitiesCount');
      
      // Debug only first 5 activities to reduce noise
      final count = int.tryParse(activitiesCount) ?? 0;
      final maxDebug = count > 5 ? 5 : count;
      for (int i = 0; i < maxDebug; i++) {
        final name = prefs.getString('flutter.friend_${i}_name') ?? 'null';
        final track = prefs.getString('flutter.friend_${i}_track') ?? 'null';
        final artist = prefs.getString('flutter.friend_${i}_artist') ?? 'null';
        final userId = prefs.getString('flutter.friend_${i}_user_id') ?? 'null';
        AppLogger.widget('friend_$i: $name - $track by $artist (ID: $userId)');
      }
      if (count > 5) {
        AppLogger.widget('... and ${count - 5} more activities');
      }
      
      // Test widget update via method channel
      AppLogger.widget('Testing widget update...');
      try {
        final result = await _channel.invokeMethod('updateWidget');
        AppLogger.widget('Widget update successful via method channel: $result');
      } catch (e) {
        AppLogger.error('Widget update failed', e);
      }
      
      AppLogger.widget('=== END WIDGET DEBUG TEST ===');
    } catch (e) {
      AppLogger.error('Error in widget debug', e);
    }
  }

  // Comprehensive debug for release builds
  static Future<Map<String, dynamic>> debugReleaseWidget() async {
    final debugInfo = <String, dynamic>{};
    
    try {
      AppLogger.widget('=== RELEASE WIDGET DEBUG ===');
      
      // 1. Check SharedPreferences data
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys().toList();
      final widgetKeys = allKeys.where((key) => 
        key.contains('activities') || key.contains('friend_') || key.contains('last_update')
      ).toList();
      
      debugInfo['total_keys'] = allKeys.length;
      debugInfo['widget_keys'] = widgetKeys.length;
      debugInfo['widget_key_list'] = widgetKeys;
      
      AppLogger.widget('Total keys in SharedPreferences: ${allKeys.length}');
      AppLogger.widget('Widget-related keys: ${widgetKeys.length}');
      
      // 2. Check activities data
      final flutterActivitiesCount = prefs.getString('flutter.activities_count');
      final homeWidgetActivitiesCount = prefs.getString('activities_count');
      
      debugInfo['flutter_activities_count'] = flutterActivitiesCount;
      debugInfo['home_widget_activities_count'] = homeWidgetActivitiesCount;
      
      AppLogger.widget('Flutter activities count: $flutterActivitiesCount');
      AppLogger.widget('HomeWidget activities count: $homeWidgetActivitiesCount');
      
      // 3. Test method channel
      debugInfo['method_channel_available'] = false;
      try {
        final result = await _channel.invokeMethod('updateWidget');
        debugInfo['method_channel_available'] = true;
        debugInfo['method_channel_result'] = result;
        AppLogger.widget('Method channel works: $result');
      } catch (e) {
        debugInfo['method_channel_error'] = e.toString();
        AppLogger.error('Method channel failed', e);
      }
      
      // 4. Test HomeWidget integration
      debugInfo['home_widget_available'] = false;
      try {
        await HomeWidget.setAppGroupId('group.com.mliem.playtivity');
        debugInfo['home_widget_available'] = true;
        AppLogger.widget('HomeWidget integration works');
      } catch (e) {
        debugInfo['home_widget_error'] = e.toString();
        AppLogger.error('HomeWidget integration failed', e);
      }
      
      AppLogger.widget('=== END RELEASE DEBUG ===');
      
    } catch (e) {
      debugInfo['debug_error'] = e.toString();
      AppLogger.error('Debug error', e);
    }
    
    return debugInfo;
  }
} 