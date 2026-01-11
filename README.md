# circuit_breaker

[Portuguese Brazil](README_pt-BR.md) | [Spanish](README_es.md)

Implementation of the Circuit Breaker design pattern in Dart.

**Version:** 3.0.1 · **License:** See LICENSE

[![pub package](https://img.shields.io/pub/v/circuit_breaker.svg)](https://pub.dev/packages/circuit_breaker)
[![Build Status](https://github.com/DouglasMedeiros/circuit-breaker/workflows/Dart%20CI/badge.svg)](https://github.com/DouglasMedeiros/circuit-breaker/actions?query=workflow%3A"Dart+CI"+branch%3Amaster)
![GitHub top language](https://img.shields.io/github/languages/top/DouglasMedeiros/circuit-breaker)

## Why this project

- Protects downstream services by automatically tripping when error rates rise.
- Supports sliding-window failure rates, exponential backoff, health checks, fallbacks, retries, and basic persistence.
- Small, dependency-light library that integrates with `package:http`.

## Features

- Circuit states: `closed`, `open`, `halfOpen`
- Sliding window failure-rate detection
- Exponential backoff for recovery timeouts
- Optional health checks and fallback handlers
- Retry policies and concurrency limiting (bulkhead)
- Metrics and event stream for monitoring
- Pluggable storage via `CircuitBreakerStorage` (in-memory and JSON helpers included)

## Getting started

Prerequisites: Dart SDK 3.0+ (see `pubspec.yaml`).

### Quick example

```dart
Future<void> genericExecuteExample() async {
  final CircuitBreaker cb = CircuitBreaker(
    failureThreshold: 2,
    timeout: const Duration(seconds: 2),
  );

  Future<String> fetchData(String id) async {
    // Simulate some async logic (not necessarily HTTP)
    if (id == 'fail') {
      throw Exception('Database connection error');
    }
    return 'Data for $id';
  }

  final String result = await cb.execute(() => fetchData('123'));

  try {
    await cb.execute(() => fetchData('fail'));
  } catch (e) {
    print('Caught error: $e');
  }

  try {
    await cb.execute(() => fetchData('fail'));
  } catch (e) {
    print('Caught error: $e');
  }

  print('Current state: ${cb.state}');

  // Execution when open with fallback
  final String fallbackResult = await cb.execute(
    () => fetchData('456'),
    fallback: (Object error) async => 'Cached data (fallback)',
  );
  print('Result with fallback: $fallbackResult');
}
```

### Request

```dart
import 'package:http/http.dart' as http;
import 'package:circuit_breaker/circuit_breaker.dart';

Future<void> main() async {
  // Cria um CircuitBreaker
  final CircuitBreaker cb = CircuitBreaker(
    failureThreshold: 3,
    successThreshold: 2,
  );

  final http.Request request = http.Request('GET', Uri.parse('https://api.example.com/ping'));

  try {
    final http.StreamedResponse streamed = await cb.executeRequest(request);
    final http.Response response = await http.Response.fromStream(streamed);
    print('status: ${response.statusCode}');
    print('metrics: ${cb.metrics}');
  } catch (e) {
    print('Requisição falhou: $e');
  }
}
```

### Using a fallback

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:circuit_breaker/circuit_breaker.dart';

Future<void> main() async {
  final CircuitBreaker cb = CircuitBreaker(
    failureThreshold: 2,
    timeout: const Duration(seconds: 1),
    fallback: (http.BaseRequest request, Object? error) async {
      // Return a fallback response when circuit is open or request fails
      final Uint8List bytes = utf8.encode('{"fallback":true}');
      return http.StreamedResponse(Stream<Uint8List>.fromIterable(<Uint8List>[bytes]), 200, headers: <String, String>{
        'content-type': 'application/json',
        'content-length': bytes.length.toString(),
      });
    },
  );

  final http.Request request = http.Request('GET', Uri.parse('https://api.example.com/data'));
  final http.StreamedResponse streamed = await cb.executeRequest(request);
  final http.Response response = await http.Response.fromStream(streamed);
  print('body: ${response.body}');
}
```

### More examples

For more examples see: `example/main.dart`

## API surface

Primary entry points are in the library barrel: `lib/circuit_breaker.dart`. Key types:

- `CircuitBreaker` — main class to create/lookup breakers (`forHost`, `forEndpoint`)
- `FallbackCallback`, `HealthCheckCallback`, `StateChangeCallback`
- `RetryPolicy`, `CircuitBreakerMetrics`, `CircuitState`, `CircuitBreakerStorage`

See the `lib/src/` sources for implementation and examples of advanced options.

## Where to get help

- Open an issue: https://github.com/DouglasMedeiros/circuit-breaker/issues
- Read source files in `lib/src/` for usage examples and behavior

## Maintainers & Contributing

- Maintainer: DouglasMedeiros — see repository homepage in `pubspec.yaml`
- Want to contribute? Please open an issue or PR. Add tests and follow existing code style.

If you plan large changes, open an issue first to discuss the design.

## License

This project is available under the terms in the `LICENSE` file in this repository.

---

Small, focused library to make HTTP calls safer and more resilient. For detailed API docs, consult the source in `lib/src/` and the tests in `test/` for usage patterns.
