import 'dart:async';
import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreaker.execute (Open State)', () {
    test('throws CircuitBreakerOpenException when open and recovery not ready', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          failureThreshold: 1,
          timeout: const Duration(seconds: 10),
        );

        // Open the circuit
        Object? error;
        cb.execute<void>(() async => throw Exception('fail')).catchError((Object e) {
          error = e;
        });
        
        async.flushMicrotasks();
        expect(error, isNotNull);
        expect(cb.state, CircuitState.open);

        // Verify exception is thrown
        error = null;
        cb.execute<String>(() async => 'success').catchError((Object e) {
          error = e;
          return ''; // Return dummy value for Future<String>
        });

        async.flushMicrotasks();

        expect(error, isA<CircuitBreakerOpenException>());
        
        // Verify metrics
        expect(cb.metrics.totalRejected, 1);
      });
    });

    test('uses fallback when open and recovery not ready', () async {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          failureThreshold: 1,
          timeout: const Duration(seconds: 10),
        );

        // Open the circuit
        cb.execute<void>(() async => throw Exception('fail')).catchError((Object _) {});
        async.flushMicrotasks();
        expect(cb.state, CircuitState.open);

        // Execute with fallback
        String? result;
        cb.execute<String>(
          () async => 'success',
          fallback: (Object error) async => 'fallback',
        ).then((String v) { result = v; });

        async.flushMicrotasks();

        expect(result, 'fallback');

        // Verify metrics
        expect(cb.metrics.totalRejected, 1);
        expect(cb.metrics.totalFallbacks, 1);
      });
    });

    test('transitions to HalfOpen when recovery is ready', () async {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          failureThreshold: 1,
          timeout: const Duration(seconds: 10),
        );

        // Open the circuit
        cb.execute<void>(() async => throw Exception('fail')).catchError((Object _) {});
        async.flushMicrotasks();
        expect(cb.state, CircuitState.open);

        // Advance time past timeout
        async.elapse(const Duration(seconds: 11));

        // Execute should now transition to HalfOpen and run the function
        String? result;
        cb.execute<String>(() async => 'recovered').then((String v) { result = v; });
        
        async.flushMicrotasks();

        expect(result, 'recovered');
        expect(cb.state, CircuitState.halfOpen);
      });
    });

    test('emits correct events when blocked', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          failureThreshold: 1,
          timeout: const Duration(seconds: 10),
        );

        // Open circuit
        cb.execute<void>(() async => throw Exception('fail')).catchError((Object _) {});
        async.flushMicrotasks();

        final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
        final StreamSubscription<CircuitBreakerEvent> sub = cb.events.listen(events.add);

        // Trigger blocked call
        cb.execute<String>(() async => 'success').catchError((Object _) { return ''; });

        async.flushMicrotasks();
        sub.cancel();

        expect(events, isNotEmpty);
        expect(events.first, isA<RequestRejectedEvent>());
      });
    });

    test('emits correct events when using fallback', () {
       fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          failureThreshold: 1,
          timeout: const Duration(seconds: 10),
        );

        // Open circuit
        cb.execute<void>(() async => throw Exception('fail')).catchError((Object _) {});
        async.flushMicrotasks();

        final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
        final StreamSubscription<CircuitBreakerEvent> sub = cb.events.listen(events.add);

        // Trigger fallback
        cb.execute<String>(
          () async => 'success',
          fallback: (Object err) async => 'fallback'
        ).then((String _) {});

        async.flushMicrotasks();
        sub.cancel();

        expect(events.any((CircuitBreakerEvent e) => e is RequestRejectedEvent), isTrue);
        expect(events.any((CircuitBreakerEvent e) => e is FallbackUsedEvent), isTrue);
      });
    });
  });
}
