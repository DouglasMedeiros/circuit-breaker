import 'dart:core';

import 'package:http/http.dart';

import 'exception.dart';
import 'state.dart';

class CircuitBreaker {
  /// Client HTTP
  Client client = Client();

  /// Request
  final BaseRequest request;

  State _state;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime _nextAttempt;

  /// Failure threshold;
  final int failureThreshold;

  /// Success threshold
  final int successThreshold;

  /// Timeout
  final Duration timeout;

  CircuitBreaker({
    required this.request,
    this.failureThreshold = 3,
    this.successThreshold = 2,
    this.timeout = const Duration(milliseconds: 3500)})
      : _nextAttempt = DateTime.now(),
        _state = State.GREEN;

  /// Current state
  State get state => _state;

  /// Next attempt execution
  DateTime get nextAttempt => _nextAttempt;

  /// Execute
  Future<BaseResponse> execute() async {
    if (_state == State.RED) {
      if (_nextAttempt.millisecondsSinceEpoch <= DateTime.now().millisecondsSinceEpoch) {
        _state = State.YELLOW;
      } else {
        throw CircuitBreakerException(request: request,
            cause: 'Circuit suspended (${request.url}). You shall not pass!');
      }
    }

    final StreamedResponse response = await client.send(request);

    if (response.statusCode >= 200 && response.statusCode <= 299) {
      return _success(response);
    } else {
      return _failure(response);
    }
  }

  BaseResponse _success(BaseResponse response) {
    _failureCount = 0;

    if (_state == State.YELLOW) {
      _successCount++;

      if (_successCount > successThreshold) {
        _successCount = 0;
        _state = State.GREEN;
      }
    }

    return response;
  }

  BaseResponse _failure(BaseResponse response) {
    _failureCount++;

    if (_failureCount >= failureThreshold) {
      _state = State.RED;
      _nextAttempt = DateTime.now().add(timeout);
    }

    return response;
  }
}