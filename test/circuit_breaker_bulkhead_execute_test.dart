import 'dart:async';
import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreaker.execute Bulkhead (Concurrency Limit)', () {
    test('throws CircuitBreakerBulkheadException when maxConcurrentRequests is reached', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          maxConcurrentRequests: 1,
        );

        // First request - stays pending because we don't complete the future
        final Completer<String> completer = Completer<String>();
        cb.execute<String>(() => completer.future).catchError((Object _) => '');

        async.flushMicrotasks();
        expect(cb.pendingRequests, 1);

        // Second request - should be rejected immediately
        Object? error;
        cb.execute<String>(() async => 'success').catchError((Object e) {
          error = e;
          return '';
        });

        async.flushMicrotasks();

        expect(error, isA<CircuitBreakerBulkheadException>());
        expect(cb.metrics.totalRejected, 1);
        
        final CircuitBreakerBulkheadException bulkheadError = error as CircuitBreakerBulkheadException;
        expect(bulkheadError.limit, 1);
        expect(bulkheadError.message, contains('Max concurrent requests (1) exceeded'));
      });
    });

    test('uses fallback when maxConcurrentRequests is reached', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          maxConcurrentRequests: 1,
        );

        // First request - stays pending
        final Completer<String> completer = Completer<String>();
        cb.execute<String>(() => completer.future).catchError((Object _) => '');

        async.flushMicrotasks();

        // Second request - should use fallback
        String? result;
        cb.execute<String>(
          () async => 'success',
          fallback: (Object error) async {
            return 'fallback_result';
          },
        ).then((String v) => result = v);

        async.flushMicrotasks();

        expect(result, 'fallback_result');
        expect(cb.metrics.totalRejected, 1);
        expect(cb.metrics.totalFallbacks, 1);
      });
    });

    test('emits correct events when bulkhead limit is exceeded', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          maxConcurrentRequests: 1,
        );

        // First request
        final Completer<String> completer = Completer<String>();
        cb.execute<String>(() => completer.future).catchError((Object _) => '');
        async.flushMicrotasks();

        final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
        final StreamSubscription<CircuitBreakerEvent> sub = cb.events.listen(events.add);

        // Trigger rejected call
        cb.execute<String>(() async => 'success').catchError((Object _) => '');

        async.flushMicrotasks();
        sub.cancel();

        expect(events.any((CircuitBreakerEvent e) => e is RequestRejectedEvent), isTrue);
        final RequestRejectedEvent rejectedEvent = events.firstWhere((CircuitBreakerEvent e) => e is RequestRejectedEvent) as RequestRejectedEvent;
        expect(rejectedEvent.url, isNull);
      });
    });

    test('emits FallbackUsedEvent when bulkhead limit is exceeded and fallback is provided', () {
      fakeAsync((FakeAsync async) {
        final CircuitBreaker cb = CircuitBreaker(
          maxConcurrentRequests: 1,
        );

        // First request
        final Completer<String> completer = Completer<String>();
        cb.execute<String>(() => completer.future).catchError((Object _) => '');
        async.flushMicrotasks();

        final List<CircuitBreakerEvent> events = <CircuitBreakerEvent>[];
        final StreamSubscription<CircuitBreakerEvent> sub = cb.events.listen(events.add);

        // Trigger fallback
        cb.execute<String>(
          () async => 'success',
          fallback: (Object err) async => 'fallback',
        );

        async.flushMicrotasks();
        sub.cancel();

        expect(events.any((CircuitBreakerEvent e) => e is RequestRejectedEvent), isTrue);
        expect(events.any((CircuitBreakerEvent e) => e is FallbackUsedEvent), isTrue);
        
        final FallbackUsedEvent fallbackEvent = events.firstWhere((CircuitBreakerEvent e) => e is FallbackUsedEvent) as FallbackUsedEvent;
        expect(fallbackEvent.originalError, contains('Max concurrent requests exceeded'));
      });
    });
  });
}
