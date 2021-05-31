import 'package:meta/meta.dart';

/// State Circuit
class State {
  /// GREEN (Closed)
  static const State GREEN = State.fromCode(0);

  /// RED (Open)
  static const State RED = State.fromCode(1);

  /// YELLOW (Half open)
  static const State YELLOW = State.fromCode(2);

  /// All states
  static List<State> get values => <State>[GREEN, RED, YELLOW];

  /// Value state
  final int value;

  @override
  String toString() {
    if (value == 0) {
      return 'Closed';
    } else if (value == 1) {
      return 'Open';
    } else if (value == 2) {
      return 'Half open';
    }

    throw Exception('Not implemented!');
  }

  @visibleForTesting
  const State.fromCode(this.value);
}
