import '../enums/circuit_state.dart';

/// Base class for all circuit breaker events
sealed class CircuitBreakerEvent {
  /// Timestamp when the event occurred
  final DateTime timestamp;

  /// Creates a new event with the current timestamp
  CircuitBreakerEvent() : timestamp = DateTime.now();
}

/// Event emitted when the circuit state changes
class StateChangedEvent extends CircuitBreakerEvent {
  /// Previous state before the transition
  final CircuitState previousState;

  /// New state after the transition
  final CircuitState newState;

  /// Creates a new state changed event
  StateChangedEvent({
    required this.previousState,
    required this.newState,
  });

  @override
  String toString() => 'StateChangedEvent($previousState -> $newState)';
}

/// Event emitted when a request succeeds
class RequestSuccessEvent extends CircuitBreakerEvent {
  /// HTTP status code of the response
  final int statusCode;

  /// Duration of the request
  final Duration duration;

  /// Creates a new request success event
  RequestSuccessEvent({
    required this.statusCode,
    required this.duration,
  });

  @override
  String toString() =>
      'RequestSuccessEvent(status: $statusCode, duration: $duration)';
}

/// Event emitted when a request fails
class RequestFailureEvent extends CircuitBreakerEvent {
  /// HTTP status code if available, null for network errors
  final int? statusCode;

  /// Error that caused the failure
  final Object? error;

  /// Duration of the request attempt
  final Duration duration;

  /// Creates a new request failure event
  RequestFailureEvent({
    this.statusCode,
    this.error,
    required this.duration,
  });

  @override
  String toString() =>
      'RequestFailureEvent(status: $statusCode, error: $error)';
}

/// Event emitted when a request is rejected due to open circuit
class RequestRejectedEvent extends CircuitBreakerEvent {
  /// URL that was rejected
  final Uri url;

  /// When the circuit will allow the next attempt
  final DateTime nextAttempt;

  /// Creates a new request rejected event
  RequestRejectedEvent({
    required this.url,
    required this.nextAttempt,
  });

  @override
  String toString() =>
      'RequestRejectedEvent(url: $url, nextAttempt: $nextAttempt)';
}

/// Event emitted when a request is retried
class RequestRetryEvent extends CircuitBreakerEvent {
  /// Current retry attempt number
  final int attempt;

  /// Maximum number of retries
  final int maxRetries;

  /// Error that triggered the retry
  final Object? error;

  /// Creates a new request retry event
  RequestRetryEvent({
    required this.attempt,
    required this.maxRetries,
    this.error,
  });

  @override
  String toString() => 'RequestRetryEvent(attempt: $attempt/$maxRetries)';
}

/// Event emitted when fallback is used
class FallbackUsedEvent extends CircuitBreakerEvent {
  /// Original error that triggered fallback
  final Object? originalError;

  /// Creates a new fallback used event
  FallbackUsedEvent({this.originalError});

  @override
  String toString() => 'FallbackUsedEvent(error: $originalError)';
}

/// Event emitted when health check is performed
class HealthCheckEvent extends CircuitBreakerEvent {
  /// Whether the health check passed
  final bool isHealthy;

  /// Duration of the health check
  final Duration duration;

  /// Creates a new health check event
  HealthCheckEvent({
    required this.isHealthy,
    required this.duration,
  });

  @override
  String toString() =>
      'HealthCheckEvent(healthy: $isHealthy, duration: $duration)';
}
