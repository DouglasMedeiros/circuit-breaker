import 'package:http/http.dart' as http;

/// Exception thrown when the circuit breaker is open and blocking requests
class CircuitBreakerException implements Exception {
  /// The cause of the exception
  final String cause;

  /// The request that was blocked
  final http.BaseRequest request;

  /// Creates a new [CircuitBreakerException]
  CircuitBreakerException({required this.request, required this.cause});

  @override
  String toString() => 'CircuitBreakerException: $cause';
}
