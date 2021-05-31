import 'dart:convert';

import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';

import 'mock_client.dart';

void main() {
  late Request request;

  MockClient _makeClient({int statusCode = 200}) =>
      MockClient((Request request) async => Response(
          json.encode(request.bodyFields), statusCode,
          request: request,
          headers: <String, String>{'content-type': 'application/json'}));

  Request _makeRequest() {
    final Request request = Request('POST', Uri.parse('http://example.com'));
    request.bodyFields = <String, String>{'data': 'abc123'};
    return request;
  }

  setUp(() {
    request = _makeRequest();
  });

  group('STATE GREEN', () {
    test('Should_Success_When_SuccessThresholdNotReached', () async {
      final CircuitBreaker cb = CircuitBreaker(
          request: request,
          failureThreshold: 3,
          successThreshold: 5,
          timeout: const Duration(seconds: 2));

      cb.client = _makeClient();

      final BaseResponse response = await cb.execute();
      expect(response.statusCode, 200);
      expect(cb.state, State.GREEN);
    });

    test('Should_Success_When_SuccessThresholdNotReached_WithChained',
        () async {
      final CircuitBreaker cb = CircuitBreaker(
          request: request,
          failureThreshold: 3,
          successThreshold: 5,
          timeout: const Duration(seconds: 2));

      cb.client = _makeClient();

      await cb.execute().then((BaseResponse value) {
        expect(value.statusCode, 200);
        expect(cb.state, State.GREEN);
      }).catchError((_, __) => fail('Failed'));
    });
  });

  group('STATE RED', () {
    test('Should_Success_When_FailThresholdReached', () async {
      final CircuitBreaker cb = CircuitBreaker(
          request: request,
          failureThreshold: 3,
          successThreshold: 5,
          timeout: const Duration(seconds: 2));

      cb.client = _makeClient(statusCode: 500);

      expect(cb.state, State.GREEN);

      await cb.execute();
      await cb.execute();

      final BaseResponse response = await cb.execute();
      expect(response.statusCode, 500);
      expect(cb.state, State.RED);
    });
  });

  group('STATE YELLOW', () {
    test('Should_Success_When_FailThresholdNotReached', () async {
      final CircuitBreaker cb = CircuitBreaker(
          request: request,
          failureThreshold: 3,
          successThreshold: 2,
          timeout: const Duration(seconds: 2));

      cb.client = _makeClient(statusCode: 500);

      expect(cb.state, State.GREEN);
      expect(cb.nextAttempt.microsecondsSinceEpoch,
          lessThanOrEqualTo(DateTime.now().microsecondsSinceEpoch));

      await cb.execute();
      await cb.execute();
      await cb.execute();

      cb.client = _makeClient();

      try {
        await cb.execute();
        expect(cb.nextAttempt, DateTime.now().add(cb.timeout));
        expect(cb.nextAttempt.isAfter(DateTime.now()), true);
      } catch (_) {
        await Future.delayed(const Duration(seconds: 3), () async {
          await cb.execute();
          final BaseResponse response = await cb.execute();

          expect(response.statusCode, 200);
          expect(cb.state, State.YELLOW);

          await cb.execute();

          expect(response.statusCode, 200);
          expect(cb.state, State.GREEN);
        });
      }
    });
  });

  group('STATE RED', () {
    test('Should_Fail_When_FailThresholdReached', () async {
      final CircuitBreaker cb = CircuitBreaker(
          request: request,
          failureThreshold: 3,
          successThreshold: 5,
          timeout: const Duration(seconds: 2));

      cb.client = _makeClient(statusCode: 500);

      expect(cb.state, State.GREEN);

      await cb.execute();
      await cb.execute();
      await cb.execute();

      expect(() => cb.execute(),
          throwsA(predicate((Object? e) => e is CircuitBreakerException)));
    });
  });
}
