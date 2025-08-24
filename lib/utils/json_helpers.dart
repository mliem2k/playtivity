class JsonHelpers {
  /// Safely extracts string value with null-safe default
  static String getString(Map<String, dynamic> json, String key, [String defaultValue = '']) {
    return json[key] as String? ?? defaultValue;
  }
  
  /// Safely extracts integer value with null-safe default  
  static int getInt(Map<String, dynamic> json, String key, [int defaultValue = 0]) {
    return json[key] as int? ?? defaultValue;
  }
  
  /// Safely extracts boolean value with null-safe default
  static bool getBool(Map<String, dynamic> json, String key, [bool defaultValue = false]) {
    return json[key] as bool? ?? defaultValue;
  }
  
  /// Safely extracts nested string value with null-safe default
  static String getNestedString(Map<String, dynamic> json, List<String> keys, [String defaultValue = '']) {
    dynamic current = json;
    
    for (String key in keys) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return defaultValue;
      }
    }
    
    return current as String? ?? defaultValue;
  }
  
  /// Safely extracts nested integer value with null-safe default
  static int getNestedInt(Map<String, dynamic> json, List<String> keys, [int defaultValue = 0]) {
    dynamic current = json;
    
    for (String key in keys) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return defaultValue;
      }
    }
    
    return current as int? ?? defaultValue;
  }
  
  /// Extracts image URL from Spotify images array format
  /// Common pattern: json['images'][0]['url'] with null safety
  static String? getSpotifyImageUrl(Map<String, dynamic> json, [String key = 'images']) {
    final images = json[key];
    if (images is List && images.isNotEmpty) {
      final firstImage = images[0];
      if (firstImage is Map<String, dynamic>) {
        return firstImage['url'] as String?;
      }
    }
    return null;
  }
  
  /// Extracts list of strings with null safety
  static List<String> getStringList(Map<String, dynamic> json, String key) {
    final list = json[key];
    if (list is List) {
      return list.map((item) => item as String? ?? '').where((item) => item.isNotEmpty).toList();
    }
    return [];
  }
  
  /// Extracts artist names and URIs from Spotify artist array
  /// Returns a record with names and URIs lists
  static ({List<String> names, List<String> uris}) getSpotifyArtists(Map<String, dynamic> json) {
    List<String> names = [];
    List<String> uris = [];
    
    if (json['artists'] is List) {
      final artistsList = json['artists'] as List;
      names = artistsList.map((artist) {
        if (artist is Map<String, dynamic>) {
          return artist['name'] as String? ?? 'Unknown Artist';
        }
        return 'Unknown Artist';
      }).toList();
      
      uris = artistsList.map((artist) {
        if (artist is Map<String, dynamic>) {
          return artist['uri'] as String? ?? '';
        }
        return '';
      }).where((uri) => uri.isNotEmpty).toList();
    } else if (json['artist'] != null) {
      final artist = json['artist'];
      if (artist is Map<String, dynamic>) {
        names = [artist['name'] as String? ?? 'Unknown Artist'];
        final artistUri = artist['uri'] as String?;
        if (artistUri != null && artistUri.isNotEmpty) {
          uris = [artistUri];
        }
      }
    }
    
    return (names: names, uris: uris);
  }
  
  /// Parses DateTime from various string formats with null safety
  static DateTime? getDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    return null;
  }
  
  /// Validates required fields are present in JSON
  static void validateRequiredFields(Map<String, dynamic> json, List<String> requiredFields) {
    final missing = requiredFields.where((field) => !json.containsKey(field) || json[field] == null).toList();
    if (missing.isNotEmpty) {
      throw ArgumentError('Missing required fields: ${missing.join(', ')}');
    }
  }
}