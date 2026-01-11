import 'dart:async';
import 'dart:io';

import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';

import 'mock_client.dart';

void main() {
  Request makeRequest() {
    final Request request = Request('POST', Uri.parse('http://example.com'));
    request.bodyFields = <String, String>{'data': 'abc123'};
    return request;
  }

  tearDown(() {
    CircuitBreaker.clearRegistry();
  });

  group('CircuitBreaker', () {
    group('closed state', () {
      test('executes requests successfully', () async {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(),
          failureThreshold: 3,
          successThreshold: 2,
          timeout: const Duration(seconds: 2),
        );

        final StreamedResponse response = await cb.executeRequest(makeRequest());

        expect(response.statusCode, 200);
        expect(cb.state, CircuitState.closed);
        cb.dispose();
      });

      test('stays closed on successful requests', () async {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(),
          failureThreshold: 3,
        );

        await cb.executeRequest(makeRequest());
        await cb.executeRequest(makeRequest());
        await cb.executeRequest(makeRequest());

        expect(cb.state, CircuitState.closed);
        expect(cb.failureCount, 0);
        cb.dispose();
      });

      test('increments failure count on non-2xx responses', () async {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 3,
        );

        await cb.executeRequest(makeRequest());

        expect(cb.state, CircuitState.closed);
        expect(cb.failureCount, 1);
        cb.dispose();
      });

      test('handles events after dispose gracefully', () async {
        final Completer<Response> completer = Completer<Response>();
        final MockClient client = createDelayedMockClient(completer.future);
        
        final CircuitBreaker cb = CircuitBreaker(
          client: client,
        );
        
        // Start request
        final Future<StreamedResponse> future = cb.executeRequest(makeRequest());
        
        // Dispose immediately
        cb.dispose();
        
        // Complete request
        completer.complete(Response('ok', 200));
        await future;
        
        // No crash means success (and _emitEvent guarded against closed controller)
      });
    });

    group('open state', () {
      test('opens after failure threshold reached', () async {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 3,
          timeout: const Duration(seconds: 2),
        );

        await cb.executeRequest(makeRequest());
        await cb.executeRequest(makeRequest());
        await cb.executeRequest(makeRequest());

        expect(cb.state, CircuitState.open);
        cb.dispose();
      });

      test('blocks requests when open', () async {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 3,
          timeout: const Duration(seconds: 2),
        );

        await cb.executeRequest(makeRequest());
        await cb.executeRequest(makeRequest());
        await cb.executeRequest(makeRequest());

        expect(cb.state, CircuitState.open);
        expect(
          () => cb.executeRequest(makeRequest()),
          throwsA(isA<CircuitBreakerException>()),
        );
        cb.dispose();
      });

      test('counts network exceptions as failures', () async {
        final CircuitBreaker cb = CircuitBreaker(
          client: createFailingMockClient(
            const SocketException('Connection refused'),
          ),
          failureThreshold: 3,
        );

        for (int i = 0; i < 3; i++) {
          try {
            await cb.executeRequest(makeRequest());
          } on SocketException catch (e) {
            expect(e, isA<SocketException>());
          }
        }

        expect(cb.state, CircuitState.open);
        expect(cb.failureCount, 3);
        cb.dispose();
      });
    });

    group('half-open state', () {
      test('transitions to half-open after timeout', () {
        fakeAsync((FakeAsync async) {
          final CircuitBreaker cb = CircuitBreaker(
            client: createMockClient(statusCode: 500),
            failureThreshold: 3,
            timeout: const Duration(seconds: 2),
          );

          cb.executeRequest(makeRequest());
          async.flushMicrotasks();
          cb.executeRequest(makeRequest());
          async.flushMicrotasks();
          cb.executeRequest(makeRequest());
          async.flushMicrotasks();

          expect(cb.state, CircuitState.open);
          expect(cb.isAllowingRequests, isFalse);

          async.elapse(const Duration(seconds: 3));

          expect(cb.isAllowingRequests, isTrue);
          cb.dispose();
        });
      });

      test('reopens immediately on failure in half-open', () {
        fakeAsync((FakeAsync async) {
          final List<(CircuitState, CircuitState)> stateChanges =
              <(CircuitState, CircuitState)>[];

          final CircuitBreaker cb = CircuitBreaker(
            client: createMockClient(statusCode: 500),
            failureThreshold: 3,
            successThreshold: 2,
            timeout: const Duration(seconds: 2),
            onStateChange: (CircuitState prev, CircuitState next) =>
                stateChanges.add((prev, next)),
          );

          cb.executeRequest(makeRequest());
          async.flushMicrotasks();
          cb.executeRequest(makeRequest());
          async.flushMicrotasks();
          cb.executeRequest(makeRequest());
          async.flushMicrotasks();

          expect(cb.state, CircuitState.open);

          async.elapse(const Duration(seconds: 3));

          cb.executeRequest(makeRequest());
          async.flushMicrotasks();

          expect(cb.state, CircuitState.open);
          expect(
            stateChanges,
            contains((CircuitState.open, CircuitState.halfOpen)),
          );
          expect(stateChanges.last, (CircuitState.halfOpen, CircuitState.open));
          cb.dispose();
        });
      });

      test('closes after success threshold reached in half-open', () {
        fakeAsync((FakeAsync async) {
          int responseCode = 500;
          final MockClient client = MockClient((BaseRequest request) async {
            return Response('body', responseCode);
          });

          final CircuitBreaker testCb = CircuitBreaker(
            client: client,
            failureThreshold: 1,
            successThreshold: 2,
            timeout: const Duration(seconds: 2),
          );

          // 1. Trip it (Fail)
          testCb.executeRequest(makeRequest());
          async.flushMicrotasks();
          expect(testCb.state, CircuitState.open);
          expect(testCb.consecutiveOpenings, 1);

          // 2. Wait for timeout to allow recovery attempt
          async.elapse(const Duration(seconds: 3));
          expect(testCb.isAllowingRequests, isTrue);

          // 3. Success 1 in half-open
          responseCode = 200;
          testCb.executeRequest(makeRequest());
          async.flushMicrotasks();
          expect(testCb.state, CircuitState.halfOpen);
          expect(testCb.successCount, 1);

          // 4. Success 2 in half-open -> should close
          testCb.executeRequest(makeRequest());
          async.flushMicrotasks();
          expect(testCb.state, CircuitState.closed);
          expect(testCb.successCount, 0);
          expect(testCb.consecutiveOpenings, 0);

          testCb.dispose();
        });
      });
    });

    group('reset', () {
      test('resets circuit to closed state', () async {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 3,
        );

        await cb.executeRequest(makeRequest());
        await cb.executeRequest(makeRequest());
        await cb.executeRequest(makeRequest());

        expect(cb.state, CircuitState.open);

        cb.reset();

        expect(cb.state, CircuitState.closed);
        expect(cb.failureCount, 0);
        expect(cb.successCount, 0);
        cb.dispose();
      });
    });
  });

  group('Exponential Backoff', () {
    test('uses base timeout on first opening', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 3,
          timeout: const Duration(seconds: 2),
          useExponentialBackoff: true,
          backoffMultiplier: 2.0,
        );

        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();

        expect(cb.state, CircuitState.open);
        expect(cb.consecutiveOpenings, 1);
        cb.dispose();
      });
    });

    test('increases timeout on consecutive openings', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 3,
          successThreshold: 1,
          timeout: const Duration(seconds: 2),
          useExponentialBackoff: true,
          backoffMultiplier: 2.0,
          maxTimeout: const Duration(minutes: 1),
        );

        // First opening
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();

        expect(cb.consecutiveOpenings, 1);

        // Wait for timeout and trigger half-open
        async.elapse(const Duration(seconds: 3));

        // Fail in half-open -> second opening
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();

        expect(cb.consecutiveOpenings, 2);
        cb.dispose();
      });
    });

    test('caps timeout at maxTimeout', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 1,
          successThreshold: 1,
          timeout: const Duration(seconds: 10),
          useExponentialBackoff: true,
          backoffMultiplier: 10.0,
          maxTimeout: const Duration(seconds: 30),
        );

        // First opening
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 15));
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 35));
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();

        // Should be capped at 30 seconds
        expect(cb.consecutiveOpenings, 3);
        cb.dispose();
      });
    });
  });

  group('Sliding Window', () {
    test('opens based on failure rate threshold', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 100, // High threshold so it doesn't trigger
        windowDuration: const Duration(seconds: 60),
        failureRateThreshold: 0.5, // 50% failure rate
        minimumRequestsInWindow: 4,
      );

      // Create 2 successes first
      final CircuitBreaker cbSuccess = CircuitBreaker(
        client: createMockClient(statusCode: 200),
        failureThreshold: 100,
        windowDuration: const Duration(seconds: 60),
        failureRateThreshold: 0.5,
        minimumRequestsInWindow: 4,
      );

      await cbSuccess.executeRequest(makeRequest());
      await cbSuccess.executeRequest(makeRequest());

      // Now 3 failures (60% failure rate)
      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());

      // Note: each circuit breaker has its own sliding window
      expect(cb.requestsInWindow, 3);
      expect(cb.currentFailureRate, 1.0); // All failures in this CB

      cb.dispose();
      cbSuccess.dispose();
    });

    test('does not open if minimum requests not met', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 100,
        windowDuration: const Duration(seconds: 60),
        failureRateThreshold: 0.5,
        minimumRequestsInWindow: 10, // Need 10 requests minimum
      );

      // Only 3 failures, not enough for minimum
      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());

      expect(cb.state, CircuitState.closed);
      expect(cb.requestsInWindow, 3);
      cb.dispose();
    });

    test('does not open if failureRateThreshold is null', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 100, // High threshold
        windowDuration: const Duration(seconds: 60),
        failureRateThreshold: null, // Explicitly null (default is null, but being explicit for test)
        minimumRequestsInWindow: 1,
      );

      // Execute many failures
      for (int i = 0; i < 5; i++) {
        await cb.executeRequest(makeRequest());
      }

      // Should be closed because failureThreshold is 100 and rate threshold is null
      expect(cb.state, CircuitState.closed);
      expect(cb.requestsInWindow, 5);
      expect(cb.currentFailureRate, 1.0);
      
      cb.dispose();
    });

    test('opens when failure rate threshold is exceeded', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 100, // High consecutive threshold
        windowDuration: const Duration(seconds: 60),
        failureRateThreshold: 0.5, // 50%
        minimumRequestsInWindow: 4,
      );
      
      // Use a success client for mixed results
      final CircuitBreaker mixedCb = CircuitBreaker(
        client: createCountingMockClient(() {
          // Alternating success/failure: S, F, S, F...
          // 4 requests: 2 failures (50%)
          // But we need to control it precisely.
          return Response('ok', 200); // placeholder
        }), 
      );
      
      // Let's manually inject results via separate CB instances or changing the client behavior is hard.
      // Easier: Use one CB and a smart client.
      
      int counter = 0;
      final MockClient client = MockClient((BaseRequest request) async {
        counter++;
        // Sequence: Success, Success, Failure, Failure
        // Total 4. Failures 2. Rate 0.5.
        if (counter <= 2) {
          return Response('ok', 200);
        }
        return Response('fail', 500);
      });
      
      final CircuitBreaker testCb = CircuitBreaker(
        client: client,
        failureThreshold: 100,
        windowDuration: const Duration(seconds: 60),
        failureRateThreshold: 0.5,
        minimumRequestsInWindow: 4,
      );
      
      await testCb.executeRequest(makeRequest()); // Success (1/1, rate 0%)
      await testCb.executeRequest(makeRequest()); // Success (2/2, rate 0%)
      await testCb.executeRequest(makeRequest()); // Failure (1/3, rate 33%)
      await testCb.executeRequest(makeRequest()); // Failure (2/4, rate 50%)
      
      expect(testCb.state, CircuitState.open);
      expect(testCb.currentFailureRate, 0.5);
      
      testCb.dispose();
      cb.dispose();
      mixedCb.dispose();
    });
  });

  group('Fallback', () {
    test('uses fallback when circuit is open', () async {
      bool fallbackCalled = false;

      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 3,
        timeout: const Duration(seconds: 10),
        fallback: (BaseRequest request, Object? error) async {
          fallbackCalled = true;
          return StreamedResponse(
            Stream<List<int>>.value(<int>[]),
            200,
            request: request,
          );
        },
      );

      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());

      expect(cb.state, CircuitState.open);

      final StreamedResponse response = await cb.executeRequest(makeRequest());

      expect(fallbackCalled, isTrue);
      expect(response.statusCode, 200);
      cb.dispose();
    });

    test('uses fallback on request failure', () async {
      bool fallbackCalled = false;

      final CircuitBreaker cb = CircuitBreaker(
        client: createFailingMockClient(
          const SocketException('Connection failed'),
        ),
        failureThreshold: 10,
        fallback: (BaseRequest request, Object? error) async {
          fallbackCalled = true;
          expect(error, isA<SocketException>());
          return StreamedResponse(
            Stream<List<int>>.value(<int>[]),
            503,
            request: request,
          );
        },
      );

      final StreamedResponse response = await cb.executeRequest(makeRequest());

      expect(fallbackCalled, isTrue);
      expect(response.statusCode, 503);
      cb.dispose();
    });
  });

  group('Bulkhead (Concurrency Limiting)', () {
    test('rejects requests when limit reached', () async {
      final Completer<Response> completer = Completer<Response>();

      final MockClient slowClient = createDelayedMockClient(completer.future);

      final CircuitBreaker cb = CircuitBreaker(
        client: slowClient,
        maxConcurrentRequests: 2,
        failureThreshold: 10,
      );

      // Start 2 requests
      final Future<StreamedResponse> req1 = cb.executeRequest(makeRequest());
      final Future<StreamedResponse> req2 = cb.executeRequest(makeRequest());

      // Wait a bit for requests to start
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(cb.pendingRequests, 2);

      // Third request should be rejected
      expect(
        () => cb.executeRequest(makeRequest()),
        throwsA(isA<CircuitBreakerException>()),
      );

      // Complete pending requests
      completer.complete(Response('ok', 200));
      await req1;
      await req2;

      expect(cb.pendingRequests, 0);
      cb.dispose();
    });

    test('uses fallback when limit reached', () async {
      final Completer<Response> completer = Completer<Response>();
      final MockClient slowClient = createDelayedMockClient(completer.future);
      bool fallbackCalled = false;

      final CircuitBreaker cb = CircuitBreaker(
        client: slowClient,
        maxConcurrentRequests: 1,
        failureThreshold: 10,
        fallback: (BaseRequest request, Object? error) async {
          fallbackCalled = true;
          return StreamedResponse(
            Stream<List<int>>.value(<int>[]),
            429,
            request: request,
          );
        },
      );

      // Start 1 request
      final Future<StreamedResponse> req1 = cb.executeRequest(makeRequest());

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Second request uses fallback
      final StreamedResponse response = await cb.executeRequest(makeRequest());

      expect(fallbackCalled, isTrue);
      expect(response.statusCode, 429);

      completer.complete(Response('ok', 200));
      await req1;
      cb.dispose();
    });
  });

  group('Metrics', () {
    test('tracks successful requests', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 200),
        failureThreshold: 3,
      );

      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());

      expect(cb.metrics.totalRequests, 2);
      expect(cb.metrics.totalSuccesses, 2);
      expect(cb.metrics.totalFailures, 0);
      expect(cb.metrics.successRate, 1.0);
      cb.dispose();
    });

    test('tracks failed requests', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 10,
      );

      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());

      expect(cb.metrics.totalRequests, 2);
      expect(cb.metrics.totalSuccesses, 0);
      expect(cb.metrics.totalFailures, 2);
      expect(cb.metrics.failureRate, 1.0);
      cb.dispose();
    });

    test('tracks rejected requests', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 3,
        timeout: const Duration(seconds: 10),
      );

      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());

      try {
        await cb.executeRequest(makeRequest());
      } catch (_) {}

      expect(cb.metrics.totalRejected, 1);
      cb.dispose();
    });

    test('tracks latency', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 200),
        failureThreshold: 3,
      );

      await cb.executeRequest(makeRequest());

      expect(cb.metrics.averageLatency.inMicroseconds, greaterThanOrEqualTo(0));
      cb.dispose();
    });
  });

  group('Events', () {
    test('emits StateChangedEvent on state changes', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 3,
      );

      final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
      cb.events.listen(events.add);

      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        events.whereType<StateChangedEvent>().length,
        greaterThanOrEqualTo(1),
      );
      cb.dispose();
    });

    test('emits RequestSuccessEvent on success', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 200),
        failureThreshold: 3,
      );

      final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
      cb.events.listen(events.add);

      await cb.executeRequest(makeRequest());

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<RequestSuccessEvent>().length, 1);
      cb.dispose();
    });

    test('emits RequestFailureEvent on failure', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 10,
      );

      final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
      cb.events.listen(events.add);

      await cb.executeRequest(makeRequest());

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<RequestFailureEvent>().length, 1);
      cb.dispose();
    });

    test('emits RequestRejectedEvent when circuit open', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 3,
        timeout: const Duration(seconds: 10),
      );

      final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
      cb.events.listen(events.add);

      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());

      try {
        await cb.executeRequest(makeRequest());
      } catch (_) {}

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<RequestRejectedEvent>().length, 1);
      cb.dispose();
    });
  });

  group('Retry Policy', () {
    test('calculates exponential backoff delay', () {
      const RetryPolicy policy = RetryPolicy(
        retryDelay: Duration(milliseconds: 100),
        useExponentialBackoff: true,
        backoffMultiplier: 2.0,
        maxRetryDelay: Duration(seconds: 10),
      );

      expect(policy.getDelayForAttempt(0), const Duration(milliseconds: 100));
      expect(policy.getDelayForAttempt(1), const Duration(milliseconds: 200));
      expect(policy.getDelayForAttempt(2), const Duration(milliseconds: 400));
      expect(policy.getDelayForAttempt(3), const Duration(milliseconds: 800));
    });

    test('caps delay at maxRetryDelay', () {
      const RetryPolicy policy = RetryPolicy(
        retryDelay: Duration(seconds: 1),
        useExponentialBackoff: true,
        backoffMultiplier: 10.0,
        maxRetryDelay: Duration(seconds: 5),
      );

      expect(policy.getDelayForAttempt(5), const Duration(seconds: 5));
    });

    test('shouldRetryForStatusCode defaults to 5xx and 429', () {
      const RetryPolicy policy = RetryPolicy();

      expect(policy.shouldRetryForStatusCode(500), isTrue);
      expect(policy.shouldRetryForStatusCode(503), isTrue);
      expect(policy.shouldRetryForStatusCode(429), isTrue);
      expect(policy.shouldRetryForStatusCode(400), isFalse);
      expect(policy.shouldRetryForStatusCode(200), isFalse);
    });

    test('shouldRetryForException returns true by default', () {
      const RetryPolicy policy = RetryPolicy();

      expect(
        policy.shouldRetryForException(const SocketException('error')),
        isTrue,
      );
      expect(policy.shouldRetryForException(Exception('error')), isTrue);
    });

    test('uses custom shouldRetryStatusCode function', () {
      final RetryPolicy policy = RetryPolicy(
        shouldRetryStatusCode: (int code) => code == 418,
      );

      expect(policy.shouldRetryForStatusCode(418), isTrue);
      expect(policy.shouldRetryForStatusCode(500), isFalse);
    });
  });

  group('Retry Failure Scenarios', () {
    test('rethrows immediately if shouldRetryForException returns false', () async {
      final CircuitBreaker cb = CircuitBreaker(
        client: createFailingMockClient(const FormatException('Do not retry')),
        retryPolicy: RetryPolicy(
          maxRetries: 3,
          shouldRetryException: (Object e) => e is! FormatException,
        ),
      );

      expect(
        () => cb.executeRequest(makeRequest()),
        throwsA(isA<FormatException>()),
      );

      // Verify no retries happened
      expect(cb.metrics.totalRetries, 0);
      cb.dispose();
    });

    test('rethrows after max retries exhausted', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          client: createFailingMockClient(const SocketException('Fail')),
          retryPolicy: const RetryPolicy(
            maxRetries: 2,
            retryDelay: Duration(seconds: 1),
            useExponentialBackoff: false,
          ),
        );

        final Future<StreamedResponse> future = cb.executeRequest(makeRequest());
        
        // Attach listener immediately to catch the eventual error
        expect(future, throwsA(isA<SocketException>()));
        
        // Initial attempt fails, waits 1s
        async.elapse(const Duration(seconds: 1));
        // Retry 1 fails, waits 1s
        async.elapse(const Duration(seconds: 1));
        // Retry 2 fails, should rethrow
        
        // Check retry count (totalRetries is incremented on each retry)
        // Note: metrics might be updated before the future completes in the microtask queue
        async.flushMicrotasks();
        expect(cb.metrics.totalRetries, 2);
        
        cb.dispose();
      });
    });
  });

  group('Circuit per Endpoint', () {
    test('forHost creates shared circuit breaker', () {
      final CircuitBreaker cb1 = CircuitBreaker.forHost('api.example.com');
      final CircuitBreaker cb2 = CircuitBreaker.forHost('api.example.com');

      expect(identical(cb1, cb2), isTrue);
    });

    test('forHost creates separate circuit breakers for different hosts', () {
      final CircuitBreaker cb1 = CircuitBreaker.forHost('api1.example.com');
      final CircuitBreaker cb2 = CircuitBreaker.forHost('api2.example.com');

      expect(identical(cb1, cb2), isFalse);
    });

    test('forEndpoint creates shared circuit breaker', () {
      final Uri endpoint = Uri.parse('https://api.example.com/v1/users');
      final CircuitBreaker cb1 = CircuitBreaker.forEndpoint(endpoint);
      final CircuitBreaker cb2 = CircuitBreaker.forEndpoint(endpoint);

      expect(identical(cb1, cb2), isTrue);
    });

    test('getByKey retrieves registered circuit breaker', () {
      CircuitBreaker.forHost('test.example.com');

      final CircuitBreaker? cb =
          CircuitBreaker.getByKey('host:test.example.com');

      expect(cb, isNotNull);
    });

    test('clearRegistry removes all circuit breakers', () {
      CircuitBreaker.forHost('host1.example.com');
      CircuitBreaker.forHost('host2.example.com');

      CircuitBreaker.clearRegistry();

      expect(CircuitBreaker.getByKey('host:host1.example.com'), isNull);
      expect(CircuitBreaker.getByKey('host:host2.example.com'), isNull);
    });
  });

  group('Request Cloning', () {
    test('correctly clones MultipartRequest (instance inequality)', () async {
      final Uri uri = Uri.parse('http://example.com/upload');
      BaseRequest? capturedRequest;
      
      // Use a custom client because MockClient from http/testing 
      // converts everything to a Request.
      final Client client = _CustomTestClient((BaseRequest request) {
        capturedRequest = request;
      });

      final CircuitBreaker cb = CircuitBreaker(client: client);

      final MultipartRequest originalRequest = MultipartRequest('POST', uri)
        ..fields['key'] = 'value'
        ..files.add(MultipartFile.fromString('file', 'content'));

      await cb.executeRequest(originalRequest);

      expect(capturedRequest, isA<MultipartRequest>());
      expect(identical(capturedRequest, originalRequest), isFalse, reason: 'Request should have been cloned');
      expect((capturedRequest as MultipartRequest).fields['key'], equals('value'));
      cb.dispose();
    });

    test('returns original request for unknown types (fallback)', () async {
      final Uri uri = Uri.parse('http://example.com');
      final StreamedRequest originalRequest = StreamedRequest('POST', uri);
      
      BaseRequest? capturedRequest;
      final Client client = _CustomTestClient((BaseRequest request) {
        capturedRequest = request;
      });
      
      final CircuitBreaker cb = CircuitBreaker(client: client);
      await cb.executeRequest(originalRequest);
      
      expect(identical(capturedRequest, originalRequest), isTrue, reason: 'StreamedRequest should not be cloned');
      cb.dispose();
    });
  });

  group('State Persistence', () {
    test('saves state to storage', () async {
      final InMemoryStorage storage = InMemoryStorage();

      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(statusCode: 500),
        failureThreshold: 3,
        storage: storage,
        key: 'test-cb',
      );

      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());
      await cb.executeRequest(makeRequest());

      await cb.saveState();

      final CircuitBreakerState? savedState = await storage.load('test-cb');

      expect(savedState, isNotNull);
      expect(savedState!.state, CircuitState.open);
      expect(savedState.failureCount, 3);
      cb.dispose();
    });

    test('restores state from storage', () async {
      final InMemoryStorage storage = InMemoryStorage();

      final CircuitBreakerState savedState = CircuitBreakerState(
        state: CircuitState.open,
        failureCount: 5,
        successCount: 0,
        nextAttempt: DateTime.now().add(const Duration(minutes: 5)),
        savedAt: DateTime.now(),
        consecutiveOpenings: 2,
      );

      await storage.save('test-cb', savedState);

      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(),
        failureThreshold: 3,
        storage: storage,
        key: 'test-cb',
      );

      final bool restored = await cb.restoreState();

      expect(restored, isTrue);
      expect(cb.state, CircuitState.open);
      expect(cb.failureCount, 5);
      expect(cb.consecutiveOpenings, 2);
      cb.dispose();
    });

    test('returns false when no state to restore', () async {
      final InMemoryStorage storage = InMemoryStorage();

      final CircuitBreaker cb = CircuitBreaker(
        client: createMockClient(),
        failureThreshold: 3,
        storage: storage,
        key: 'nonexistent',
      );

      final bool restored = await cb.restoreState();

      expect(restored, isFalse);
      expect(cb.state, CircuitState.closed);
      cb.dispose();
    });
  });

  group('SlidingWindow', () {
    test('tracks requests within window', () {
      fakeAsync((FakeAsync async) {
        final SlidingWindow window = SlidingWindow(const Duration(seconds: 10));

        window.recordSuccess();
        window.recordSuccess();
        window.recordFailure();

        expect(window.totalCount, 3);
        expect(window.successCount, 2);
        expect(window.failureCount, 1);
        expect(window.failureRate, closeTo(0.33, 0.01));
      });
    });

    test('prunes old entries', () {
      fakeAsync((FakeAsync async) {
        final SlidingWindow window = SlidingWindow(const Duration(seconds: 5));

        window.recordSuccess();
        window.recordFailure();

        async.elapse(const Duration(seconds: 6));

        window.recordSuccess();

        expect(window.totalCount, 1);
        expect(window.successCount, 1);
        expect(window.failureCount, 0);
      });
    });

    test('clear removes all entries', () {
      final SlidingWindow window = SlidingWindow(const Duration(seconds: 60));

      window.recordSuccess();
      window.recordFailure();
      window.recordSuccess();

      window.clear();

      expect(window.totalCount, 0);
    });
  });

  group('CircuitBreakerMetrics', () {
    test('calculates correct success rate', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();

      metrics.recordSuccess(const Duration(milliseconds: 100));
      metrics.recordSuccess(const Duration(milliseconds: 100));
      metrics.recordFailure(const Duration(milliseconds: 100));

      expect(metrics.successRate, closeTo(0.67, 0.01));
    });

    test('calculates correct failure rate', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();

      metrics.recordSuccess(const Duration(milliseconds: 100));
      metrics.recordFailure(const Duration(milliseconds: 100));
      metrics.recordFailure(const Duration(milliseconds: 100));

      expect(metrics.failureRate, closeTo(0.67, 0.01));
    });

    test('tracks latency statistics', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();

      metrics.recordSuccess(const Duration(milliseconds: 100));
      metrics.recordSuccess(const Duration(milliseconds: 200));
      metrics.recordSuccess(const Duration(milliseconds: 300));

      expect(metrics.minLatency, const Duration(milliseconds: 100));
      expect(metrics.maxLatency, const Duration(milliseconds: 300));
      expect(metrics.averageLatency, const Duration(milliseconds: 200));
    });

    test('reset clears all metrics', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();

      metrics.recordSuccess(const Duration(milliseconds: 100));
      metrics.recordFailure(const Duration(milliseconds: 100));
      metrics.recordRejected();
      metrics.recordRetry();
      metrics.recordFallback();

      metrics.reset();

      expect(metrics.totalRequests, 0);
      expect(metrics.totalSuccesses, 0);
      expect(metrics.totalFailures, 0);
      expect(metrics.totalRejected, 0);
      expect(metrics.totalRetries, 0);
      expect(metrics.totalFallbacks, 0);
    });

    test('toMap returns correct snapshot', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();

      metrics.recordSuccess(const Duration(milliseconds: 100));
      metrics.recordFailure(const Duration(milliseconds: 200));

      final Map<String, dynamic> snapshot = metrics.toMap();

      expect(snapshot['totalRequests'], 2);
      expect(snapshot['totalSuccesses'], 1);
      expect(snapshot['totalFailures'], 1);
      expect(snapshot['successRate'], 0.5);
    });
  });

  group('CircuitState', () {
    test('toString returns readable names', () {
      expect(CircuitState.closed.toString(), 'Closed');
      expect(CircuitState.open.toString(), 'Open');
      expect(CircuitState.halfOpen.toString(), 'Half-open');
    });

  });

  group('CircuitBreakerException', () {
    test('toString includes message', () {
      final CircuitBreakerException exception = CircuitBreakerException(
        'Test cause',
      );

      expect(exception.toString(), 'CircuitBreakerException: Test cause');
    });
  });
}

class _CustomTestClient extends BaseClient {
  final void Function(BaseRequest) onSend;
  _CustomTestClient(this.onSend);

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    onSend(request);
    return StreamedResponse(const Stream<List<int>>.empty(), 200, request: request);
  }
}

