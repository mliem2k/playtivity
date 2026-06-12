import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/services/debounced_refresh_service.dart';

void main() {
  tearDown(() {
    DebouncedRefreshService.cancelAll();
  });

  group('DebouncedRefreshService.debounce', () {
    test('fires callback after the specified delay', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.debounce(
          'test',
          const Duration(milliseconds: 200),
          () => fired++,
        );
        expect(fired, 0);
        fake.elapse(const Duration(milliseconds: 200));
        expect(fired, 1);
      });
    });

    test('does not fire before the delay expires', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.debounce(
          'early',
          const Duration(milliseconds: 300),
          () => fired++,
        );
        fake.elapse(const Duration(milliseconds: 299));
        expect(fired, 0);
        fake.elapse(const Duration(milliseconds: 1));
        expect(fired, 1);
      });
    });

    test('cancels previous timer when called again for the same key', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.debounce(
          'dbl',
          const Duration(milliseconds: 200),
          () => fired++,
        );
        fake.elapse(const Duration(milliseconds: 100)); // halfway
        // Second call resets the timer
        DebouncedRefreshService.debounce(
          'dbl',
          const Duration(milliseconds: 200),
          () => fired++,
        );
        fake.elapse(const Duration(milliseconds: 200));
        // Only the second callback fires, and only once
        expect(fired, 1);
      });
    });

    test('different keys are independent', () {
      fakeAsync((fake) {
        int firedA = 0;
        int firedB = 0;
        DebouncedRefreshService.debounce(
          'keyA',
          const Duration(milliseconds: 100),
          () => firedA++,
        );
        DebouncedRefreshService.debounce(
          'keyB',
          const Duration(milliseconds: 200),
          () => firedB++,
        );
        fake.elapse(const Duration(milliseconds: 100));
        expect(firedA, 1);
        expect(firedB, 0);
        fake.elapse(const Duration(milliseconds: 100));
        expect(firedA, 1);
        expect(firedB, 1);
      });
    });

    test('executeImmediately fires right away on first call', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.debounce(
          'imm',
          const Duration(milliseconds: 500),
          () => fired++,
          executeImmediately: true,
        );
        // Should execute synchronously before any time elapses
        fake.flushMicrotasks();
        expect(fired, 1);
      });
    });

    test('executeImmediately defers if called again within the delay', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.debounce(
          'imm2',
          const Duration(milliseconds: 500),
          () => fired++,
          executeImmediately: true,
        );
        fake.flushMicrotasks();
        expect(fired, 1);

        // Second call within 500ms should be debounced, not immediate
        DebouncedRefreshService.debounce(
          'imm2',
          const Duration(milliseconds: 500),
          () => fired++,
          executeImmediately: true,
        );
        fake.flushMicrotasks();
        expect(fired, 1); // still 1, debounced

        fake.elapse(const Duration(milliseconds: 500));
        expect(fired, 2); // now fires
      });
    });
  });

  group('DebouncedRefreshService.throttle', () {
    test('executes immediately on first call', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.throttle(
          'thr',
          const Duration(milliseconds: 500),
          () => fired++,
        );
        fake.flushMicrotasks();
        expect(fired, 1);
      });
    });

    test('does not execute again before interval expires', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.throttle('t', const Duration(milliseconds: 500), () => fired++);
        fake.flushMicrotasks();
        DebouncedRefreshService.throttle('t', const Duration(milliseconds: 500), () => fired++);
        fake.flushMicrotasks();
        expect(fired, 1);
      });
    });

    test('executes again after interval expires', () {
      // fakeAsync controls Timer but not DateTime.now(), so the deferred timer
      // is set for the full interval (500ms) regardless of elapsed fake time.
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.throttle('t2', const Duration(milliseconds: 500), () => fired++);
        fake.elapse(const Duration(milliseconds: 500));
        // Second call: DateTime.now() hasn't advanced (real time ≈ same), so it
        // creates a deferred timer for the full interval again.
        DebouncedRefreshService.throttle('t2', const Duration(milliseconds: 500), () => fired++);
        expect(fired, 1); // not fired yet
        fake.elapse(const Duration(milliseconds: 500)); // allow deferred timer to fire
        expect(fired, 2);
      });
    });

    test('schedules deferred execution for second call within interval', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.throttle('t3', const Duration(milliseconds: 500), () => fired++);
        fake.elapse(const Duration(milliseconds: 100));
        DebouncedRefreshService.throttle('t3', const Duration(milliseconds: 500), () => fired++);
        // Deferred timer fires after ≈500ms fake time (full interval since
        // DateTime.now() is not under fakeAsync control)
        fake.elapse(const Duration(milliseconds: 500));
        expect(fired, 2);
      });
    });

    test('does not schedule multiple deferred timers for same key', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.throttle('t4', const Duration(milliseconds: 500), () => fired++);
        fake.elapse(const Duration(milliseconds: 100));
        // Multiple calls within interval — only one deferred timer should be set
        DebouncedRefreshService.throttle('t4', const Duration(milliseconds: 500), () => fired++);
        DebouncedRefreshService.throttle('t4', const Duration(milliseconds: 500), () => fired++);
        fake.elapse(const Duration(milliseconds: 500));
        expect(fired, 2); // 1 immediate + 1 deferred
      });
    });
  });

  group('DebouncedRefreshService.cancel', () {
    test('prevents pending debounce from firing', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.debounce('c', const Duration(milliseconds: 200), () => fired++);
        DebouncedRefreshService.cancel('c');
        fake.elapse(const Duration(milliseconds: 300));
        expect(fired, 0);
      });
    });

    test('does not throw when key is not pending', () {
      fakeAsync((fake) {
        expect(() => DebouncedRefreshService.cancel('ghost'), returnsNormally);
      });
    });

    test('isPending returns false after cancel', () {
      fakeAsync((fake) {
        DebouncedRefreshService.debounce('p', const Duration(milliseconds: 200), () {});
        expect(DebouncedRefreshService.isPending('p'), isTrue);
        DebouncedRefreshService.cancel('p');
        expect(DebouncedRefreshService.isPending('p'), isFalse);
      });
    });
  });

  group('DebouncedRefreshService.cancelAll', () {
    test('cancels all pending operations', () {
      fakeAsync((fake) {
        int fired = 0;
        DebouncedRefreshService.debounce('a', const Duration(milliseconds: 200), () => fired++);
        DebouncedRefreshService.debounce('b', const Duration(milliseconds: 200), () => fired++);
        DebouncedRefreshService.cancelAll();
        fake.elapse(const Duration(milliseconds: 300));
        expect(fired, 0);
      });
    });

    test('pendingOperationsCount is 0 after cancelAll', () {
      fakeAsync((fake) {
        DebouncedRefreshService.debounce('x', const Duration(milliseconds: 200), () {});
        DebouncedRefreshService.debounce('y', const Duration(milliseconds: 200), () {});
        expect(DebouncedRefreshService.pendingOperationsCount, 2);
        DebouncedRefreshService.cancelAll();
        expect(DebouncedRefreshService.pendingOperationsCount, 0);
      });
    });
  });

  group('DebouncedRefreshService state helpers', () {
    test('isPending is true while timer is outstanding', () {
      fakeAsync((fake) {
        DebouncedRefreshService.debounce('s', const Duration(milliseconds: 200), () {});
        expect(DebouncedRefreshService.isPending('s'), isTrue);
        fake.elapse(const Duration(milliseconds: 200));
        expect(DebouncedRefreshService.isPending('s'), isFalse);
      });
    });

    test('isPending is false for unknown key', () {
      expect(DebouncedRefreshService.isPending('unknown'), isFalse);
    });

    test('pendingOperationsCount reflects active timers', () {
      fakeAsync((fake) {
        expect(DebouncedRefreshService.pendingOperationsCount, 0);
        DebouncedRefreshService.debounce('p1', const Duration(milliseconds: 200), () {});
        expect(DebouncedRefreshService.pendingOperationsCount, 1);
        DebouncedRefreshService.debounce('p2', const Duration(milliseconds: 200), () {});
        expect(DebouncedRefreshService.pendingOperationsCount, 2);
        fake.elapse(const Duration(milliseconds: 200));
        expect(DebouncedRefreshService.pendingOperationsCount, 0);
      });
    });
  });

  group('DebounceKeys constants', () {
    test('all keys are non-empty strings', () {
      final keys = [
        DebounceKeys.activitiesRefresh,
        DebounceKeys.profileRefresh,
        DebounceKeys.manualRefresh,
        DebounceKeys.searchQuery,
        DebounceKeys.apiCall,
        DebounceKeys.cacheRefresh,
        DebounceKeys.activityEnhancement,
        DebounceKeys.friendsActivities,
        DebounceKeys.currentlyPlaying,
      ];
      for (final key in keys) {
        expect(key, isNotEmpty, reason: 'DebounceKeys.$key should not be empty');
      }
    });

    test('all keys are unique', () {
      final keys = [
        DebounceKeys.activitiesRefresh,
        DebounceKeys.profileRefresh,
        DebounceKeys.manualRefresh,
        DebounceKeys.searchQuery,
        DebounceKeys.apiCall,
        DebounceKeys.cacheRefresh,
        DebounceKeys.activityEnhancement,
        DebounceKeys.friendsActivities,
        DebounceKeys.currentlyPlaying,
      ];
      expect(keys.toSet().length, keys.length);
    });
  });
}
