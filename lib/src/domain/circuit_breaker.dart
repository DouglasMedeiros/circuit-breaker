import 'dart:async';

import 'package:clock/clock.dart';
import 'package:http/http.dart';

import 'enums/circuit_state.dart';
import 'events/circuit_breaker_events.dart';
import 'exceptions/circuit_breaker_exception.dart';
import 'models/circuit_breaker_metrics.dart';
import 'models/circuit_breaker_state.dart';
import 'models/sliding_window.dart';
import 'policies/retry_policy.dart';
import 'repositories/circuit_breaker_storage.dart';

/// Callback type for state change notifications
typedef StateChangeCallback = void Function(
  CircuitState previousState,
  CircuitState newState,
);

/// Callback type for fallback function
typedef FallbackCallback = Future<StreamedResponse> Function(
  BaseRequest request,
  Object? error,
);

/// Callback type for health check function
typedef HealthCheckCallback = Future<bool> Function();

/// Implementation of the Circuit Breaker design pattern.
///
/// The circuit breaker monitors requests (HTTP or generic functions) and automatically opens
/// (blocks requests) when failures exceed a threshold, allowing the
/// downstream service time to recover.
///
/// Features:
/// - Support for HTTP requests and generic asynchronous functions
/// - Exponential backoff for recovery timeouts
/// - Sliding window for failure rate calculation
/// - Health check support
/// - Fallback function support
/// - Retry policies
/// - Concurrency limiting (bulkhead pattern)
/// - Metrics and event streaming
/// - State persistence
class CircuitBreaker {
  // Registry for per-host/endpoint circuit breakers
  static final Map<String, CircuitBreaker> _registry =
      <String, CircuitBreaker>{};

  /// HTTP client used to send requests
  final Client _client;

  late final _StateController _stateController;
  late final _RequestExecutor _executor;

  late final _MetricsManager _metricsManager;

  // Event stream
  final StreamController<CircuitBreakerEvent> _eventController =
      StreamController<CircuitBreakerEvent>.broadcast();

  /// Number of consecutive failures before opening the circuit
  final int failureThreshold;

  /// Number of consecutive successes in half-open state before closing
  final int successThreshold;

  /// Base duration to wait before attempting recovery
  final Duration timeout;

  /// Optional callback invoked when state changes
  final StateChangeCallback? onStateChange;

  // === Exponential Backoff ===

  /// Whether to use exponential backoff for recovery timeouts
  final bool useExponentialBackoff;

  /// Multiplier for exponential backoff (default: 2.0)
  final double backoffMultiplier;

  /// Maximum timeout when using exponential backoff
  final Duration maxTimeout;

  // === Sliding Window ===

  /// Duration of the sliding window for failure rate calculation
  final Duration? windowDuration;

  /// Failure rate threshold (0.0 to 1.0) to open circuit
  final double? failureRateThreshold;

  /// Minimum number of requests in window before applying failure rate
  final int minimumRequestsInWindow;

  // === Health Check ===

  /// Health check function to verify service health
  final HealthCheckCallback? healthCheck;

  /// Interval between health checks when circuit is open
  final Duration healthCheckInterval;

  // === Fallback ===

  /// Fallback function when circuit is open or request fails
  final FallbackCallback? fallback;

  // === Request Timeout ===

  /// Timeout for individual requests (separate from recovery timeout)
  final Duration requestTimeout;

  // === Bulkhead (Concurrency Limiting) ===

  /// Maximum number of concurrent requests (0 = unlimited)
  final int maxConcurrentRequests;

  // === Retry Policy ===

  /// Retry policy for failed requests
  final RetryPolicy retryPolicy;

  // === Persistence ===

  /// Storage for persisting circuit breaker state
  final CircuitBreakerStorage? storage;

  /// Unique key for this circuit breaker (used for persistence and registry)
  final String? key;

  late final _HealthCheckMonitor _healthCheckMonitor;

