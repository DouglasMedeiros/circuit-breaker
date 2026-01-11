import 'dart:async';
import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreaker.execute Failure Handling', () {
    test('calls _onFailure and rethrows when function fails and no fallback is provided', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          failureThreshold: 2,
        );

        final Exception error = Exception('original failure');
        Object? caughtError;

        cb.execute<String>(() async => throw error).catchError((Object e) {
          caughtError = e;
          return '';
        });

        async.flushMicrotasks();

        expect(caughtError, equals(error));
        expect(cb.failureCount, 1);
        expect(cb.metrics.totalFailures, 1);
        expect(cb.state, CircuitState.closed);
      });
    });

    test('calls _onFailure and returns fallback result when function fails and fallback is provided', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          failureThreshold: 2,
        );

        final Exception error = Exception('original failure');
        String? result;

        cb.execute<String>(
          () async => throw error,
          fallback: (Object e) async {
            expect(e, equals(error));
            return 'fallback_value';
          },
        ).then((String v) => result = v);

        async.flushMicrotasks();

        expect(result, 'fallback_value');
        expect(cb.failureCount, 1);
        expect(cb.metrics.totalFailures, 1);
        expect(cb.metrics.totalFallbacks, 1);
      });
    });

    test('emits correct events when function fails and fallback is used', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker();

        final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
        final StreamSubscription<CircuitBreakerEvent> sub = cb.events.listen(events.add);

        final Exception error = Exception('fail');

        cb.execute<String>(
          () async => throw error,
          fallback: (Object _) async => 'fallback',
        );

        async.flushMicrotasks();
        sub.cancel();

        expect(events.any((CircuitBreakerEvent e) => e is RequestFailureEvent), isTrue);
        expect(events.any((CircuitBreakerEvent e) => e is FallbackUsedEvent), isTrue);

        final RequestFailureEvent failureEvent = events.firstWhere((CircuitBreakerEvent e) => e is RequestFailureEvent) as RequestFailureEvent;
        expect(failureEvent.error, equals(error));

        final FallbackUsedEvent fallbackEvent = events.firstWhere((CircuitBreakerEvent e) => e is FallbackUsedEvent) as FallbackUsedEvent;
        expect(fallbackEvent.originalError, equals(error));
      });
    });

    test('trips the circuit when failures reach threshold via generic execute', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          failureThreshold: 2,
        );

        // First failure
        cb.execute<void>(() async => throw Exception('fail 1')).catchError((Object _) {});
        async.flushMicrotasks();
        expect(cb.state, CircuitState.closed);
        expect(cb.failureCount, 1);

        // Second failure - should trip
        cb.execute<void>(() async => throw Exception('fail 2')).catchError((Object _) {});
        async.flushMicrotasks();
        
        expect(cb.state, CircuitState.open);
        expect(cb.failureCount, 2);
      });
    });
  });
}
