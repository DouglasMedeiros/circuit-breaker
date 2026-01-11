import 'package:circuit_breaker/src/domain/exceptions/circuit_breaker_exception.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('CircuitBreakerException', () {
    test('toString returns correct message', () {
      final Uri uri = Uri.parse('http://example.com');
      final http.Request request = http.Request('GET', uri);
      final CircuitBreakerException exception = CircuitBreakerException(
        request: request,
        cause: 'Too many failures',
      );

      expect(exception.toString(), equals('CircuitBreakerException: Too many failures'));
      expect(exception.request, equals(request));
      expect(exception.cause, equals('Too many failures'));
    });
  });
}