  /// Creates a new [CircuitBreaker] instance.
  CircuitBreaker({
    Client? client,
    this.failureThreshold = 3,
    this.successThreshold = 2,
    this.timeout = const Duration(milliseconds: 3500),
    this.onStateChange,
    // Exponential backoff
    this.useExponentialBackoff = false,
    this.backoffMultiplier = 2.0,
    this.maxTimeout = const Duration(minutes: 5),
    // Sliding window
    this.windowDuration,
    this.failureRateThreshold,
    this.minimumRequestsInWindow = 10,
    // Health check
    this.healthCheck,
    this.healthCheckInterval = const Duration(seconds: 5),
    // Fallback
    this.fallback,
    // Request timeout
    this.requestTimeout = const Duration(seconds: 30),
    // Bulkhead
    this.maxConcurrentRequests = 0,
    // Retry
    this.retryPolicy = RetryPolicy.none,
    // Persistence
    this.storage,
    this.key,
  }) : _client = client ?? Client() {
    _metricsManager = _MetricsManager(
      windowDuration ?? const Duration(seconds: 60),
    );
    _stateController = _StateController(
      failureThreshold: failureThreshold,
      successThreshold: successThreshold,
      timeout: timeout,
      useExponentialBackoff: useExponentialBackoff,
      backoffMultiplier: backoffMultiplier,
      maxTimeout: maxTimeout,
    );
    _executor = _RequestExecutor(
      client: _client,
      requestTimeout: requestTimeout,
      maxConcurrentRequests: maxConcurrentRequests,
      retryPolicy: retryPolicy,
    );
    _healthCheckMonitor = _HealthCheckMonitor(
      healthCheck: healthCheck,
      healthCheckInterval: healthCheckInterval,
    );
  }

  /// Gets or creates a circuit breaker for a specific host
  static CircuitBreaker forHost(
    String host, {
    Client? client,
    int failureThreshold = 3,
    int successThreshold = 2,
    Duration timeout = const Duration(milliseconds: 3500),
    StateChangeCallback? onStateChange,
    bool useExponentialBackoff = false,
    double backoffMultiplier = 2.0,
    Duration maxTimeout = const Duration(minutes: 5),
    Duration? windowDuration,
    double? failureRateThreshold,
    int minimumRequestsInWindow = 10,
    HealthCheckCallback? healthCheck,
    Duration healthCheckInterval = const Duration(seconds: 5),
    FallbackCallback? fallback,
    Duration requestTimeout = const Duration(seconds: 30),
    int maxConcurrentRequests = 0,
    RetryPolicy retryPolicy = RetryPolicy.none,
    CircuitBreakerStorage? storage,
  }) {
    final String registryKey = 'host:$host';
    return _registry.putIfAbsent(
      registryKey,
      () => CircuitBreaker(
        client: client,
        failureThreshold: failureThreshold,
        successThreshold: successThreshold,
        timeout: timeout,
        onStateChange: onStateChange,
        useExponentialBackoff: useExponentialBackoff,
        backoffMultiplier: backoffMultiplier,
        maxTimeout: maxTimeout,
        windowDuration: windowDuration,
        failureRateThreshold: failureRateThreshold,
        minimumRequestsInWindow: minimumRequestsInWindow,
        healthCheck: healthCheck,
        healthCheckInterval: healthCheckInterval,
        fallback: fallback,
        requestTimeout: requestTimeout,
        maxConcurrentRequests: maxConcurrentRequests,
        retryPolicy: retryPolicy,
        storage: storage,
        key: registryKey,
      ),
    );
  }

