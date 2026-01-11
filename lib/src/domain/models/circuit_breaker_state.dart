import '../enums/circuit_state.dart';

/// Represents the persisted state of a circuit breaker
class CircuitBreakerState {
  /// Current circuit state
  final CircuitState state;

  /// Number of consecutive failures
  final int failureCount;

  /// Number of consecutive successes
  final int successCount;

  /// When the circuit will next attempt recovery
  final DateTime nextAttempt;

  /// When this state was saved
  final DateTime savedAt;

  /// Number of consecutive circuit openings (for exponential backoff)
  final int consecutiveOpenings;

  /// Creates a new circuit breaker state
  CircuitBreakerState({
    required this.state,
    required this.failureCount,
    required this.successCount,
    required this.nextAttempt,
    required this.savedAt,
    this.consecutiveOpenings = 0,
  });

  /// Creates a state from a JSON map
  factory CircuitBreakerState.fromJson(Map<String, dynamic> json) {
    return CircuitBreakerState(
      state: CircuitState.values.firstWhere(
        (CircuitState s) => s.name == json['state'],
        orElse: () => CircuitState.closed,
      ),
      failureCount: json['failureCount'] as int? ?? 0,
      successCount: json['successCount'] as int? ?? 0,
      nextAttempt: DateTime.parse(json['nextAttempt'] as String),
      savedAt: DateTime.parse(json['savedAt'] as String),
      consecutiveOpenings: json['consecutiveOpenings'] as int? ?? 0,
    );
  }

  /// Converts the state to a JSON map
  Map<String, dynamic> toJson() => <String, dynamic>{
        'state': state.name,
        'failureCount': failureCount,
        'successCount': successCount,
        'nextAttempt': nextAttempt.toIso8601String(),
        'savedAt': savedAt.toIso8601String(),
        'consecutiveOpenings': consecutiveOpenings,
      };

  @override
  String toString() => 'CircuitBreakerState(${toJson()})';
}
