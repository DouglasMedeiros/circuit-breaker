import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';

import 'mock_client.dart';

void main() {
  Request makeRequest() {
    return Request('GET', Uri.parse('http://example.com'));
  }

  tearDown(() {
    CircuitBreaker.clearRegistry();
  });

  group('Health Check', () {
    test('starts health check when circuit opens', () {
      fakeAsync((FakeAsync async) {
        int healthCheckCount = 0;
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 1,
          healthCheck: () async {
            healthCheckCount++;
            return false;
          },
          healthCheckInterval: const Duration(seconds: 5),
        );

        // Open the circuit
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        expect(cb.state, CircuitState.open);

        // Verify health check hasn't run yet (it runs on timer)
        expect(healthCheckCount, 0);

        // Advance time by interval
        async.elapse(const Duration(seconds: 5));
        expect(healthCheckCount, 1);

        async.elapse(const Duration(seconds: 5));
        expect(healthCheckCount, 2);
        
        cb.dispose();
      });
    });

    test('stops health check when circuit closes (reset)', () {
      fakeAsync((FakeAsync async) {
        int healthCheckCount = 0;
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 1,
          healthCheck: () async {
            healthCheckCount++;
            return false;
          },
          healthCheckInterval: const Duration(seconds: 5),
        );

        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        expect(cb.state, CircuitState.open);

        async.elapse(const Duration(seconds: 5));
        expect(healthCheckCount, 1);

        cb.reset();
        expect(cb.state, CircuitState.closed);

        async.elapse(const Duration(seconds: 10));
        // Count should not increase after reset
        expect(healthCheckCount, 1);
        
        cb.dispose();
      });
    });

    test('transitions to HalfOpen when health check passes', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 1,
          healthCheck: () async {
            return true; // Healthy
          },
          healthCheckInterval: const Duration(seconds: 5),
        );

        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        expect(cb.state, CircuitState.open);

        async.elapse(const Duration(seconds: 5));
        
        expect(cb.state, CircuitState.halfOpen);
        
        cb.dispose();
      });
    });

    test('stays Open when health check fails', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 1,
          healthCheck: () async {
            return false; // Unhealthy
          },
          healthCheckInterval: const Duration(seconds: 5),
        );

        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        expect(cb.state, CircuitState.open);

        async.elapse(const Duration(seconds: 5));
        expect(cb.state, CircuitState.open);
        
        cb.dispose();
      });
    });

    test('stays Open when health check throws exception', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 1,
          healthCheck: () async {
            throw Exception('Health check failed');
          },
          healthCheckInterval: const Duration(seconds: 5),
        );

        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        expect(cb.state, CircuitState.open);

        async.elapse(const Duration(seconds: 5));
        expect(cb.state, CircuitState.open);
        
        cb.dispose();
      });
    });

    test('emits HealthCheckEvent', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 1,
          healthCheck: () async {
            return true;
          },
          healthCheckInterval: const Duration(seconds: 5),
        );

        final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
        cb.events.listen(events.add);

        cb.executeRequest(makeRequest());
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));

        final HealthCheckEvent event = events.whereType<HealthCheckEvent>().first;
        expect(event.isHealthy, isTrue);
        expect(event.duration, isNotNull);
        
        cb.dispose();
      });
    });
    
    test('emits HealthCheckEvent on failure/exception', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 1,
          healthCheck: () async {
             throw Exception('fail');
          },
          healthCheckInterval: const Duration(seconds: 5),
        );

        final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
        cb.events.listen(events.add);

        cb.executeRequest(makeRequest());
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));

        final HealthCheckEvent event = events.whereType<HealthCheckEvent>().first;
        expect(event.isHealthy, isFalse);
        
        cb.dispose();
      });
    });

    test('restores state and starts health check if Open', () async {
       final InMemoryStorage storage = InMemoryStorage();
       final DateTime now = DateTime.now();
       
       final CircuitBreakerState openState = CircuitBreakerState(
         state: CircuitState.open,
         failureCount: 5,
         successCount: 0,
         nextAttempt: now.add(const Duration(minutes: 5)),
         savedAt: now,
       );
       
       await storage.save('test-key', openState);
       
       fakeAsync((FakeAsync async) {
         int healthCheckCount = 0;
         final CircuitBreaker cb = CircuitBreaker(
           storage: storage,
           key: 'test-key',
           healthCheck: () async {
             healthCheckCount++;
             return false;
           },
           healthCheckInterval: const Duration(seconds: 5),
         );
         
         // Have to wait for restore to complete? restoreState is async.
         // But here we can't await in fakeAsync callback easily if it's not using async/await properly
         // Let's call restoreState inside logic
         
         cb.restoreState().then((_) {
            expect(cb.state, CircuitState.open);
            
            async.elapse(const Duration(seconds: 5));
            expect(healthCheckCount, 1);
         });
         
         async.flushMicrotasks();
         cb.dispose();
       });
    });

    test('transitioning away from Open stops health check', () {
      fakeAsync((FakeAsync async) {
        int healthCheckCount = 0;
        final CircuitBreaker cb = CircuitBreaker(
          client: createMockClient(statusCode: 500),
          failureThreshold: 1,
          healthCheck: () async {
            healthCheckCount++;
            return false;
          },
          healthCheckInterval: const Duration(seconds: 5),
        );

        // Trip to Open -> starts health check
        cb.executeRequest(makeRequest());
        async.flushMicrotasks();
        expect(cb.state, CircuitState.open);

        async.elapse(const Duration(seconds: 5));
        expect(healthCheckCount, 1);

        // Transition to Half-Open (manually or via timeout)
        // Resetting to Closed is an easy way to trigger transition away from Open
        cb.reset();
        expect(cb.state, CircuitState.closed);

        async.elapse(const Duration(seconds: 10));
        // Should still be 1
        expect(healthCheckCount, 1);
        
        cb.dispose();
      });
    });
  });
}