  /// Gets or creates a circuit breaker for a specific endpoint
  static CircuitBreaker forEndpoint(
    Uri endpoint, {
    Client? client,
    int failureThreshold = 3,
    int successThreshold = 2,
    Duration timeout = const Duration(milliseconds: 3500),
    StateChangeCallback? onStateChange,
    bool useExponentialBackoff = false,
    double backoffMultiplier = 2.0,
    Duration maxTimeout = const Duration(minutes: 5),
    Duration? windowDuration,
    double? failureRateThreshold,
    int minimumRequestsInWindow = 10,
    HealthCheckCallback? healthCheck,
    Duration healthCheckInterval = const Duration(seconds: 5),
    FallbackCallback? fallback,
    Duration requestTimeout = const Duration(seconds: 30),
    int maxConcurrentRequests = 0,
    RetryPolicy retryPolicy = RetryPolicy.none,
    CircuitBreakerStorage? storage,
  }) {
    final String registryKey = 'endpoint:${endpoint.toString()}';
    return _registry.putIfAbsent(
      registryKey,
      () => CircuitBreaker(
        client: client,
        failureThreshold: failureThreshold,
        successThreshold: successThreshold,
        timeout: timeout,
        onStateChange: onStateChange,
        useExponentialBackoff: useExponentialBackoff,
        backoffMultiplier: backoffMultiplier,
        maxTimeout: maxTimeout,
        windowDuration: windowDuration,
        failureRateThreshold: failureRateThreshold,
        minimumRequestsInWindow: minimumRequestsInWindow,
        healthCheck: healthCheck,
        healthCheckInterval: healthCheckInterval,
        fallback: fallback,
        requestTimeout: requestTimeout,
        maxConcurrentRequests: maxConcurrentRequests,
        retryPolicy: retryPolicy,
        storage: storage,
        key: registryKey,
      ),
    );
  }

  /// Clears all registered circuit breakers
  static void clearRegistry() {
    for (final CircuitBreaker cb in _registry.values) {
      cb.dispose();
    }
    _registry.clear();
  }

  /// Gets a registered circuit breaker by key
  static CircuitBreaker? getByKey(String key) => _registry[key];

  /// Current state of the circuit breaker
  CircuitState get state => _stateController.state;

  /// When the circuit will attempt recovery (only relevant when open)
  DateTime get nextAttempt => _stateController.nextAttempt;

  /// Current failure count
  int get failureCount => _stateController.failureCount;

  /// Current success count (relevant in half-open state)
  int get successCount => _stateController.successCount;

  /// Number of times the circuit has opened consecutively
  int get consecutiveOpenings => _stateController.consecutiveOpenings;

  /// Number of requests currently in progress
  int get pendingRequests => _executor.pendingRequests;

  /// Whether the circuit is allowing requests
  bool get isAllowingRequests =>
      state != CircuitState.open || _stateController.canAttemptRecovery;

  /// Metrics for this circuit breaker
  CircuitBreakerMetrics get metrics => _metricsManager.metrics;

  /// Stream of circuit breaker events
  Stream<CircuitBreakerEvent> get events => _eventController.stream;

  /// Current failure rate from sliding window
  double get currentFailureRate => _metricsManager.failureRate;

  /// Total requests in sliding window
  int get requestsInWindow => _metricsManager.totalCount;

