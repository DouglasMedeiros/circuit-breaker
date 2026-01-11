import 'package:circuit_breaker/src/domain/enums/circuit_state.dart';
import 'package:circuit_breaker/src/domain/events/circuit_breaker_events.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreakerEvent', () {
    test('StateChangedEvent toString', () {
      final StateChangedEvent event = StateChangedEvent(
        previousState: CircuitState.closed,
        newState: CircuitState.open,
      );
      expect(event.toString(), 'StateChangedEvent(Closed -> Open)');
      expect(event.timestamp, isNotNull);
    });

    test('RequestSuccessEvent toString', () {
      final RequestSuccessEvent event = RequestSuccessEvent(
        statusCode: 200,
        duration: const Duration(milliseconds: 100),
      );
      expect(
        event.toString(),
        'RequestSuccessEvent(status: 200, duration: 0:00:00.100000)',
      );
    });

    test('RequestFailureEvent toString', () {
      final RequestFailureEvent event = RequestFailureEvent(
        statusCode: 500,
        error: 'Error',
        duration: const Duration(milliseconds: 100),
      );
      expect(
        event.toString(),
        'RequestFailureEvent(status: 500, error: Error)',
      );
    });

    test('RequestRejectedEvent toString', () {
      final DateTime now = DateTime(2023, 1, 1);
      final RequestRejectedEvent event = RequestRejectedEvent(
        url: Uri.parse('http://example.com'),
        nextAttempt: now,
      );
      expect(
        event.toString(),
        'RequestRejectedEvent(url: http://example.com, nextAttempt: $now)',
      );
    });

    test('RequestRetryEvent toString', () {
      final RequestRetryEvent event = RequestRetryEvent(
        attempt: 1,
        maxRetries: 3,
        error: 'Error',
      );
      expect(event.toString(), 'RequestRetryEvent(attempt: 1/3)');
    });

    test('FallbackUsedEvent toString', () {
      final FallbackUsedEvent event = FallbackUsedEvent(originalError: 'Error');
      expect(event.toString(), 'FallbackUsedEvent(error: Error)');
    });

    test('HealthCheckEvent toString', () {
      final HealthCheckEvent event = HealthCheckEvent(
        isHealthy: true,
        duration: const Duration(milliseconds: 50),
      );
      expect(
        event.toString(),
        'HealthCheckEvent(healthy: true, duration: 0:00:00.050000)',
      );
    });
  });
}
