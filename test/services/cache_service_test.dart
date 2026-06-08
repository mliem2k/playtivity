import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/services/cache_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CacheService.saveJson / loadJson', () {
    test('round-trips a JSON map', () async {
      final data = {'name': 'Alice', 'score': 42};
      final saved = await CacheService.saveJson('myKey', data);
      expect(saved, isTrue);

      final loaded = await CacheService.loadJson('myKey');
      expect(loaded, equals(data));
    });

    test('returns null for missing key', () async {
      final loaded = await CacheService.loadJson('nonexistent');
      expect(loaded, isNull);
    });

    test('overwrites existing entry with new data', () async {
      await CacheService.saveJson('k', {'v': 1});
      await CacheService.saveJson('k', {'v': 2});
      final loaded = await CacheService.loadJson('k');
      expect(loaded!['v'], 2);
    });

    test('round-trips nested structures', () async {
      final nested = {
        'user': {'id': 'u1', 'tags': ['a', 'b']},
        'count': 3,
      };
      await CacheService.saveJson('nested', nested);
      final loaded = await CacheService.loadJson('nested');
      expect(loaded, equals(nested));
    });

    test('uses prefixed key — does not conflict with bare key', () async {
      // Seed bare key directly in prefs
      SharedPreferences.setMockInitialValues({'myKey': '{"direct": true}'});
      // CacheService uses prefix 'playtivity_cache_myKey', so this is distinct
      final loaded = await CacheService.loadJson('myKey');
      expect(loaded, isNull);
    });

    test('returns null when stored value is corrupt JSON', () async {
      SharedPreferences.setMockInitialValues({
        'playtivity_cache_bad': 'not-valid-json{{{',
      });
      final loaded = await CacheService.loadJson('bad');
      expect(loaded, isNull);
    });
  });

  group('CacheService.saveString / loadString', () {
    test('round-trips a plain string', () async {
      await CacheService.saveString('token', 'Bearer abc123');
      final loaded = await CacheService.loadString('token');
      expect(loaded, 'Bearer abc123');
    });

    test('returns null for missing key', () async {
      final loaded = await CacheService.loadString('absent');
      expect(loaded, isNull);
    });

    test('overwrites existing string', () async {
      await CacheService.saveString('s', 'first');
      await CacheService.saveString('s', 'second');
      expect(await CacheService.loadString('s'), 'second');
    });

    test('persists empty string', () async {
      await CacheService.saveString('empty', '');
      final loaded = await CacheService.loadString('empty');
      expect(loaded, '');
    });
  });

  group('CacheService.remove', () {
    test('removes a key that was set', () async {
      await CacheService.saveString('del', 'value');
      await CacheService.remove('del');
      expect(await CacheService.loadString('del'), isNull);
    });

    test('does not throw when key does not exist', () async {
      // Should complete without error
      await expectLater(CacheService.remove('ghost'), completes);
    });

    test('does not affect sibling keys', () async {
      await CacheService.saveString('a', 'alpha');
      await CacheService.saveString('b', 'beta');
      await CacheService.remove('a');
      expect(await CacheService.loadString('b'), 'beta');
    });
  });

  group('CacheService.clear', () {
    test('removes all playtivity-prefixed keys', () async {
      await CacheService.saveString('x', 'val1');
      await CacheService.saveJson('y', {'foo': 'bar'});
      await CacheService.clear();
      expect(await CacheService.loadString('x'), isNull);
      expect(await CacheService.loadJson('y'), isNull);
    });

    test('does not remove non-playtivity keys', () async {
      // Seed a non-prefixed key directly
      SharedPreferences.setMockInitialValues({'other_key': 'preserve-me'});
      await CacheService.saveString('mine', 'val');
      await CacheService.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('other_key'), 'preserve-me');
    });

    test('returns true on success', () async {
      final result = await CacheService.clear();
      expect(result, isTrue);
    });

    test('cache is empty after clear — subsequent load returns null', () async {
      await CacheService.saveJson('data', {'items': [1, 2, 3]});
      await CacheService.clear();
      expect(await CacheService.loadJson('data'), isNull);
    });
  });
}