  /// Executes a generic asynchronous function through the circuit breaker.
  Future<T> execute<T>(
    Future<T> Function() function, {
    Future<T> Function(Object error)? fallback,
  }) async {
    // Check bulkhead limit
    if (maxConcurrentRequests > 0 && pendingRequests >= maxConcurrentRequests) {
      _metricsManager.recordRejected();
      _emitEvent(
          () => RequestRejectedEvent(url: null, nextAttempt: clock.now()));

      if (fallback != null) {
        _metricsManager.recordFallback();
        _emitEvent(() => FallbackUsedEvent(
            originalError: 'Max concurrent requests exceeded'));
        return fallback('Max concurrent requests exceeded');
      }

      throw CircuitBreakerBulkheadException(
          'Max concurrent requests ($maxConcurrentRequests) exceeded',
          limit: maxConcurrentRequests);
    }

    // Check circuit state
    if (state == CircuitState.open) {
      if (_stateController.canAttemptRecovery) {
        _transitionTo(CircuitState.halfOpen);
      } else {
        _metricsManager.recordRejected();
        _emitEvent(
            () => RequestRejectedEvent(url: null, nextAttempt: nextAttempt));

        if (fallback != null) {
          _metricsManager.recordFallback();
          _emitEvent(() => FallbackUsedEvent(originalError: 'Circuit open'));
          return fallback('Circuit open');
        }

        throw CircuitBreakerOpenException(
            'Circuit suspended. Retry after $nextAttempt',
            nextAttempt: nextAttempt);
      }
    }

    _executor.incrementPending();
    final DateTime startTime = clock.now();

    try {
      final T result = await _executor.executeFunctionWithRetry(
        function,
        onRetry: () => _metricsManager.recordRetry(),
        onRetryEvent: (attempt, maxRetries, error) {
          _emitEvent(() => RequestRetryEvent(
              attempt: attempt, maxRetries: maxRetries, error: error));
        },
      );
      final Duration duration = clock.now().difference(startTime);

      _onSuccess(duration);

      return result;
    } catch (e) {
      final Duration duration = clock.now().difference(startTime);
      _onFailure(duration, error: e);

      if (fallback != null) {
        _metricsManager.recordFallback();
        _emitEvent(() => FallbackUsedEvent(originalError: e));
        return fallback(e);
      }

      rethrow;
    } finally {
      _executor.decrementPending();
    }
  }

  /// Executes an HTTP request through the circuit breaker.
  ///
  /// Throws [CircuitBreakerException] if the circuit is open and
  /// the timeout has not elapsed and no fallback is configured.
  Future<StreamedResponse> executeRequest(BaseRequest request) async {
    // Check bulkhead limit
    if (maxConcurrentRequests > 0 && pendingRequests >= maxConcurrentRequests) {
      _metricsManager.recordRejected();
      _emitEvent(() => RequestRejectedEvent(url: request.url, nextAttempt: clock.now()));

      if (fallback != null) {
        _metricsManager.recordFallback();
        _emitEvent(() => FallbackUsedEvent(
              originalError: 'Max concurrent requests exceeded',
            ));
        return fallback!(request, 'Max concurrent requests exceeded');
      }

      throw CircuitBreakerBulkheadException(
        'Max concurrent requests ($maxConcurrentRequests) exceeded',
        limit: maxConcurrentRequests,
      );
    }

    // Check circuit state
    if (state == CircuitState.open) {
      if (_stateController.canAttemptRecovery) {
        _transitionTo(CircuitState.halfOpen);
      } else {
        _metricsManager.recordRejected();
        _emitEvent(() => RequestRejectedEvent(
              url: request.url,
              nextAttempt: nextAttempt,
            ));

        if (fallback != null) {
          _metricsManager.recordFallback();
          _emitEvent(() => FallbackUsedEvent(originalError: 'Circuit open'));
          return fallback!(request, 'Circuit open');
        }

        throw CircuitBreakerOpenException(
          'Circuit suspended (${request.url}). Retry after $nextAttempt',
          nextAttempt: nextAttempt,
        );
      }
    }

    _executor.incrementPending();
    final DateTime startTime = clock.now();

    try {
      final StreamedResponse response = await _executor.executeWithRetry(
        request,
        onRetry: () => _metricsManager.recordRetry(),
        onRetryEvent: (attempt, maxRetries, error) {
          _emitEvent(() => RequestRetryEvent(
              attempt: attempt, maxRetries: maxRetries, error: error));
        },
      );
      final Duration duration = clock.now().difference(startTime);

      if (response.statusCode >= 200 && response.statusCode <= 299) {
        _onSuccess(duration, statusCode: response.statusCode);
      } else {
        _onFailure(duration, statusCode: response.statusCode);
      }

      return response;
    } catch (e) {
      final Duration duration = clock.now().difference(startTime);
      _onFailure(duration, error: e);

      if (fallback != null) {
        _metricsManager.recordFallback();
        _emitEvent(() => FallbackUsedEvent(originalError: e));
        return fallback!(request, e);
      }

      if (e is TimeoutException) {
        throw CircuitBreakerTimeoutException(
          'Request timed out',
          timeout: requestTimeout,
        );
      } else if (e is ClientException) {
        throw CircuitBreakerNetworkException(
          'Network error: ${e.message}',
          originalError: e,
        );
      }

      rethrow;
    } finally {
      _executor.decrementPending();
    }
  }

