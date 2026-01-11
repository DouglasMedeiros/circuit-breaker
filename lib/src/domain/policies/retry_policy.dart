/// Policy for retrying failed requests
class RetryPolicy {
  /// Maximum number of retry attempts
  final int maxRetries;

  /// Base delay between retries
  final Duration retryDelay;

  /// Whether to use exponential backoff for retries
  final bool useExponentialBackoff;

  /// Maximum delay between retries when using exponential backoff
  final Duration maxRetryDelay;

  /// Backoff multiplier for exponential backoff
  final double backoffMultiplier;

  /// Function to determine if a status code should trigger a retry
  final bool Function(int statusCode)? shouldRetryStatusCode;

  /// Function to determine if an exception should trigger a retry
  final bool Function(Object error)? shouldRetryException;

  /// Creates a new retry policy
  const RetryPolicy({
    this.maxRetries = 3,
    this.retryDelay = const Duration(milliseconds: 500),
    this.useExponentialBackoff = true,
    this.maxRetryDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.shouldRetryStatusCode,
    this.shouldRetryException,
  });

  /// No retry policy - requests are not retried
  static const RetryPolicy none = RetryPolicy(maxRetries: 0);

  /// Default retry policy with 3 retries and exponential backoff
  static const RetryPolicy defaultPolicy = RetryPolicy();

  /// Calculates the delay for a specific retry attempt
  Duration getDelayForAttempt(int attempt) {
    if (!useExponentialBackoff) {
      return retryDelay;
    }

    int multiplier = 1;
    for (int i = 0; i < attempt; i++) {
      multiplier = (multiplier * backoffMultiplier).round();
    }

    final Duration calculatedDelay = Duration(
      milliseconds: retryDelay.inMilliseconds * multiplier,
    );

    return calculatedDelay > maxRetryDelay ? maxRetryDelay : calculatedDelay;
  }

  /// Determines if a request should be retried based on status code
  bool shouldRetryForStatusCode(int statusCode) {
    if (shouldRetryStatusCode != null) {
      return shouldRetryStatusCode!(statusCode);
    }
    // Default: retry on 5xx server errors and 429 (too many requests)
    return statusCode >= 500 || statusCode == 429;
  }

  /// Determines if a request should be retried based on an exception
  bool shouldRetryForException(Object error) {
    if (shouldRetryException != null) {
      return shouldRetryException!(error);
    }
    // Default: retry on any exception (network errors, timeouts, etc.)
    return true;
  }
}
