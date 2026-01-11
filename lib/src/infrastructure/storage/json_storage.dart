import 'dart:convert';

import '../../domain/models/circuit_breaker_state.dart';
import '../../domain/repositories/circuit_breaker_storage.dart';

/// JSON file-based storage implementation (platform-agnostic interface)
class JsonStorage implements CircuitBreakerStorage {
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _remove;
  final Future<void> Function() _clearAll;

  /// Creates a JSON storage with custom read/write functions
  JsonStorage({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    required Future<void> Function(String key) remove,
    required Future<void> Function() clearAll,
  })  : _read = read,
        _write = write,
        _remove = remove,
        _clearAll = clearAll;

  @override
  Future<void> save(String key, CircuitBreakerState state) async {
    final String jsonString = jsonEncode(state.toJson());
    await _write(key, jsonString);
  }

  @override
  Future<CircuitBreakerState?> load(String key) async {
    final String? jsonString = await _read(key);
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }
    try {
      final Map<String, dynamic> json =
          jsonDecode(jsonString) as Map<String, dynamic>;
      return CircuitBreakerState.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    await _remove(key);
  }

  @override
  Future<void> clear() async {
    await _clearAll();
  }
}
