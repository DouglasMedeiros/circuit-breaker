/// Holds metrics and statistics for a circuit breaker
class CircuitBreakerMetrics {
  int _totalRequests = 0;
  int _totalSuccesses = 0;
  int _totalFailures = 0;
  int _totalRejected = 0;
  int _totalRetries = 0;
  int _totalFallbacks = 0;
  int _consecutiveFailures = 0;
  int _consecutiveSuccesses = 0;

  Duration _totalLatency = Duration.zero;
  Duration _minLatency = const Duration(days: 365);
  Duration _maxLatency = Duration.zero;

  /// Total number of requests attempted
  int get totalRequests => _totalRequests;

  /// Total number of successful requests
  int get totalSuccesses => _totalSuccesses;

  /// Total number of failed requests
  int get totalFailures => _totalFailures;

  /// Total number of rejected requests (circuit open)
  int get totalRejected => _totalRejected;

  /// Total number of retry attempts
  int get totalRetries => _totalRetries;

  /// Total number of times fallback was used
  int get totalFallbacks => _totalFallbacks;

  /// Current consecutive failure count
  int get consecutiveFailures => _consecutiveFailures;

  /// Current consecutive success count
  int get consecutiveSuccesses => _consecutiveSuccesses;

  /// Success rate as a percentage (0.0 to 1.0)
  double get successRate =>
      _totalRequests > 0 ? _totalSuccesses / _totalRequests : 1.0;

  /// Failure rate as a percentage (0.0 to 1.0)
  double get failureRate =>
      _totalRequests > 0 ? _totalFailures / _totalRequests : 0.0;

  /// Average latency of all requests
  Duration get averageLatency => _totalRequests > 0
      ? Duration(
          microseconds: _totalLatency.inMicroseconds ~/ _totalRequests,
        )
      : Duration.zero;

  /// Minimum latency recorded
  Duration get minLatency =>
      _minLatency == const Duration(days: 365) ? Duration.zero : _minLatency;

  /// Maximum latency recorded
  Duration get maxLatency => _maxLatency;

  /// Records a successful request
  void recordSuccess(Duration latency) {
    _totalRequests++;
    _totalSuccesses++;
    _consecutiveSuccesses++;
    _consecutiveFailures = 0;
    _recordLatency(latency);
  }

  /// Records a failed request
  void recordFailure(Duration latency) {
    _totalRequests++;
    _totalFailures++;
    _consecutiveFailures++;
    _consecutiveSuccesses = 0;
    _recordLatency(latency);
  }

  /// Records a rejected request
  void recordRejected() {
    _totalRejected++;
  }

  /// Records a retry attempt
  void recordRetry() {
    _totalRetries++;
  }

  /// Records a fallback usage
  void recordFallback() {
    _totalFallbacks++;
  }

  void _recordLatency(Duration latency) {
    _totalLatency += latency;
    if (latency < _minLatency) {
      _minLatency = latency;
    }
    if (latency > _maxLatency) {
      _maxLatency = latency;
    }
  }

  /// Resets all metrics to initial values
  void reset() {
    _totalRequests = 0;
    _totalSuccesses = 0;
    _totalFailures = 0;
    _totalRejected = 0;
    _totalRetries = 0;
    _totalFallbacks = 0;
    _consecutiveFailures = 0;
    _consecutiveSuccesses = 0;
    _totalLatency = Duration.zero;
    _minLatency = const Duration(days: 365);
    _maxLatency = Duration.zero;
  }

  /// Returns a snapshot of current metrics as a map
  Map<String, dynamic> toMap() => <String, dynamic>{
        'totalRequests': _totalRequests,
        'totalSuccesses': _totalSuccesses,
        'totalFailures': _totalFailures,
        'totalRejected': _totalRejected,
        'totalRetries': _totalRetries,
        'totalFallbacks': _totalFallbacks,
        'successRate': successRate,
        'failureRate': failureRate,
        'averageLatencyMs': averageLatency.inMilliseconds,
        'minLatencyMs': minLatency.inMilliseconds,
        'maxLatencyMs': maxLatency.inMilliseconds,
      };

  @override
  String toString() => 'CircuitBreakerMetrics(${toMap()})';
}
