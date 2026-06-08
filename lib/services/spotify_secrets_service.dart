// lib/services/spotify_secrets_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';
import 'spotify_totp_helper.dart';

class SpotifySecretsService {
  static const String _remoteUrl =
      'https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true';
  static const String _cacheKey = 'spotify_totp_secrets';
  static const String _cacheTimestampKey = 'spotify_totp_secrets_ts';
  static const int _cacheTtlMs = 6 * 60 * 60 * 1000; // 6 hours in ms

  /// Loads secrets (cache-first, then remote), applies them to SpotifyTotpHelper.
  /// Silent on failure — TOTP falls back to hardcoded constants.
  static Future<Map<String, List<int>>?> loadAndApply() async {
    final secrets = await _loadSecrets();
    if (secrets != null) {
      SpotifyTotpHelper.applySecrets(secrets);
      AppLogger.info('TOTP secrets loaded (version: ${SpotifyTotpHelper.activeVersion})');
    }
    return secrets;
  }

  /// Validates that [raw] is a non-empty dict of digit-string keys to non-empty int-list values.
  /// Returns the typed map on success, null on any validation failure.
  static Map<String, List<int>>? validateSecretsFormat(Map<String, dynamic> raw) {
    if (raw.isEmpty) return null;
    final result = <String, List<int>>{};
    for (final entry in raw.entries) {
      if (!RegExp(r'^\d+$').hasMatch(entry.key)) return null;
      if (entry.value is! List) return null;
      final list = entry.value as List;
      if (list.isEmpty) return null;
      if (!list.every((e) => e is int)) return null;
      result[entry.key] = list.cast<int>();
    }
    return result;
  }

  static Future<Map<String, List<int>>?> _loadSecrets() async {
    final cached = await _loadFromCache();
    if (cached != null) return cached;

    try {
      final response = await http
          .get(Uri.parse(_remoteUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        AppLogger.spotify('TOTP secrets fetch failed: HTTP ${response.statusCode}');
        return null;
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final validated = validateSecretsFormat(decoded);
      if (validated == null) {
        AppLogger.spotify('TOTP secrets failed format validation');
        return null;
      }

      await _saveToCache(validated);
      return validated;
    } catch (e) {
      AppLogger.spotify('TOTP secrets fetch error: $e');
      return null;
    }
  }

  static Future<Map<String, List<int>>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_cacheTimestampKey);
      if (ts == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > _cacheTtlMs) return null;

      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;

      final decoded = json.decode(raw) as Map<String, dynamic>;
      return validateSecretsFormat(decoded);
    } catch (e) {
      AppLogger.spotify('TOTP cache load error: $e');
      return null;
    }
  }

  static Future<void> _saveToCache(Map<String, List<int>> secrets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(secrets));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      AppLogger.spotify('TOTP cache save error: $e');
    }
  }
}
