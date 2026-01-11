import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreaker.executeFunction', () {
    test('executes function successfully', () async {
      final CircuitBreaker cb = CircuitBreaker();
      final String result = await cb.execute(() async => 'success');
      expect(result, 'success');
      expect(cb.state, CircuitState.closed);
    });

    test('counts failures', () async {
      final CircuitBreaker cb = CircuitBreaker(failureThreshold: 2);
      
      try {
        await cb.execute(() async => throw Exception('fail'));
      } catch (_) {}
      
      expect(cb.failureCount, 1);
    });

    test('opens circuit after threshold', () async {
      final CircuitBreaker cb = CircuitBreaker(failureThreshold: 2);

      try {
        await cb.execute(() async => throw Exception('fail'));
      } catch (_) {}
      try {
        await cb.execute(() async => throw Exception('fail'));
      } catch (_) {}

      expect(cb.state, CircuitState.open);
    });

    test('uses fallback', () async {
      final CircuitBreaker cb = CircuitBreaker(failureThreshold: 1);

      try {
        await cb.execute(() async => throw Exception('fail'));
      } catch (_) {}
      
      expect(cb.state, CircuitState.open);

      final String result = await cb.execute(
        () async => 'should not be called',
        fallback: (Object error) async => 'fallback',
      );

      expect(result, 'fallback');
    });

    test('retries on failure', () async {
      int attempts = 0;
      final CircuitBreaker cb = CircuitBreaker(
        retryPolicy: RetryPolicy(
            maxRetries: 2,
            retryDelay: Duration.zero,
            shouldRetryException: (Object e) => true
        ),
      );

      try {
        await cb.execute(() async {
          attempts++;
          throw Exception('fail');
        });
      } catch (_) {}

      expect(attempts, 3); // Initial + 2 retries
    });
  });
}
