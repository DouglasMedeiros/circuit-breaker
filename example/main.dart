import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:http/http.dart' as http;

/// Simple mock HTTP client to simulate responses and errors for examples.
class MockClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;

  MockClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _handler(request);
}

Future<http.StreamedResponse> _makeResponse(int statusCode, String body,
    {Duration delay = Duration.zero}) async {
  if (delay > Duration.zero) {
    await Future<void>.delayed(delay);
  }

  final Uint8List bytes = utf8.encode(body);
  return http.StreamedResponse(Stream<Uint8List>.fromIterable(<Uint8List>[bytes]), statusCode, headers: <String, String>{
    'content-type': 'application/json',
    'content-length': bytes.length.toString(),
  });
}

Future<void> basicExample() async {
  print('\n== Basic example ==');

  final MockClient client = MockClient((http.BaseRequest req) async => _makeResponse(200, '{"ok":true}'));

  final CircuitBreaker cb = CircuitBreaker(
    client: client,
    failureThreshold: 3,
    successThreshold: 2,
  );

  final http.Request request = http.Request('GET', Uri.parse('https://example.test/ping'));

  final http.StreamedResponse streamed = await cb.executeRequest(request);
  final http.Response resp = await http.Response.fromStream(streamed);
  print('status: ${resp.statusCode}, body: ${resp.body}');
  print('metrics: ${cb.metrics}');
}

Future<void> openCircuitWithFallbackExample() async {
  print('\n== Open circuit + fallback example ==');

  // Client that returns 500 for any call
  final MockClient client = MockClient((http.BaseRequest req) async => _makeResponse(500, '{"error":"server"}'));

  final CircuitBreaker cb = CircuitBreaker(
    client: client,
    failureThreshold: 2,
    timeout: const Duration(seconds: 1),
    fallback: (http.BaseRequest request, Object? error) async {
      final Uint8List bytes = utf8.encode('{"fallback":true}');
      return http.StreamedResponse(Stream<Uint8List>.fromIterable(<Uint8List>[bytes]), 200, headers: <String, String>{
        'content-type': 'application/json',
        'content-length': bytes.length.toString(),
      });
    },
  );

  final http.Request request = http.Request('GET', Uri.parse('https://example.test/fail'));

  // Cause failures to open the circuit
  try {
    await cb.executeRequest(request);
  } catch (_) {}
  try {
    await cb.executeRequest(request);
  } catch (_) {}

  print('state after failures: ${cb.state}');

  // This call will use fallback because circuit is open
  final http.StreamedResponse streamed = await cb.executeRequest(request);
  final http.Response resp = await http.Response.fromStream(streamed);
  print('fallback response: ${resp.statusCode} ${resp.body}');
}

Future<void> retryPolicyExample() async {
  print('\n== Retry policy example ==');

  // Simulate a transient failure that succeeds on the 3rd try
  int counter = 0;
  final MockClient client = MockClient((http.BaseRequest req) async {
    counter++;
    if (counter < 3) {
      throw Exception('transient network error');
    }
    return _makeResponse(200, '{"ok":"after retry"}');
  });

  final CircuitBreaker cb = CircuitBreaker(
    client: client,
    retryPolicy: const RetryPolicy(maxRetries: 3, useExponentialBackoff: false, retryDelay: Duration(milliseconds: 100)),
  );

  final http.StreamedResponse streamed = await cb.executeRequest(http.Request('GET', Uri.parse('https://example.test/retry')));
  final http.Response resp = await http.Response.fromStream(streamed);
  print('response after retries: ${resp.statusCode} ${resp.body}');
  print('metrics: ${cb.metrics}');
}

Future<void> concurrencyExample() async {
  print('\n== Concurrency (bulkhead) example ==');

  // Client that delays responses so concurrent requests overlap
  final MockClient client = MockClient((http.BaseRequest req) async => _makeResponse(200, '{"ok":true}', delay: const Duration(milliseconds: 300)));

  final CircuitBreaker cb = CircuitBreaker(
    client: client,
    maxConcurrentRequests: 1,
    fallback: (http.BaseRequest request, Object? error) async => _makeResponse(200, '{"fallback":true}'),
  );

  final http.Request req = http.Request('GET', Uri.parse('https://example.test/slow'));

  final Future<http.StreamedResponse> f1 = cb.executeRequest(req);
  final Future<http.StreamedResponse> f2 = cb.executeRequest(req);

  final http.StreamedResponse r1 = await f1;
  final http.Response res1 = await http.Response.fromStream(r1);
  final http.StreamedResponse r2 = await f2;
  final http.Response res2 = await http.Response.fromStream(r2);

  print('first: ${res1.statusCode}, second: ${res2.statusCode}');
  print('metrics: ${cb.metrics}');
}

Future<void> persistenceExample() async {
  print('\n== Persistence example ==');

  final MockClient client = MockClient((http.BaseRequest req) async => _makeResponse(500, '{"err":true}'));

  final InMemoryStorage storage = InMemoryStorage();

  final CircuitBreaker cb = CircuitBreaker(
    client: client,
    failureThreshold: 1,
    storage: storage,
    key: 'example:cb',
  );

  // cause an opening
  try {
    await cb.executeRequest(http.Request('GET', Uri.parse('https://example.test/x')));
  } catch (_) {}

  await cb.saveState();
  print('saved keys: ${storage.keys}');

  // create a new instance and restore
  final CircuitBreaker cb2 = CircuitBreaker(
    client: MockClient((http.BaseRequest req) async => _makeResponse(200, '{"ok":true}')),
    storage: storage,
    key: 'example:cb',
  );

  final bool restored = await cb2.restoreState();
  print('restored: $restored, state: ${cb2.state}');
}

