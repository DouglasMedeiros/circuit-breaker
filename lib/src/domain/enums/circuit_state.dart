/// Circuit breaker states
enum CircuitState {
  /// Closed - normal operation, requests flow through
  closed,

  /// Open - circuit tripped, requests blocked until timeout expires
  open,

  /// Half-open - testing recovery after timeout, counting successes
  halfOpen;

  @override
  String toString() {
    return switch (this) {
      CircuitState.closed => 'Closed',
      CircuitState.open => 'Open',
      CircuitState.halfOpen => 'Half-open',
    };
  }
}