  /// Resets the circuit breaker to its initial closed state.
  void reset() {
    _stateController.reset();
    _metricsManager.clear();
    _stopHealthCheck();
    _transitionTo(CircuitState.closed);
  }

  /// Saves the current state to storage
  Future<void> saveState() async {
    if (storage == null || key == null) {
      return;
    }

    final CircuitBreakerState savedState = CircuitBreakerState(
      state: state,
      failureCount: failureCount,
      successCount: successCount,
      nextAttempt: nextAttempt,
      savedAt: clock.now(),
      consecutiveOpenings: consecutiveOpenings,
    );

    await storage!.save(key!, savedState);
  }

  /// Restores state from storage
  Future<bool> restoreState() async {
    if (storage == null || key == null) {
      return false;
    }

    final CircuitBreakerState? savedState = await storage!.load(key!);
    if (savedState == null) {
      return false;
    }

    _stateController.restore(savedState);

    // Start health check if circuit is open
    if (state == CircuitState.open && healthCheck != null) {
      _startHealthCheck();
    }

    return true;
  }

  /// Disposes resources used by this circuit breaker
  void dispose() {
    _stopHealthCheck();
    _eventController.close();
  }

  void _transitionTo(CircuitState newState) {
    _stateController.transitionTo(
      newState,
      onTransition: (previousState, newState) {
        _emitEvent(() => StateChangedEvent(
              previousState: previousState,
              newState: newState,
            ));

        onStateChange?.call(previousState, newState);

        // Handle health check timer
        if (newState == CircuitState.open && healthCheck != null) {
          _startHealthCheck();
        } else if (newState != CircuitState.open) {
          _stopHealthCheck();
        }
      },
    );
  }

  void _onSuccess(Duration latency, {int? statusCode}) {
    _stateController.incrementSuccess();
    _metricsManager.recordSuccess(latency);

    _emitEvent(() => RequestSuccessEvent(
          statusCode: statusCode,
          duration: latency,
        ));

    if (state == CircuitState.halfOpen) {
      if (successCount >= successThreshold) {
        _stateController.reset(); // Reset counters and transition to closed
        _transitionTo(CircuitState.closed);
      }
    }
  }

  void _onFailure(Duration latency, {int? statusCode, Object? error}) {
    _stateController.incrementFailure();
    _metricsManager.recordFailure(latency);

    _emitEvent(() => RequestFailureEvent(
          statusCode: statusCode,
          error: error,
          duration: latency,
        ));

    bool shouldOpen = false;

    if (state == CircuitState.halfOpen) {
      // Any failure in half-open state immediately opens the circuit
      shouldOpen = true;
    } else if (failureCount >= failureThreshold) {
      shouldOpen = true;
    } else if (_shouldOpenBasedOnFailureRate()) {
      shouldOpen = true;
    }

    if (shouldOpen) {
      _openCircuit();
    }
  }

  bool _shouldOpenBasedOnFailureRate() {
    if (failureRateThreshold == null) {
      return false;
    }

    if (_metricsManager.totalCount < minimumRequestsInWindow) {
      return false;
    }

    return _metricsManager.failureRate >= failureRateThreshold!;
  }

  void _openCircuit() {
    _stateController.openCircuit();
    _transitionTo(CircuitState.open);
  }

  void _startHealthCheck() {
    _healthCheckMonitor.start(_performHealthCheck);
  }

  void _stopHealthCheck() {
    _healthCheckMonitor.stop();
  }

