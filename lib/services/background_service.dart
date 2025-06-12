import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'widget_service.dart';
import '../services/spotify_service.dart';
import '../services/spotify_buddy_service.dart';
import '../models/user.dart';
import '../models/activity.dart';

class BackgroundService {
  static const String _widgetUpdateTaskName = "widget_update_task";
  static const String _widgetUpdateTaskId = "widget_update_periodic";
  
  // Initialize background service
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true, // Set to false in production
    );
  }
  
  // Register periodic widget update task
  static Future<void> registerWidgetUpdateTask() async {
    try {
      // Cancel any existing task first
      await Workmanager().cancelByUniqueName(_widgetUpdateTaskId);
      
      // Register new periodic task (every 30 minutes)
      await Workmanager().registerPeriodicTask(
        _widgetUpdateTaskId,
        _widgetUpdateTaskName,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        inputData: {
          'task_type': 'widget_update',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      
      print('🔄 Background widget update task registered');
    } catch (e) {
      print('❌ Error registering background task: $e');
    }
  }
  
  // Cancel widget update task
  static Future<void> cancelWidgetUpdateTask() async {
    try {
      await Workmanager().cancelByUniqueName(_widgetUpdateTaskId);
      print('🛑 Background widget update task cancelled');
    } catch (e) {
      print('❌ Error cancelling background task: $e');
    }
  }
  
  // Cancel all background tasks
  static Future<void> cancelAllTasks() async {
    try {
      await Workmanager().cancelAll();
      print('🛑 All background tasks cancelled');
    } catch (e) {
      print('❌ Error cancelling all background tasks: $e');
    }
  }
}

// Background callback dispatcher - must be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('🔄 Background task started: $task');
    
    try {
      switch (task) {
        case BackgroundService._widgetUpdateTaskName:
          await _updateWidgetInBackground(inputData);
          break;
        default:
          print('❓ Unknown background task: $task');
      }
      
      print('✅ Background task completed: $task');
      return Future.value(true);
    } catch (e) {
      print('❌ Background task failed: $task - $e');
      return Future.value(false);
    }
  });
}

// Update widget in background
Future<void> _updateWidgetInBackground(Map<String, dynamic>? inputData) async {
  try {
    print('📱 Starting background widget update...');
    
    // Get stored authentication data
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('flutter.spotify_user');
    final bearerToken = prefs.getString('flutter.spotify_bearer_token');
    
    if (userJson == null || bearerToken == null) {
      print('❌ No authentication data found for background update');
      return;
    }
    
    // Parse user data
    final userData = json.decode(userJson);
    final currentUser = User.fromJson(userData);
    
    // Create Spotify buddy service instance
    final buddyService = SpotifyBuddyService.instance;
    
    // Fetch friends' activities
    final friendsActivities = await buddyService.getFriendActivity();
    
    if (friendsActivities.isNotEmpty) {
      print('📊 Background: Fetched ${friendsActivities.length} activities');
      
      // Update widget with new data
      await WidgetService.updateWidget(
        currentUser: currentUser,
        friendsActivities: friendsActivities,
      );
      
      print('✅ Background widget update completed');
    } else {
      print('📊 Background: No activities found');
      
      // Update widget with empty data
      await WidgetService.updateWidget(
        currentUser: currentUser,
        friendsActivities: [],
      );
    }
    
  } catch (e) {
    print('❌ Error in background widget update: $e');
    rethrow;
  }
} 