import 'package:circuit_breaker/src/domain/exceptions/circuit_breaker_exception.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreakerException', () {
    test('toString returns correct message', () {
      final CircuitBreakerException exception = CircuitBreakerException(
        'Too many failures',
      );

      expect(exception.toString(), equals('CircuitBreakerException: Too many failures'));
      expect(exception.message, equals('Too many failures'));
    });
  });

  group('CircuitBreakerOpenException', () {
    test('stores nextAttempt', () {
      final DateTime nextAttempt = DateTime.now();
      final CircuitBreakerOpenException exception = CircuitBreakerOpenException(
        'Circuit is open',
        nextAttempt: nextAttempt,
      );

      expect(exception.nextAttempt, equals(nextAttempt));
      expect(exception.toString(), equals('CircuitBreakerOpenException: Circuit is open'));
    });
  });

  group('CircuitBreakerTimeoutException', () {
    test('stores timeout', () {
      const Duration timeout = Duration(seconds: 5);
      final CircuitBreakerTimeoutException exception = CircuitBreakerTimeoutException(
        'Timeout exceeded',
        timeout: timeout,
      );

      expect(exception.timeout, equals(timeout));
      expect(exception.toString(), equals('CircuitBreakerTimeoutException: Timeout exceeded'));
    });
  });

  group('CircuitBreakerBulkheadException', () {
    test('stores limit', () {
      final CircuitBreakerBulkheadException exception = CircuitBreakerBulkheadException(
        'Limit exceeded',
        limit: 10,
      );

      expect(exception.limit, equals(10));
      expect(exception.toString(), equals('CircuitBreakerBulkheadException: Limit exceeded'));
    });
  });

  group('CircuitBreakerNetworkException', () {
    test('stores originalError', () {
      final Exception original = Exception('Network error');
      final CircuitBreakerNetworkException exception = CircuitBreakerNetworkException(
        'Connection failed',
        originalError: original,
      );

      expect(exception.originalError, equals(original));
      expect(exception.toString(), equals('CircuitBreakerNetworkException: Connection failed'));
    });
  });
}
