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

  final http.StreamedResponse streamed = await cb.execute(request);
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
    await cb.execute(request);
  } catch (_) {}
  try {
    await cb.execute(request);
  } catch (_) {}

  print('state after failures: ${cb.state}');

  // This call will use fallback because circuit is open
  final http.StreamedResponse streamed = await cb.execute(request);
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

  final http.StreamedResponse streamed = await cb.execute(http.Request('GET', Uri.parse('https://example.test/retry')));
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

  final Future<http.StreamedResponse> f1 = cb.execute(req);
  final Future<http.StreamedResponse> f2 = cb.execute(req);

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
    await cb.execute(http.Request('GET', Uri.parse('https://example.test/x')));
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

  final http.StreamedResponse streamed = await cb.execute(http.Request('GET', Uri.parse('https://example.test/evt')));
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
      final http.StreamedResponse s = await cb.execute(http.Request('GET', Uri.parse('https://example.test/w')));
      await http.Response.fromStream(s);
    } catch (_) {}
  }

  print('failureRate: ${cb.currentFailureRate}, state: ${cb.state}');
}

Future<void> main() async {
  await basicExample();
  await openCircuitWithFallbackExample();
  await retryPolicyExample();
  await concurrencyExample();
  await persistenceExample();
  await eventsAndMetricsExample();
  await slidingWindowAndFailureRateExample();

  print('\nAll examples finished.');
}
