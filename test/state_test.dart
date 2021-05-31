import 'package:circuit_breaker/circuit_breaker.dart';
import 'package:test/test.dart';

void main() {
  test('Should_Returns_Closed', () async {
    final State state = State.GREEN;
    expect(state.toString(), 'Closed');
  });

  test('Should_Returns_Open', () async {
    final State state = State.RED;
    expect(state.toString(), 'Open');
  });

  test('Should_Returns_HalfOpen', () async {
    final State state = State.YELLOW;
    expect(state.toString(), 'Half open');
  });

  test('Should_Returns_CountTotal', () async {
    final List<State> states = State.values;
    expect(states.length, 3);
    expect(states.contains(State.GREEN), true);
    expect(states.contains(State.RED), true);
    expect(states.contains(State.YELLOW), true);
  });

  test('Should_Fail_CreateStateNotExists', () async {
    expect(() => const State.fromCode(99),
        throwsA(predicate((Object? e) => e is Exception)));
  });
}
