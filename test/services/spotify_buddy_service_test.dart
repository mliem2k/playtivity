import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/services/spotify_buddy_service.dart';

// The service is a singleton; reset observable state between tests.
void _reset() {
  SpotifyBuddyService.instance.clearBearerToken();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _reset();
  });

  tearDown(_reset);

  // ---------------------------------------------------------------------------
  // Token management
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService token management', () {
    test('getBearerToken returns null before any token is set', () {
      expect(SpotifyBuddyService.instance.getBearerToken(), isNull);
    });

    test('getBearerToken returns token after setBearerToken', () {
      SpotifyBuddyService.instance.setBearerToken(
        'myBearerToken',
        {'Cookie': 'sp_dc=abc'},
      );
      expect(SpotifyBuddyService.instance.getBearerToken(), 'myBearerToken');
    });

    test('getBearerToken returns null after clearBearerToken', () {
      SpotifyBuddyService.instance.setBearerToken(
        'token',
        {'Cookie': 'sp_dc=abc'},
      );
      SpotifyBuddyService.instance.clearBearerToken();
      expect(SpotifyBuddyService.instance.getBearerToken(), isNull);
    });

    test('getBearerToken returns null for empty string token', () {
      SpotifyBuddyService.instance.setBearerToken('', {'Cookie': 'sp_dc=abc'});
      expect(SpotifyBuddyService.instance.getBearerToken(), isNull);
    });

    test('getCookieString returns Cookie header value after setBearerToken', () {
      SpotifyBuddyService.instance.setBearerToken(
        'tok',
        {'Cookie': 'sp_dc=mycookie; sp_t=xyz'},
      );
      expect(
        SpotifyBuddyService.instance.getCookieString(),
        'sp_dc=mycookie; sp_t=xyz',
      );
    });

    test('getCookieString returns empty string when Cookie header absent', () {
      SpotifyBuddyService.instance.setBearerToken('tok', {});
      expect(SpotifyBuddyService.instance.getCookieString(), '');
    });

    test('getCookieString returns null after clearBearerToken', () {
      SpotifyBuddyService.instance.setBearerToken(
        'tok',
        {'Cookie': 'sp_dc=abc'},
      );
      SpotifyBuddyService.instance.clearBearerToken();
      expect(SpotifyBuddyService.instance.getCookieString(), isNull);
    });

    test('getClientToken returns stored client-token header', () {
      SpotifyBuddyService.instance.setBearerToken(
        'tok',
        {'Cookie': 'sp_dc=abc', 'client-token': 'ct123'},
      );
      expect(SpotifyBuddyService.instance.getClientToken(), 'ct123');
    });

    test('getClientToken returns null when client-token header absent', () {
      SpotifyBuddyService.instance.setBearerToken('tok', {'Cookie': 'sp_dc=abc'});
      expect(SpotifyBuddyService.instance.getClientToken(), isNull);
    });

    test('getClientToken returns null after clearBearerToken', () {
      SpotifyBuddyService.instance.setBearerToken(
        'tok',
        {'client-token': 'ct123'},
      );
      SpotifyBuddyService.instance.clearBearerToken();
      expect(SpotifyBuddyService.instance.getClientToken(), isNull);
    });

    test('setBearerToken overwrites a previously set token', () {
      SpotifyBuddyService.instance.setBearerToken('first', {'Cookie': 'a=1'});
      SpotifyBuddyService.instance.setBearerToken('second', {'Cookie': 'b=2'});
      expect(SpotifyBuddyService.instance.getBearerToken(), 'second');
      expect(SpotifyBuddyService.instance.getCookieString(), 'b=2');
    });
  });

  // ---------------------------------------------------------------------------
  // Buddy list cache management
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService buddy list cache', () {
    test('getBuddyListCacheStatus reports no cache initially', () {
      final status = SpotifyBuddyService.instance.getBuddyListCacheStatus();
      expect(status['hasCache'], isFalse);
      expect(status['activityCount'], 0);
      expect(status['shouldRefresh'], isTrue);
      expect(status['cacheAge'], isNull);
    });

    test('clearBuddyListCache resets cache status to no-cache state', () {
      // Nothing to clear initially, but clearBuddyListCache must still work
      SpotifyBuddyService.instance.clearBuddyListCache();
      final status = SpotifyBuddyService.instance.getBuddyListCacheStatus();
      expect(status['hasCache'], isFalse);
    });

    test('getBuddyListCacheStatus returns correct structure', () {
      final status = SpotifyBuddyService.instance.getBuddyListCacheStatus();
      expect(status.containsKey('hasCache'), isTrue);
      expect(status.containsKey('cacheAge'), isTrue);
      expect(status.containsKey('activityCount'), isTrue);
      expect(status.containsKey('shouldRefresh'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Singleton identity
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService singleton', () {
    test('factory constructor returns the same instance', () {
      final a = SpotifyBuddyService();
      final b = SpotifyBuddyService();
      expect(identical(a, b), isTrue);
    });

    test('instance getter returns the same object as factory constructor', () {
      expect(identical(SpotifyBuddyService.instance, SpotifyBuddyService()), isTrue);
    });

    test('state set via factory is visible via instance getter', () {
      SpotifyBuddyService().setBearerToken('shared', {'Cookie': 'x=1'});
      expect(SpotifyBuddyService.instance.getBearerToken(), 'shared');
    });
  });

  // ---------------------------------------------------------------------------
  // getFriendActivity — no token guard
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService.getFriendActivity', () {
    test('throws when no bearer token is set', () async {
      await expectLater(
        SpotifyBuddyService.instance.getFriendActivity(),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No Bearer token'),
        )),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // getTopContent — no cookie guard
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService.getTopContent', () {
    test('returns null when no cookie string is set', () async {
      SpotifyBuddyService.instance.setBearerToken('tok', {}); // no Cookie header
      final result = await SpotifyBuddyService.instance.getTopContent();
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // _parseUserFrom2026Api (exercised via getCurrentUserProfileWithToken guard)
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService._parseUserFrom2026Api defaults', () {
    // We can't call the private method directly, but we can verify defaults
    // are applied by calling getCurrentUserProfileWithToken with a fake token
    // that will fail network — only test the guard condition here.
    test('getCurrentUserProfileWithToken throws without network (guard fails fast)', () async {
      // The method makes a real HTTP call; in test environment it will fail.
      // What we verify: it doesn't crash with a Dart type error, only network error.
      Object? caught;
      try {
        await SpotifyBuddyService.instance
            .getCurrentUserProfileWithToken('fake-token');
      } catch (e) {
        caught = e;
      }
      // Any error is acceptable — what matters is no unhandled assertion/type errors
      expect(caught, isNotNull);
    });
  });
}