  Future<void> _performHealthCheck() async {
    await _healthCheckMonitor.performHealthCheck(
      currentState: state,
      onEvent: (isHealthy, duration) {
        _emitEvent(() => HealthCheckEvent(
              isHealthy: isHealthy,
              duration: duration,
            ));
      },
      onHealthy: () {
        _transitionTo(CircuitState.halfOpen);
      },
    );
  }

  void _emitEvent(CircuitBreakerEvent Function() eventProvider) {
    if (!_eventController.isClosed && _eventController.hasListener) {
      _eventController.add(eventProvider());
    }
  }
}

/// Private manager for metrics and sliding window calculations
class _MetricsManager {
  final SlidingWindow _slidingWindow;
  final CircuitBreakerMetrics _metrics = CircuitBreakerMetrics();

  _MetricsManager(Duration windowDuration)
      : _slidingWindow = SlidingWindow(windowDuration);

  void recordSuccess(Duration latency) {
    _slidingWindow.recordSuccess();
    _metrics.recordSuccess(latency);
  }

  void recordFailure(Duration latency) {
    _slidingWindow.recordFailure();
    _metrics.recordFailure(latency);
  }

  void recordRejected() => _metrics.recordRejected();
  void recordFallback() => _metrics.recordFallback();
  void recordRetry() => _metrics.recordRetry();

  double get failureRate => _slidingWindow.failureRate;
  int get totalCount => _slidingWindow.totalCount;
  void clear() => _slidingWindow.clear();
  CircuitBreakerMetrics get metrics => _metrics;
}

/// Private controller for managing circuit breaker state transitions
class _StateController {
  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  int _consecutiveOpenings = 0;
  DateTime _nextAttempt = clock.now();

  final int failureThreshold;
  final int successThreshold;
  final Duration timeout;
  final bool useExponentialBackoff;
  final double backoffMultiplier;
  final Duration maxTimeout;

  _StateController({
    required this.failureThreshold,
    required this.successThreshold,
    required this.timeout,
    required this.useExponentialBackoff,
    required this.backoffMultiplier,
    required this.maxTimeout,
  });

  CircuitState get state => _state;
  DateTime get nextAttempt => _nextAttempt;
  int get failureCount => _failureCount;
  int get successCount => _successCount;
  int get consecutiveOpenings => _consecutiveOpenings;

  bool get canAttemptRecovery =>
      _nextAttempt.millisecondsSinceEpoch <= clock.now().millisecondsSinceEpoch;

  void transitionTo(CircuitState newState,
      {void Function(CircuitState, CircuitState)? onTransition}) {
    if (_state != newState) {
      final CircuitState previousState = _state;
      _state = newState;
      onTransition?.call(previousState, newState);
    }
  }

  void incrementFailure() {
    _successCount = 0;
    _failureCount++;
  }

  void incrementSuccess() {
    _failureCount = 0;
    if (_state == CircuitState.halfOpen) {
      _successCount++;
    }
  }

  void openCircuit() {
    if (_state != CircuitState.open) {
      _consecutiveOpenings++;
    }
    _nextAttempt = clock.now().add(_calculateRecoveryTimeout());
  }

  void reset() {
    _failureCount = 0;
    _successCount = 0;
    _consecutiveOpenings = 0;
  }

  Duration _calculateRecoveryTimeout() {
    if (!useExponentialBackoff || _consecutiveOpenings <= 1) {
      return timeout;
    }

    int multiplier = 1;
    for (int i = 1; i < _consecutiveOpenings; i++) {
      multiplier = (multiplier * backoffMultiplier).round();
    }

    final Duration calculatedTimeout = Duration(
      milliseconds: timeout.inMilliseconds * multiplier,
    );

    return calculatedTimeout > maxTimeout ? maxTimeout : calculatedTimeout;
  }

  void restore(CircuitBreakerState savedState) {
    _state = savedState.state;
    _failureCount = savedState.failureCount;
    _successCount = savedState.successCount;
    _nextAttempt = savedState.nextAttempt;
    _consecutiveOpenings = savedState.consecutiveOpenings;
  }
}