Future<void> eventsAndMetricsExample() async {
  print('\n== Events & Metrics example ==');

  final MockClient client = MockClient((http.BaseRequest req) async => _makeResponse(200, '{"ok":true}'));

  final CircuitBreaker cb = CircuitBreaker(client: client);

  final StreamSubscription<CircuitBreakerEvent> sub = cb.events.listen((CircuitBreakerEvent e) => print('event -> $e'));

  final http.StreamedResponse streamed = await cb.executeRequest(http.Request('GET', Uri.parse('https://example.test/evt')));
  final http.Response resp = await http.Response.fromStream(streamed);
  print('resp: ${resp.statusCode}');

  print('metrics snapshot: ${cb.metrics.toMap()}');
  await sub.cancel();
}

Future<void> slidingWindowAndFailureRateExample() async {
  print('\n== Sliding window & failure rate example ==');

  // Alternate success and failure to show failure rate
  int calls = 0;
  final MockClient client = MockClient((http.BaseRequest req) async {
    calls++;
    if (calls % 2 == 0) {
      return _makeResponse(500, '{"err":true}');
    }
    return _makeResponse(200, '{"ok":true}');
  });

  final CircuitBreaker cb = CircuitBreaker(
    client: client,
    windowDuration: const Duration(seconds: 5),
    failureRateThreshold: 0.6,
    minimumRequestsInWindow: 2,
  );

  // make a few calls
  for (int i = 0; i < 4; i++) {
    try {
      final http.StreamedResponse s = await cb.executeRequest(http.Request('GET', Uri.parse('https://example.test/w')));
      await http.Response.fromStream(s);
    } catch (_) {}
  }

  print('failureRate: ${cb.currentFailureRate}, state: ${cb.state}');
}

Future<void> exceptionHandlingExample() async {
  print('\n== Exception handling example ==');

  // 1. Handling CircuitBreakerOpenException
  final CircuitBreaker cbOpen = CircuitBreaker(
    client: MockClient((http.BaseRequest req) async => _makeResponse(500, 'error')),
    failureThreshold: 1,
    timeout: const Duration(seconds: 5),
  );

  // Trip it
  try {
    await cbOpen.executeRequest(http.Request('GET', Uri.parse('https://example.test/trip')));
  } catch (_) {}

  try {
    await cbOpen.executeRequest(http.Request('GET', Uri.parse('https://example.test/call')));
  } on CircuitBreakerOpenException catch (e) {
    print('Caught expected open exception: ${e.message}');
    print('Next attempt possible at: ${e.nextAttempt}');
  }

  // 2. Handling CircuitBreakerBulkheadException
  final CircuitBreaker cbBulkhead = CircuitBreaker(
    client: MockClient((http.BaseRequest req) async => _makeResponse(200, 'ok', delay: const Duration(milliseconds: 500))),
    maxConcurrentRequests: 1,
  );

  // Start one request
  unawaited(cbBulkhead.executeRequest(http.Request('GET', Uri.parse('https://example.test/slow'))));

  try {
    // Give it a tiny bit to start
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // Immediate second request
    await cbBulkhead.executeRequest(http.Request('GET', Uri.parse('https://example.test/fast')));
  } on CircuitBreakerBulkheadException catch (e) {
    print('Caught expected bulkhead exception: ${e.message}');
    print('Concurrent limit: ${e.limit}');
  }

  // 3. Handling CircuitBreakerTimeoutException
  final CircuitBreaker cbTimeout = CircuitBreaker(
    client: MockClient((http.BaseRequest req) async => _makeResponse(200, 'ok', delay: const Duration(seconds: 2))),
    requestTimeout: const Duration(milliseconds: 100),
  );

  try {
    await cbTimeout.executeRequest(http.Request('GET', Uri.parse('https://example.test/timeout')));
  } on CircuitBreakerTimeoutException catch (e) {
    print('Caught expected timeout exception: ${e.message}');
    print('Timeout duration: ${e.timeout}');
  }

  // 4. Handling CircuitBreakerNetworkException
  final CircuitBreaker cbNetwork = CircuitBreaker(
    client: MockClient((http.BaseRequest req) async => throw http.ClientException('no internet')),
  );

  try {
    await cbNetwork.executeRequest(http.Request('GET', Uri.parse('https://example.test/network')));
  } on CircuitBreakerNetworkException catch (e) {
    print('Caught expected network exception: ${e.message}');
    print('Original error: ${e.originalError}');
  }
}

Future<void> genericExecuteExample() async {
  print('\n== Generic execute<T> example ==');

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

  // 1. Successful execution
  print('Calling execute with success...');
  final String result = await cb.execute(() => fetchData('123'));
  print('Result: $result');

  // 2. Failure execution
  print('Calling execute with failure (1st time)...');
  try {
    await cb.execute(() => fetchData('fail'));
  } catch (e) {
    print('Caught error: $e');
  }

  print('Calling execute with failure (2nd time) to trip circuit...');
  try {
    await cb.execute(() => fetchData('fail'));
  } catch (e) {
    print('Caught error: $e');
  }

  print('Current state: ${cb.state}');

  // 3. Execution when open with fallback
  print('Calling execute while open with fallback...');
  final String fallbackResult = await cb.execute(
    () => fetchData('456'),
    fallback: (Object error) async => 'Cached data (fallback)',
  );
  print('Result with fallback: $fallbackResult');
}

Future<void> main() async {
  await genericExecuteExample();
  await basicExample();
  await openCircuitWithFallbackExample();
  await retryPolicyExample();
  await concurrencyExample();
  await persistenceExample();
  await eventsAndMetricsExample();
  await slidingWindowAndFailureRateExample();
  await exceptionHandlingExample();

  print('\nAll examples finished.');
}
