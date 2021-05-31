import 'package:http/http.dart' as http;

class CircuitBreakerException implements Exception {
  String cause;
  http.BaseRequest request;

  CircuitBreakerException({required this.request, required this.cause});
}
