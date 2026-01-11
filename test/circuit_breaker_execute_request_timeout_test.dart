import 'dart:async';
import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreaker.executeRequest Timeout Handling', () {
    test('wraps TimeoutException in CircuitBreakerTimeoutException', () {
      fakeAsync((FakeAsync async) {
        // Create a MockClient that delays longer than the request timeout
        final MockClient client = MockClient((Request request) async {
          await Future<void>.delayed(const Duration(seconds: 10));
          return Response('ok', 200);
        });

        final CircuitBreaker cb = CircuitBreaker(
          client: client,
          requestTimeout: const Duration(seconds: 1),
        );

        final Request request = Request('GET', Uri.parse('https://example.com'));

        Object? caughtError;
        cb.executeRequest(request).catchError((Object e) {
          caughtError = e;
          // Return a dummy response to satisfy the future type if needed, 
          // though catchError result is ignored here since we check caughtError variable.
          return StreamedResponse(const Stream<List<int>>.empty(), 500); 
        });

        // Advance time past requestTimeout (1s) but before mock client response (10s)
        async.elapse(const Duration(seconds: 2));

        expect(caughtError, isA<CircuitBreakerTimeoutException>());
        
        final CircuitBreakerTimeoutException timeoutError = caughtError as CircuitBreakerTimeoutException;
        expect(timeoutError.timeout, equals(const Duration(seconds: 1)));
        expect(timeoutError.message, 'Request timed out');

        // Verify failure metrics were recorded
        expect(cb.failureCount, 1);
        expect(cb.metrics.totalFailures, 1);
      });
    });

    test('calls fallback when TimeoutException occurs and fallback is provided', () {
      fakeAsync((FakeAsync async) {
        final MockClient client = MockClient((Request request) async {
          await Future<void>.delayed(const Duration(seconds: 10));
          return Response('ok', 200);
        });

        final CircuitBreaker cbWithFallback = CircuitBreaker(
          client: client,
          requestTimeout: const Duration(seconds: 1),
          fallback: (BaseRequest req, Object? err) async {
             // Verify that the error passed to fallback is indeed the TimeoutException (or wrapped)
             // The implementation catches TimeoutException then throws CircuitBreakerTimeoutException.
             // Then the outer catch catches it and calls fallback.
             // Wait, the catch block:
             /*
               } catch (e) {
                 // ... _onFailure ...
                 if (fallback != null) { ... return fallback(...) }
                 if (e is TimeoutException) { throw ... }
               }
             */
             // The catch catches the exception from `_executeWithRetry`.
             // `_executeWithRetry` awaits `_client.send().timeout()`.
             // So `timeout()` throws `TimeoutException`.
             // The catch block catches `TimeoutException`.
             // It calls `_onFailure`.
             // THEN it checks `fallback`.
             // If fallback exists, it calls it with `e` (which is `TimeoutException`).
             // It does NOT wrap it in `CircuitBreakerTimeoutException` BEFORE calling fallback.
             // It wraps it AFTER checking fallback, if fallback is null.
             
             // Let's verify this behavior.
             return StreamedResponse(const Stream<List<int>>.empty(), 503);
          }
        );

        final Request request = Request('GET', Uri.parse('https://example.com'));
        StreamedResponse? fallbackResult;
        cbWithFallback.executeRequest(request).then((StreamedResponse r) {
            fallbackResult = r;
        });

        async.elapse(const Duration(seconds: 2));

        expect(fallbackResult, isNotNull);
        expect(fallbackResult!.statusCode, 503);
        expect(cbWithFallback.metrics.totalFallbacks, 1);
      });
    });
  });
}
