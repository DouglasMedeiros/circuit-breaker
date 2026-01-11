import 'dart:collection';

import 'package:clock/clock.dart';

/// Tracks request outcomes within a sliding time window
class SlidingWindow {
  final Duration _windowDuration;
  final Queue<_WindowEntry> _entries = Queue<_WindowEntry>();

  int _cachedSuccessCount = 0;
  int _cachedFailureCount = 0;

  /// Creates a sliding window with the specified duration
  SlidingWindow(this._windowDuration);

  /// Duration of the sliding window
  Duration get windowDuration => _windowDuration;

  /// Records a success in the window
  void recordSuccess() {
    _pruneOldEntries();
    _entries.add(_WindowEntry(clock.now(), true));
    _cachedSuccessCount++;
  }

  /// Records a failure in the window
  void recordFailure() {
    _pruneOldEntries();
    _entries.add(_WindowEntry(clock.now(), false));
    _cachedFailureCount++;
  }

  /// Total number of entries in the current window
  int get totalCount {
    _pruneOldEntries();
    return _entries.length;
  }

  /// Number of successful entries in the current window
  int get successCount {
    _pruneOldEntries();
    return _cachedSuccessCount;
  }

  /// Number of failed entries in the current window
  int get failureCount {
    _pruneOldEntries();
    return _cachedFailureCount;
  }

  /// Failure rate in the current window (0.0 to 1.0)
  double get failureRate {
    _pruneOldEntries();
    if (_entries.isEmpty) {
      return 0.0;
    }
    return _cachedFailureCount / _entries.length;
  }

  /// Success rate in the current window (0.0 to 1.0)
  double get successRate {
    _pruneOldEntries();
    if (_entries.isEmpty) {
      return 1.0;
    }
    return _cachedSuccessCount / _entries.length;
  }

  /// Clears all entries from the window
  void clear() {
    _entries.clear();
    _cachedSuccessCount = 0;
    _cachedFailureCount = 0;
  }

  void _pruneOldEntries() {
    final DateTime cutoff = clock.now().subtract(_windowDuration);
    while (_entries.isNotEmpty && _entries.first.timestamp.isBefore(cutoff)) {
      final _WindowEntry entry = _entries.removeFirst();
      if (entry.isSuccess) {
        _cachedSuccessCount--;
      } else {
        _cachedFailureCount--;
      }
    }
  }
}

class _WindowEntry {
  final DateTime timestamp;
  final bool isSuccess;

  _WindowEntry(this.timestamp, this.isSuccess);
}
