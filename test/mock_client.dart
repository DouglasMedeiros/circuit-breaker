import 'dart:typed_data';

import 'package:http/http.dart';

class MockClient extends BaseClient {
  final MockClientStreamHandler _handler;

  MockClient._(this._handler);

  // ignore: sort_unnamed_constructors_first
  MockClient(MockClientHandler fn)
      : this._((BaseRequest baseRequest, ByteStream bodyStream) async {
    final Uint8List bodyBytes = await bodyStream.toBytes();
    final Request request = Request(baseRequest.method, baseRequest.url)
      ..persistentConnection = baseRequest.persistentConnection
      ..followRedirects = baseRequest.followRedirects
      ..maxRedirects = baseRequest.maxRedirects
      ..headers.addAll(baseRequest.headers)
      ..bodyBytes = bodyBytes
      ..finalize();

    final Response response = await fn(request);
    return StreamedResponse(
        ByteStream.fromBytes(response.bodyBytes), response.statusCode,
        contentLength: response.contentLength,
        request: baseRequest,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase);
  });

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    // ignore: always_specify_types
    ByteStream bodyStream = const ByteStream(Stream.empty());
    if (!request.finalized) {
      bodyStream = request.finalize();
    }
    return await _handler(request, bodyStream);
  }
}

typedef MockClientStreamHandler = Future<StreamedResponse> Function(
    BaseRequest request, ByteStream bodyStream);

typedef MockClientHandler = Future<Response> Function(Request request);