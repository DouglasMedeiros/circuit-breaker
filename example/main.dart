import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:http/http.dart';

void main() {
  final Request request = Request('POST', Uri.parse('http://example.com'));

  CircuitBreaker(
      request: request,
      failureThreshold: 3,
      successThreshold: 5,
      timeout: const Duration(seconds: 2));
}
