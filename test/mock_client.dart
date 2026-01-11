import 'package:http/http.dart';
import 'package:http/testing.dart' as http_testing;

/// Creates a mock client for testing
MockClient createMockClient({int statusCode = 200, String body = '{}'}) {
  return http_testing.MockClient((BaseRequest request) async {
    return Response(
      body,
      statusCode,
      request: request,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}

/// Creates a mock client that throws an exception (simulates network failure)
MockClient createFailingMockClient(Exception exception) {
  return http_testing.MockClient((BaseRequest request) async {
    throw exception;
  });
}

/// Creates a mock client that waits for a future to complete
MockClient createDelayedMockClient(Future<Response> futureResponse) {
  return http_testing.MockClient((BaseRequest request) async {
    return futureResponse;
  });
}

/// Creates a mock client that calls a function for each request
MockClient createCountingMockClient(Response Function() handler) {
  return http_testing.MockClient((BaseRequest request) async {
    return handler();
  });
}

/// Type alias for MockClient
typedef MockClient = http_testing.MockClient;
