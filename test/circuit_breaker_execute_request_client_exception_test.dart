import 'dart:async';
import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreaker.executeRequest ClientException Handling', () {
    test('wraps ClientException in CircuitBreakerNetworkException', () {
      fakeAsync((FakeAsync async) {
        final ClientException clientException = ClientException('connection failed');
        final MockClient client = MockClient((Request request) async {
          throw clientException;
        });

        final CircuitBreaker cb = CircuitBreaker(
          client: client,
        );

        final Request request = Request('GET', Uri.parse('https://example.com'));

        Object? caughtError;
        cb.executeRequest(request).catchError((Object e) {
          caughtError = e;
          return StreamedResponse(const Stream<List<int>>.empty(), 500);
        });

        async.flushMicrotasks();

        expect(caughtError, isA<CircuitBreakerNetworkException>());
        
        final CircuitBreakerNetworkException networkError = caughtError as CircuitBreakerNetworkException;
        expect(networkError.request, equals(request));
        expect(networkError.originalError, equals(clientException));
        expect(networkError.message, contains('Network error: connection failed'));

        expect(cb.failureCount, 1);
        expect(cb.metrics.totalFailures, 1);
      });
    });

    test('calls fallback when ClientException occurs', () {
       fakeAsync((FakeAsync async) {
        final ClientException clientException = ClientException('connection failed');
        final MockClient client = MockClient((Request request) async {
          throw clientException;
        });

        final CircuitBreaker cb = CircuitBreaker(
          client: client,
          fallback: (BaseRequest req, Object? err) async {
            // Verify correct error is passed to fallback (unwrapped ClientException)
            // Note: The catch block first calls fallback with original error 'e', 
            // THEN checks if e is ClientException to wrap it if fallback was null.
            expect(err, equals(clientException));
            return StreamedResponse(const Stream<List<int>>.empty(), 503);
          }
        );

        final Request request = Request('GET', Uri.parse('https://example.com'));
        
        StreamedResponse? result;
        cb.executeRequest(request).then((StreamedResponse r) => result = r);

        async.flushMicrotasks();

        expect(result, isNotNull);
        expect(result!.statusCode, 503);
        expect(cb.metrics.totalFallbacks, 1);
      });
    });
  });
}
