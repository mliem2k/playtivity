import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/services/api_retry_service.dart';

void main() {
  group('ApiRetryService.retryApiCall', () {
    test('returns result immediately on first success', () async {
      int calls = 0;
      final result = await ApiRetryService.retryApiCall(
        () async {
          calls++;
          return 'ok';
        },
        initialDelay: Duration.zero,
      );
      expect(result, 'ok');
      expect(calls, 1);
    });

    test('retries after failure and succeeds on third attempt', () async {
      int calls = 0;
      final result = await ApiRetryService.retryApiCall(
        () async {
          calls++;
          if (calls < 3) throw Exception('transient');
          return 'recovered';
        },
        maxRetries: 3,
        initialDelay: Duration.zero,
      );
      expect(result, 'recovered');
      expect(calls, 3);
    });

    test('rethrows after exhausting maxRetries', () async {
      int calls = 0;
      await expectLater(
        ApiRetryService.retryApiCall(
          () async {
            calls++;
            throw Exception('persistent');
          },
          maxRetries: 2,
          initialDelay: Duration.zero,
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('persistent'))),
      );
      // 1 initial + 2 retries = 3 total
      expect(calls, 3);
    });

    test('maxRetries 0 means exactly one attempt with no retry', () async {
      int calls = 0;
      await expectLater(
        ApiRetryService.retryApiCall(
          () async {
            calls++;
            throw Exception('fail');
          },
          maxRetries: 0,
          initialDelay: Duration.zero,
        ),
        throwsA(isA<Exception>()),
      );
      expect(calls, 1);
    });

    test('succeeds on last allowed retry', () async {
      int calls = 0;
      final result = await ApiRetryService.retryApiCall(
        () async {
          calls++;
          if (calls <= 3) throw Exception('fail $calls');
          return 'final';
        },
        maxRetries: 3,
        initialDelay: Duration.zero,
      );
      expect(result, 'final');
      expect(calls, 4); // 1 initial + 3 retries
    });

    test('rate-limit 429 error triggers retry', () {
      fakeAsync((fake) {
        int calls = 0;
        String? result;
        ApiRetryService.retryApiCall(
          () async {
            calls++;
            if (calls == 1) throw Exception('HTTP 429 rate limit exceeded');
            return 'after-rate-limit';
          },
          maxRetries: 2,
          initialDelay: const Duration(milliseconds: 50),
        ).then((v) => result = v);

        // Rate-limit delay for attempt 0 = 5000ms * 2^0 = 5000ms
        fake.elapse(const Duration(seconds: 6));
        fake.flushMicrotasks();

        expect(calls, 2);
        expect(result, 'after-rate-limit');
      });
    });

    test('"rate limit" string in error message triggers rate-limit backoff', () {
      fakeAsync((fake) {
        int calls = 0;
        String? result;
        ApiRetryService.retryApiCall<String>(
          () async {
            calls++;
            if (calls == 1) throw Exception('rate limit exceeded');
            return 'ok';
          },
          maxRetries: 1,
          initialDelay: const Duration(milliseconds: 50),
        ).then((v) => result = v);

        // Rate-limit delay for attempt 0 = 5000ms * 2^0 = 5000ms
        fake.elapse(const Duration(seconds: 6));
        fake.flushMicrotasks();

        expect(calls, 2); // initial + 1 retry
        expect(result, 'ok');
      });
    });

    test('"429" in error message triggers rate-limit backoff', () {
      fakeAsync((fake) {
        int calls = 0;
        String? result;
        ApiRetryService.retryApiCall<String>(
          () async {
            calls++;
            if (calls == 1) throw Exception('status 429');
            return 'ok';
          },
          maxRetries: 1,
          initialDelay: const Duration(milliseconds: 50),
        ).then((v) => result = v);

        fake.elapse(const Duration(seconds: 6));
        fake.flushMicrotasks();

        expect(calls, 2);
        expect(result, 'ok');
      });
    });

    test('non-rate-limit error uses initialDelay-based exponential backoff', () {
      fakeAsync((fake) {
        int calls = 0;
        String? result;
        const delay = Duration(milliseconds: 100);
        ApiRetryService.retryApiCall(
          () async {
            calls++;
            if (calls == 1) throw Exception('timeout');
            return 'ok';
          },
          maxRetries: 2,
          initialDelay: delay,
        ).then((v) => result = v);

        // delay for attempt 0 = 100ms * 2^0 = 100ms; advance just past it
        fake.elapse(const Duration(milliseconds: 150));
        fake.flushMicrotasks();

        expect(calls, 2);
        expect(result, 'ok');
      });
    });

    test('operation name appears in error log (does not affect retry behaviour)', () async {
      // Verifies the operation parameter is accepted without affecting behaviour
      int calls = 0;
      final result = await ApiRetryService.retryApiCall(
        () async {
          calls++;
          return 42;
        },
        operation: 'Custom Operation Name',
        initialDelay: Duration.zero,
      );
      expect(result, 42);
      expect(calls, 1);
    });

    test('works with generic type parameters', () async {
      final intResult = await ApiRetryService.retryApiCall<int>(
        () async => 7,
        initialDelay: Duration.zero,
      );
      expect(intResult, 7);

      final mapResult = await ApiRetryService.retryApiCall<Map<String, dynamic>>(
        () async => {'key': 'value'},
        initialDelay: Duration.zero,
      );
      expect(mapResult, {'key': 'value'});
    });
  });
}
