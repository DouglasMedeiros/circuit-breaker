import '../models/circuit_breaker_state.dart';

/// Interface for persisting circuit breaker state
abstract class CircuitBreakerStorage {
  /// Saves circuit breaker state
  Future<void> save(String key, CircuitBreakerState state);

  /// Loads circuit breaker state, returns null if not found
  Future<CircuitBreakerState?> load(String key);

  /// Deletes circuit breaker state
  Future<void> delete(String key);

  /// Clears all stored states
  Future<void> clear();
}
