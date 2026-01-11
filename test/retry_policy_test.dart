import 'package:circuit_breaker/src/domain/policies/retry_policy.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    test('default constants', () {
      expect(RetryPolicy.none.maxRetries, 0);
      expect(RetryPolicy.defaultPolicy.maxRetries, 3);
      expect(RetryPolicy.defaultPolicy.useExponentialBackoff, isTrue);
    });

    test('getDelayForAttempt without exponential backoff', () {
      const RetryPolicy policy = RetryPolicy(
        useExponentialBackoff: false,
        retryDelay: Duration(seconds: 1),
      );
      expect(policy.getDelayForAttempt(1), const Duration(seconds: 1));
      expect(policy.getDelayForAttempt(5), const Duration(seconds: 1));
    });

    test('getDelayForAttempt with exponential backoff', () {
      const RetryPolicy policy = RetryPolicy(
        useExponentialBackoff: true,
        retryDelay: Duration(seconds: 1),
        backoffMultiplier: 2.0,
        maxRetryDelay: Duration(seconds: 10),
      );
      // Attempt 0: 0 multiplier? loop 0 to 0 -> multiplier 1. 1*1 = 1s
      expect(policy.getDelayForAttempt(0), const Duration(seconds: 1));
      
      // Attempt 1: loop 0 to 1 -> multiplier 2. 1*2 = 2s
      expect(policy.getDelayForAttempt(1), const Duration(seconds: 2));
      
      // Attempt 2: loop 0 to 2 -> multiplier 4. 1*4 = 4s
      expect(policy.getDelayForAttempt(2), const Duration(seconds: 4));
    });

    test('getDelayForAttempt caps at maxRetryDelay', () {
      const RetryPolicy policy = RetryPolicy(
        useExponentialBackoff: true,
        retryDelay: Duration(seconds: 1),
        backoffMultiplier: 2.0,
        maxRetryDelay: Duration(seconds: 3),
      );
      // Attempt 2 would be 4s, capped at 3s
      expect(policy.getDelayForAttempt(2), const Duration(seconds: 3));
    });

    test('shouldRetryForStatusCode defaults', () {
      const RetryPolicy policy = RetryPolicy();
      expect(policy.shouldRetryForStatusCode(500), isTrue);
      expect(policy.shouldRetryForStatusCode(429), isTrue);
      expect(policy.shouldRetryForStatusCode(503), isTrue);
      expect(policy.shouldRetryForStatusCode(200), isFalse);
      expect(policy.shouldRetryForStatusCode(404), isFalse);
    });
    
    test('shouldRetryForStatusCode custom', () {
      final RetryPolicy policy = RetryPolicy(
        shouldRetryStatusCode: (int code) => code == 404,
      );
      expect(policy.shouldRetryForStatusCode(404), isTrue);
      expect(policy.shouldRetryForStatusCode(500), isFalse);
    });

    test('shouldRetryForException defaults', () {
      const RetryPolicy policy = RetryPolicy();
      expect(policy.shouldRetryForException(Exception()), isTrue);
    });
    
    test('shouldRetryForException custom', () {
      final RetryPolicy policy = RetryPolicy(
        shouldRetryException: (Object e) => e is FormatException,
      );
      expect(policy.shouldRetryForException(const FormatException()), isTrue);
      expect(policy.shouldRetryForException(Exception()), isFalse);
    });
  });
}