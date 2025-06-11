import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import '../models/track.dart';
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
      
      // Save friends' activities (up to 5 to stay within Android widget Column limit)
      if (friendsActivities != null && friendsActivities.isNotEmpty) {
        final limitedActivities = friendsActivities.take(5).toList();
        
        print('📊 Widget: Saving ${limitedActivities.length} activities');
        
        // Save activity count for widget to know how many to show
        await HomeWidget.saveWidgetData('activities_count', limitedActivities.length.toString());
        await _saveToSharedPreferences('activities_count', limitedActivities.length.toString());
        print('📊 Widget: Saved activities_count as ${limitedActivities.length}');
        
        for (int i = 0; i < 5; i++) {
          if (i < limitedActivities.length) {
            final activity = limitedActivities[i];
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
            
            // Save directly to SharedPreferences as fallback
            await _saveToSharedPreferences('friend_${i}_name', activity.user.displayName);
            await _saveToSharedPreferences('friend_${i}_track', activity.contentName);
            await _saveToSharedPreferences('friend_${i}_artist', activity.contentSubtitle);
            await _saveToSharedPreferences('friend_${i}_album_art', activity.contentImageUrl ?? '');
            // Note: Android Glance widgets don't support network images, but saving for iOS
            await _saveToSharedPreferences('friend_${i}_image', activity.user.imageUrl ?? '');
            // Save friend user ID for Spotify profile launching
            await _saveToSharedPreferences('friend_${i}_user_id', activity.user.id);
          } else {
            // Clear unused slots
            await HomeWidget.saveWidgetData('friend_${i}_name', '');
            await HomeWidget.saveWidgetData('friend_${i}_track', '');
            await HomeWidget.saveWidgetData('friend_${i}_artist', '');
            await HomeWidget.saveWidgetData('friend_${i}_album_art', '');
            await HomeWidget.saveWidgetData('friend_${i}_image', '');
            await HomeWidget.saveWidgetData('friend_${i}_user_id', '');
            
            await _saveToSharedPreferences('friend_${i}_name', '');
            await _saveToSharedPreferences('friend_${i}_track', '');
            await _saveToSharedPreferences('friend_${i}_artist', '');
            await _saveToSharedPreferences('friend_${i}_album_art', '');
            await _saveToSharedPreferences('friend_${i}_image', '');
            await _saveToSharedPreferences('friend_${i}_user_id', '');
          }
        }
      } else {
        print('📊 Widget: No activities to save');
        // No activities - clear all slots and set count to 0
        await HomeWidget.saveWidgetData('activities_count', '0');
        await _saveToSharedPreferences('activities_count', '0');
        for (int i = 0; i < 5; i++) {
          await HomeWidget.saveWidgetData('friend_${i}_name', '');
          await HomeWidget.saveWidgetData('friend_${i}_track', '');
          await HomeWidget.saveWidgetData('friend_${i}_artist', '');
          await HomeWidget.saveWidgetData('friend_${i}_album_art', '');
          await HomeWidget.saveWidgetData('friend_${i}_image', '');
          await HomeWidget.saveWidgetData('friend_${i}_user_id', '');
          
          await _saveToSharedPreferences('friend_${i}_name', '');
          await _saveToSharedPreferences('friend_${i}_track', '');
          await _saveToSharedPreferences('friend_${i}_artist', '');
          await _saveToSharedPreferences('friend_${i}_album_art', '');
          await _saveToSharedPreferences('friend_${i}_image', '');
          await _saveToSharedPreferences('friend_${i}_user_id', '');
        }
      }
      
      // Save last update timestamp
      await HomeWidget.saveWidgetData('last_update', DateTime.now().toIso8601String());
      await _saveToSharedPreferences('last_update', DateTime.now().toIso8601String());
      
      // Small delay to ensure data is persisted before widget update
      await Future.delayed(const Duration(milliseconds: 100));
      
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
      final keys = [
        'activities_count',
        'friend_0_name', 'friend_0_track', 'friend_0_artist', 'friend_0_album_art', 'friend_0_image', 'friend_0_user_id',
        'friend_1_name', 'friend_1_track', 'friend_1_artist', 'friend_1_album_art', 'friend_1_image', 'friend_1_user_id',
        'friend_2_name', 'friend_2_track', 'friend_2_artist', 'friend_2_album_art', 'friend_2_image', 'friend_2_user_id',
        'friend_3_name', 'friend_3_track', 'friend_3_artist', 'friend_3_album_art', 'friend_3_image', 'friend_3_user_id',
        'friend_4_name', 'friend_4_track', 'friend_4_artist', 'friend_4_album_art', 'friend_4_image', 'friend_4_user_id',
        'last_update'
      ];
      
      for (String key in keys) {
        await HomeWidget.saveWidgetData(key, '');
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
      
      for (int i = 0; i < 5; i++) {
        final name = prefs.getString('flutter.friend_${i}_name') ?? 'null';
        final track = prefs.getString('flutter.friend_${i}_track') ?? 'null';
        final artist = prefs.getString('flutter.friend_${i}_artist') ?? 'null';
        print('📊   friend_$i: $name - $track by $artist');
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