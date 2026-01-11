import 'package:circuit_breaker/src/domain/enums/circuit_state.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitState', () {
    test('toString returns correct string for each state', () {
      expect(CircuitState.closed.toString(), equals('Closed'));
      expect(CircuitState.open.toString(), equals('Open'));
      expect(CircuitState.halfOpen.toString(), equals('Half-open'));
    });
  });
}
