/// Base exception thrown by the Circuit Breaker
class CircuitBreakerException implements Exception {
  /// The cause of the exception
  final String message;

  /// Creates a new [CircuitBreakerException]
  CircuitBreakerException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when the circuit is open and blocking requests
class CircuitBreakerOpenException extends CircuitBreakerException {
  /// The time when the circuit might close
  final DateTime? nextAttempt;

  /// Creates a new [CircuitBreakerOpenException]
  CircuitBreakerOpenException(
    super.message, {
    this.nextAttempt,
  });
}

/// Thrown when the request timeout is exceeded
class CircuitBreakerTimeoutException extends CircuitBreakerException {
  /// The timeout duration that was exceeded
  final Duration timeout;

  /// Creates a new [CircuitBreakerTimeoutException]
  CircuitBreakerTimeoutException(
    super.message, {
    required this.timeout,
  });
}

/// Thrown when the bulkhead (concurrency limit) is exceeded
class CircuitBreakerBulkheadException extends CircuitBreakerException {
  /// The maximum number of concurrent requests allowed
  final int limit;

  /// Creates a new [CircuitBreakerBulkheadException]
  CircuitBreakerBulkheadException(
    super.message, {
    required this.limit,
  });
}

/// Thrown when a network error occurs during request execution
class CircuitBreakerNetworkException extends CircuitBreakerException {
  /// The original error that caused this exception
  final Object originalError;

  /// Creates a new [CircuitBreakerNetworkException]
  CircuitBreakerNetworkException(
    super.message, {
    required this.originalError,
  });
}
