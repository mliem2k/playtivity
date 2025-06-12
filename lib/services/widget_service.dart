import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../models/activity.dart';
import '../models/user.dart';

@pragma('vm:entry-point')
class WidgetService {  static const String _widgetName = 'PlaytivityWidget';
  static const String _androidWidgetName = 'com.mliem.playtivity.widget.PlaytivityWidgetReceiver';
  static const String _iOSWidgetName = 'PlaytivityWidget';
  
  // Method channel for direct widget updates
  static const MethodChannel _channel = MethodChannel('playtivity_widget');
  
  // Initialize the widget
  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId('group.com.mliem.playtivity');
    // Register interactive callback for widget clicks
    HomeWidget.registerInteractivityCallback(backgroundCallback);
  }

  // Background callback for interactive widget actions
  @pragma("vm:entry-point")
  static FutureOr<void> backgroundCallback(Uri? data) async {
    print('🎯 Widget callback triggered with data: $data');
    
    if (data != null) {
      final action = data.host;
      final queryParams = data.queryParameters;
      
      switch (action) {
        case 'openApp':
          print('📱 Opening main app from widget');
          break;
        case 'refreshData':
          print('🔄 Refreshing widget data');
          // Could trigger a data refresh here
          break;
        default:
          print('🤷 Unknown widget action: $action');
      }
    }
  }

  // Save data directly to SharedPreferences as fallback
  static Future<void> _saveToSharedPreferences(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('flutter.$key', value);
      print('📊 Direct save: flutter.$key = $value');
    } catch (e) {
      print('❌ Error saving to SharedPreferences: $e');
    }
  }
  
  // Update widget with friends' activities only
  static Future<void> updateWidget({
    User? currentUser,
    List<Activity>? friendsActivities,
  }) async {
    try {
      
      // Save friends' activities (show all activities, no longer limited to 5)
      if (friendsActivities != null && friendsActivities.isNotEmpty) {
        // Remove the take(5) limitation to show all friends
        final activities = friendsActivities.toList();
        
        print('📊 Widget: Saving ${activities.length} activities');
        
        // First, clear any old data by clearing up to 50 slots to handle large friend lists
        for (int i = 0; i < 50; i++) {
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
          print('📊 Widget: Activity $i - ${activity.user.displayName}: ${activity.contentName}');
          
          // Save via HomeWidget
          await HomeWidget.saveWidgetData('friend_${i}_name', activity.user.displayName);
          await HomeWidget.saveWidgetData('friend_${i}_track', activity.contentName);
          await HomeWidget.saveWidgetData('friend_${i}_artist', activity.contentSubtitle);
          await HomeWidget.saveWidgetData('friend_${i}_album_art', activity.contentImageUrl ?? '');
          // Note: friend_image saved for potential future iOS widget support
          await HomeWidget.saveWidgetData('friend_${i}_image', activity.user.imageUrl ?? '');
          // Save friend user ID for Spotify profile launching
          await HomeWidget.saveWidgetData('friend_${i}_user_id', activity.user.id);
          // Save timestamp and currently playing status for "time ago" functionality
          await HomeWidget.saveWidgetData('friend_${i}_timestamp', activity.timestamp.millisecondsSinceEpoch.toString());
          await HomeWidget.saveWidgetData('friend_${i}_is_currently_playing', activity.isCurrentlyPlaying.toString());
          await HomeWidget.saveWidgetData('friend_${i}_activity_type', activity.type == ActivityType.playlist ? 'playlist' : 'track');
          
          // Save directly to SharedPreferences as fallback
          await _saveToSharedPreferences('friend_${i}_name', activity.user.displayName);
          await _saveToSharedPreferences('friend_${i}_track', activity.contentName);
          await _saveToSharedPreferences('friend_${i}_artist', activity.contentSubtitle);
          await _saveToSharedPreferences('friend_${i}_album_art', activity.contentImageUrl ?? '');
          // Note: Android Glance widgets don't support network images, but saving for iOS
          await _saveToSharedPreferences('friend_${i}_image', activity.user.imageUrl ?? '');
          // Save friend user ID for Spotify profile launching
          await _saveToSharedPreferences('friend_${i}_user_id', activity.user.id);
          // Save timestamp and currently playing status for "time ago" functionality
          await _saveToSharedPreferences('friend_${i}_timestamp', activity.timestamp.millisecondsSinceEpoch.toString());
          await _saveToSharedPreferences('friend_${i}_is_currently_playing', activity.isCurrentlyPlaying.toString());
          await _saveToSharedPreferences('friend_${i}_activity_type', activity.type == ActivityType.playlist ? 'playlist' : 'track');
        }
        
        // Save activity count AFTER all activities are saved for atomic updates
        await HomeWidget.saveWidgetData('activities_count', activities.length.toString());
        await _saveToSharedPreferences('activities_count', activities.length.toString());
        print('📊 Widget: Saved activities_count as ${activities.length} AFTER saving all activities');
        
        // Extra debug logging
        print('📊 Widget: Successfully saved all ${activities.length} activities');
        print('📊 Widget: First friend saved: ${activities.isNotEmpty ? activities[0].user.displayName : 'none'}');
        print('📊 Widget: Last friend saved: ${activities.isNotEmpty ? activities[activities.length - 1].user.displayName : 'none'}');
        
      } else {
        print('📊 Widget: No activities to save');
        // No activities - clear all slots and set count to 0
        await HomeWidget.saveWidgetData('activities_count', '0');
        await _saveToSharedPreferences('activities_count', '0');
        for (int i = 0; i < 50; i++) {
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
      
      // Save last update timestamp
      await HomeWidget.saveWidgetData('last_update', DateTime.now().toIso8601String());
      await _saveToSharedPreferences('last_update', DateTime.now().toIso8601String());
      
      // Longer delay to ensure all data is persisted before widget update
      await Future.delayed(const Duration(milliseconds: 500));
      
      print('📊 Widget: About to call updateWidget()');
      print('📊 Widget: Using androidName: $_androidWidgetName');
      
            // Trigger widget update via method channel
      try {
        final result = await _channel.invokeMethod('updateWidget');
        print('📱 Widget update triggered via method channel: $result');
      } catch (channelError) {
        print('❌ Method channel widget update failed: $channelError');
        // Fallback: data is still saved, widget may update on next system refresh
        print('📱 Data saved to SharedPreferences - widget will update on next refresh');
      }
    } catch (e) {
      print('❌ Error updating widget: $e');
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
      
      // Clear up to 50 friend slots to ensure all data is cleared
      for (int i = 0; i < 50; i++) {
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
        androidName: _androidWidgetName,
        iOSName: _iOSWidgetName,
      );
    } catch (e) {
      print('❌ Error clearing widget data: $e');
    }
  }

  // Debug method to test widget data and update
  static Future<void> debugWidgetData() async {
    try {
      print('📊 === WIDGET DEBUG TEST ===');
      
      // Check what's currently in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      print('📊 Current SharedPreferences data:');
      
      final activitiesCount = prefs.getString('flutter.activities_count') ?? 'null';
      print('📊   activities_count: $activitiesCount');
      
      // Debug all activities (up to 20 to avoid spam)
      final count = int.tryParse(activitiesCount) ?? 0;
      final maxDebug = count > 20 ? 20 : count;
      for (int i = 0; i < maxDebug; i++) {
        final name = prefs.getString('flutter.friend_${i}_name') ?? 'null';
        final track = prefs.getString('flutter.friend_${i}_track') ?? 'null';
        final artist = prefs.getString('flutter.friend_${i}_artist') ?? 'null';
        print('📊   friend_$i: $name - $track by $artist');
      }
      if (count > 20) {
        print('📊   ... and ${count - 20} more activities');
      }
      
      // Test widget update via method channel
      print('📊 Testing widget update...');
      try {
        final result = await _channel.invokeMethod('updateWidget');
        print('📊 Widget update successful via method channel: $result');
      } catch (e) {
        print('📊 Widget update failed: $e');
      }
      
      print('📊 === END WIDGET DEBUG TEST ===');
    } catch (e) {
      print('❌ Error in widget debug: $e');
    }
  }
} 