import '../../domain/models/circuit_breaker_state.dart';
import '../../domain/repositories/circuit_breaker_storage.dart';

/// In-memory implementation of circuit breaker storage
class InMemoryStorage implements CircuitBreakerStorage {
  final Map<String, CircuitBreakerState> _storage =
      <String, CircuitBreakerState>{};

  @override
  Future<void> save(String key, CircuitBreakerState state) async {
    _storage[key] = state;
  }

  @override
  Future<CircuitBreakerState?> load(String key) async {
    return _storage[key];
  }

  @override
  Future<void> delete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> clear() async {
    _storage.clear();
  }

  /// Returns all stored keys
  List<String> get keys => _storage.keys.toList();
}