/// Private executor for handling request attempts and retries
class _RequestExecutor {
  final Client _client;
  final Duration requestTimeout;
  final int maxConcurrentRequests;
  final RetryPolicy retryPolicy;
  int _pendingRequests = 0;

  _RequestExecutor({
    required Client client,
    required this.requestTimeout,
    required this.maxConcurrentRequests,
    required this.retryPolicy,
  }) : _client = client;

  int get pendingRequests => _pendingRequests;

  Future<T> executeFunctionWithRetry<T>(
    Future<T> Function() function, {
    required void Function() onRetry,
    required void Function(int attempt, int maxRetries, Object error)
        onRetryEvent,
  }) async {
    int attempt = 0;

    while (true) {
      try {
        return await function();
      } catch (e) {
        if (attempt < retryPolicy.maxRetries &&
            retryPolicy.shouldRetryForException(e)) {
          attempt++;

          onRetry();
          onRetryEvent(attempt, retryPolicy.maxRetries, e);

          final Duration delay = retryPolicy.getDelayForAttempt(attempt);
          await Future<void>.delayed(delay);

          continue;
        }

        rethrow;
      }
    }
  }

  Future<StreamedResponse> executeWithRetry(
    BaseRequest request, {
    required void Function() onRetry,
    required void Function(int attempt, int maxRetries, Object error)
        onRetryEvent,
  }) async {
    int attempt = 0;

    while (true) {
      try {
        final BaseRequest requestToSend = _copyRequest(request);

        return await _client.send(requestToSend).timeout(requestTimeout);
      } catch (e) {
        if (attempt < retryPolicy.maxRetries &&
            retryPolicy.shouldRetryForException(e)) {
          attempt++;

          onRetry();
          onRetryEvent(attempt, retryPolicy.maxRetries, e);

          final Duration delay = retryPolicy.getDelayForAttempt(attempt);
          await Future<void>.delayed(delay);

          continue;
        }

        rethrow;
      }
    }
  }

  BaseRequest _copyRequest(BaseRequest request) {
    if (request is Request) {
      final Request copy = Request(request.method, request.url)
        ..encoding = request.encoding
        ..bodyBytes = request.bodyBytes;

      _copyBaseRequestProperties(request, copy);

      return copy;
    }

    if (request is MultipartRequest) {
      final MultipartRequest copy =
          MultipartRequest(request.method, request.url)
            ..fields.addAll(request.fields)
            ..files.addAll(request.files);

      _copyBaseRequestProperties(request, copy);

      return copy;
    }

    return request;
  }

  void _copyBaseRequestProperties(BaseRequest source, BaseRequest destination) {
    destination
      ..headers.addAll(source.headers)
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection;
  }

  void incrementPending() => _pendingRequests++;
  void decrementPending() => _pendingRequests--;
}

/// Private monitor for managing service health checks
class _HealthCheckMonitor {
  final HealthCheckCallback? healthCheck;
  final Duration healthCheckInterval;
  Timer? _healthCheckTimer;

  _HealthCheckMonitor({
    required this.healthCheck,
    required this.healthCheckInterval,
  });

  void start(Future<void> Function() onPerformHealthCheck) {
    stop();

    if (healthCheck != null) {
      _healthCheckTimer = Timer.periodic(
        healthCheckInterval,
        (_) => onPerformHealthCheck(),
      );
    }
  }

  void stop() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Future<void> performHealthCheck({
    required CircuitState currentState,
    required void Function(bool isHealthy, Duration duration) onEvent,
    required void Function() onHealthy,
  }) async {
    if (healthCheck == null || currentState != CircuitState.open) {
      return;
    }

    final DateTime startTime = clock.now();

    try {
      final bool isHealthy = await healthCheck!();
      final Duration duration = clock.now().difference(startTime);

      onEvent(isHealthy, duration);

      if (isHealthy) {
        onHealthy();
      }
    } catch (e) {
      final Duration duration = clock.now().difference(startTime);

      onEvent(false, duration);
    }
  }
}
