import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_logger.dart';

/// Service for debounced operations to prevent excessive API calls
/// Ensures operations don't fire too frequently, improving performance and reducing server load
class DebouncedRefreshService {
  static final Map<String, Timer> _timers = {};
  static final Map<String, DateTime> _lastExecution = {};
  
  /// Debounces a function call by the specified duration
  /// If called multiple times within the duration, only the last call executes
  static void debounce(
    String key,
    Duration delay,
    VoidCallback callback, {
    bool executeImmediately = false,
  }) {
    // Cancel existing timer for this key
    _timers[key]?.cancel();
    
    if (executeImmediately) {
      final lastExecution = _lastExecution[key];
      final now = DateTime.now();
      
      // Execute immediately if enough time has passed
      if (lastExecution == null || now.difference(lastExecution) >= delay) {
        _lastExecution[key] = now;
        callback();
        return;
      }
    }
    
    // Set up new debounced timer
    _timers[key] = Timer(delay, () {
      _lastExecution[key] = DateTime.now();
      AppLogger.debug('Executing debounced operation: $key');
      callback();
      _timers.remove(key);
    });
  }
  
  /// Throttles a function call to execute at most once per duration
  /// Unlike debounce, this ensures regular execution intervals
  static void throttle(
    String key,
    Duration interval,
    VoidCallback callback,
  ) {
    final lastExecution = _lastExecution[key];
    final now = DateTime.now();
    
    // If enough time has passed or this is the first call, execute immediately
    if (lastExecution == null || now.difference(lastExecution) >= interval) {
      _lastExecution[key] = now;
      AppLogger.debug('Executing throttled operation: $key');
      callback();
      return;
    }
    
    // If we already have a timer for this key, don't set another
    if (_timers.containsKey(key)) {
      return;
    }
    
    // Set up timer to execute at the next available interval
    final timeUntilNextExecution = interval - now.difference(lastExecution);
    _timers[key] = Timer(timeUntilNextExecution, () {
      _lastExecution[key] = DateTime.now();
      AppLogger.debug('Executing throttled operation: $key');
      callback();
      _timers.remove(key);
    });
  }
  
  /// Cancels a specific debounced/throttled operation
  static void cancel(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
    _lastExecution.remove(key);
    AppLogger.debug('Cancelled operation: $key');
  }
  
  /// Cancels all pending operations
  static void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _lastExecution.clear();
    AppLogger.debug('Cancelled all debounced operations');
  }
  
  /// Gets number of pending operations
  static int get pendingOperationsCount => _timers.length;
  
  /// Checks if a specific operation is pending
  static bool isPending(String key) => _timers.containsKey(key);
}

/// Mixin for widgets that need debounced refresh functionality
mixin DebouncedRefreshMixin<T extends StatefulWidget> on State<T> {
  final Map<String, Timer> _widgetTimers = {};
  
  /// Debounced refresh with automatic cleanup on dispose
  void debouncedRefresh(
    String key,
    Duration delay,
    VoidCallback callback,
  ) {
    _widgetTimers[key]?.cancel();
    
    _widgetTimers[key] = Timer(delay, () {
      if (mounted) {
        AppLogger.debug('Executing widget debounced refresh: $key');
        callback();
      }
      _widgetTimers.remove(key);
    });
  }
  
  /// Cancel specific debounced operation
  void cancelDebouncedRefresh(String key) {
    _widgetTimers[key]?.cancel();
    _widgetTimers.remove(key);
  }
  
  /// Cancel all debounced operations for this widget
  void cancelAllDebouncedRefresh() {
    for (final timer in _widgetTimers.values) {
      timer.cancel();
    }
    _widgetTimers.clear();
  }
  
  @override
  void dispose() {
    cancelAllDebouncedRefresh();
    super.dispose();
  }
}

/// Common debounce keys for consistency
class DebounceKeys {
  static const String homeRefresh = 'home_refresh';
  static const String profileRefresh = 'profile_refresh';
  static const String manualRefresh = 'manual_refresh';
  static const String searchQuery = 'search_query';
  static const String apiCall = 'api_call';
  static const String cacheRefresh = 'cache_refresh';
  
  // Activity-specific
  static const String activityEnhancement = 'activity_enhancement';
  static const String friendsActivities = 'friends_activities';
  static const String currentlyPlaying = 'currently_playing';
}