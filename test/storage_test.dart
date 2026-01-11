import 'dart:convert';

import 'package:circuit_breaker/src/domain/enums/circuit_state.dart';
import 'package:circuit_breaker/src/domain/models/circuit_breaker_state.dart';
import 'package:circuit_breaker/src/infrastructure/storage/in_memory_storage.dart';
import 'package:circuit_breaker/src/infrastructure/storage/json_storage.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreakerState', () {
    final DateTime now = DateTime.now();
    final CircuitBreakerState sampleState = CircuitBreakerState(
      state: CircuitState.open,
      failureCount: 5,
      successCount: 0,
      nextAttempt: now.add(const Duration(seconds: 60)),
      savedAt: now,
      consecutiveOpenings: 2,
    );

    test('toJson and fromJson work correctly', () {
      final Map<String, dynamic> json = sampleState.toJson();
      final CircuitBreakerState newState = CircuitBreakerState.fromJson(json);

      expect(newState.state, equals(sampleState.state));
      expect(newState.failureCount, equals(sampleState.failureCount));
      expect(newState.successCount, equals(sampleState.successCount));
      expect(newState.consecutiveOpenings, equals(sampleState.consecutiveOpenings));
      // Comparing dates as strings to avoid microsecond discrepancies if any
      expect(newState.nextAttempt.toIso8601String(), equals(sampleState.nextAttempt.toIso8601String()));
      expect(newState.savedAt.toIso8601String(), equals(sampleState.savedAt.toIso8601String()));
      expect(newState.toString(), contains('state: open'));
    });

    test('fromJson handles missing optional fields', () {
      final Map<String, dynamic> minimalJson = <String, dynamic>{
        'state': 'closed',
        'nextAttempt': now.toIso8601String(),
        'savedAt': now.toIso8601String(),
      };

      final CircuitBreakerState newState = CircuitBreakerState.fromJson(minimalJson);

      expect(newState.state, equals(CircuitState.closed));
      expect(newState.failureCount, equals(0));
      expect(newState.successCount, equals(0));
      expect(newState.consecutiveOpenings, equals(0));
    });

    test('fromJson handles unknown state gracefully', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'state': 'unknown_state',
        'nextAttempt': now.toIso8601String(),
        'savedAt': now.toIso8601String(),
      };

      final CircuitBreakerState newState = CircuitBreakerState.fromJson(json);
      expect(newState.state, equals(CircuitState.closed)); // Default fallback
    });
  });

  group('InMemoryStorage', () {
    late InMemoryStorage storage;
    final DateTime now = DateTime.now();
    final CircuitBreakerState state = CircuitBreakerState(
      state: CircuitState.closed,
      failureCount: 0,
      successCount: 0,
      nextAttempt: now,
      savedAt: now,
    );

    setUp(() {
      storage = InMemoryStorage();
    });

    test('save stores the state', () async {
      await storage.save('key1', state);
      final CircuitBreakerState? loaded = await storage.load('key1');
      expect(loaded, equals(state));
    });

    test('load returns null for unknown key', () async {
      final CircuitBreakerState? loaded = await storage.load('unknown');
      expect(loaded, isNull);
    });

    test('delete removes the state', () async {
      await storage.save('key1', state);
      await storage.delete('key1');
      final CircuitBreakerState? loaded = await storage.load('key1');
      expect(loaded, isNull);
    });

    test('clear removes all states', () async {
      await storage.save('key1', state);
      await storage.save('key2', state);
      await storage.clear();
      expect(await storage.load('key1'), isNull);
      expect(await storage.load('key2'), isNull);
      expect(storage.keys, isEmpty);
    });
    
    test('keys returns all keys', () async {
       await storage.save('key1', state);
       await storage.save('key2', state);
       expect(storage.keys, containsAll(<String>['key1', 'key2']));
    });
  });

  group('JsonStorage', () {
    late Map<String, String> backingStore;
    late JsonStorage storage;
    final DateTime now = DateTime.now();
    final CircuitBreakerState state = CircuitBreakerState(
      state: CircuitState.closed,
      failureCount: 0,
      successCount: 0,
      nextAttempt: now,
      savedAt: now,
    );

    setUp(() {
      backingStore = <String, String>{};
      storage = JsonStorage(
        read: (String key) async => backingStore[key],
        write: (String key, String value) async => backingStore[key] = value,
        remove: (String key) async => backingStore.remove(key),
        clearAll: () async => backingStore.clear(),
      );
    });

    test('save encodes and writes JSON', () async {
      await storage.save('key1', state);
      expect(backingStore.containsKey('key1'), isTrue);
      expect(backingStore['key1'], contains('"state":"closed"'));
    });

    test('load decodes JSON', () async {
      backingStore['key1'] = jsonEncode(state.toJson());
      final CircuitBreakerState? loaded = await storage.load('key1');
      expect(loaded?.state, equals(state.state));
    });

    test('load returns null for missing key (null string)', () async {
      final CircuitBreakerState? loaded = await storage.load('unknown');
      expect(loaded, isNull);
    });
    
    test('load returns null for empty string', () async {
      backingStore['empty'] = '';
      final CircuitBreakerState? loaded = await storage.load('empty');
      expect(loaded, isNull);
    });

    test('load returns null for invalid JSON', () async {
      backingStore['invalid'] = '{ invalid json }';
      final CircuitBreakerState? loaded = await storage.load('invalid');
      expect(loaded, isNull);
    });

    test('delete removes from backing store', () async {
      backingStore['key1'] = 'data';
      await storage.delete('key1');
      expect(backingStore.containsKey('key1'), isFalse);
    });

    test('clear empties backing store', () async {
      backingStore['key1'] = 'data';
      await storage.clear();
      expect(backingStore.isEmpty, isTrue);
    });
  });
}
