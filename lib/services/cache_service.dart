import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_logger.dart';

class CacheService {
  static const String _keyPrefix = 'playtivity_cache_';
  
  static String _buildKey(String key) => '$_keyPrefix$key';
  
  static Future<bool> saveJson(String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = json.encode(data);
      final success = await prefs.setString(_buildKey(key), cacheJson);
      
      if (success) {
        AppLogger.debug('Cache saved successfully for key: $key');
      }
      
      return success;
    } catch (e) {
      AppLogger.error('Error saving cache for key $key', e);
      return false;
    }
  }
  
  static Future<Map<String, dynamic>?> loadJson(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheString = prefs.getString(_buildKey(key));
      
      if (cacheString == null) {
        return null;
      }
      
      final data = json.decode(cacheString) as Map<String, dynamic>;
      AppLogger.debug('Cache loaded successfully for key: $key');
      return data;
    } catch (e) {
      AppLogger.error('Error loading cache for key $key', e);
      return null;
    }
  }
  
  static Future<bool> saveString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setString(_buildKey(key), value);
      
      if (success) {
        AppLogger.debug('String cache saved successfully for key: $key');
      }
      
      return success;
    } catch (e) {
      AppLogger.error('Error saving string cache for key $key', e);
      return false;
    }
  }
  
  static Future<String?> loadString(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_buildKey(key));
      
      if (value != null) {
        AppLogger.debug('String cache loaded successfully for key: $key');
      }
      
      return value;
    } catch (e) {
      AppLogger.error('Error loading string cache for key $key', e);
      return null;
    }
  }
  
  static Future<bool> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.remove(_buildKey(key));
      
      if (success) {
        AppLogger.debug('Cache removed successfully for key: $key');
      }
      
      return success;
    } catch (e) {
      AppLogger.error('Error removing cache for key $key', e);
      return false;
    }
  }
  
  static Future<bool> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_keyPrefix));
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      
      AppLogger.debug('All Playtivity cache cleared successfully');
      return true;
    } catch (e) {
      AppLogger.error('Error clearing cache', e);
      return false;
    }
  }
}