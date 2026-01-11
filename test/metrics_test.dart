import 'package:circuit_breaker/src/domain/models/circuit_breaker_metrics.dart';
import 'package:circuit_breaker/src/domain/models/sliding_window.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreakerMetrics', () {
    test('initial values are correct', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      expect(metrics.totalRequests, 0);
      expect(metrics.totalSuccesses, 0);
      expect(metrics.totalFailures, 0);
      expect(metrics.totalRejected, 0);
      expect(metrics.totalRetries, 0);
      expect(metrics.totalFallbacks, 0);
      expect(metrics.consecutiveFailures, 0);
      expect(metrics.consecutiveSuccesses, 0);
      expect(metrics.successRate, 1.0); // Default when no requests
      expect(metrics.failureRate, 0.0);
      expect(metrics.averageLatency, Duration.zero);
      expect(metrics.minLatency, Duration.zero);
      expect(metrics.maxLatency, Duration.zero);
    });

    test('toString returns correct format', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      expect(metrics.toString(), contains('CircuitBreakerMetrics'));
      expect(metrics.toString(), contains('totalRequests: 0'));
    });

    test('recordSuccess updates metrics correctly', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      metrics.recordSuccess(const Duration(milliseconds: 100));

      expect(metrics.totalRequests, 1);
      expect(metrics.totalSuccesses, 1);
      expect(metrics.totalFailures, 0);
      expect(metrics.consecutiveSuccesses, 1);
      expect(metrics.consecutiveFailures, 0);
      expect(metrics.successRate, 1.0);
      expect(metrics.failureRate, 0.0);
    });

    test('recordFailure updates metrics correctly', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      metrics.recordFailure(const Duration(milliseconds: 100));

      expect(metrics.totalRequests, 1);
      expect(metrics.totalSuccesses, 0);
      expect(metrics.totalFailures, 1);
      expect(metrics.consecutiveSuccesses, 0);
      expect(metrics.consecutiveFailures, 1);
      expect(metrics.successRate, 0.0);
      expect(metrics.failureRate, 1.0);
    });

    test('consecutive counts reset correctly', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      
      // Success -> Failure
      metrics.recordSuccess(Duration.zero);
      expect(metrics.consecutiveSuccesses, 1);
      expect(metrics.consecutiveFailures, 0);
      
      metrics.recordFailure(Duration.zero);
      expect(metrics.consecutiveSuccesses, 0);
      expect(metrics.consecutiveFailures, 1);

      // Failure -> Success
      metrics.recordSuccess(Duration.zero);
      expect(metrics.consecutiveSuccesses, 1);
      expect(metrics.consecutiveFailures, 0);
    });

    test('recordRejected increments count', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      metrics.recordRejected();
      expect(metrics.totalRejected, 1);
    });

    test('recordRetry increments count', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      metrics.recordRetry();
      expect(metrics.totalRetries, 1);
    });

    test('recordFallback increments count', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      metrics.recordFallback();
      expect(metrics.totalFallbacks, 1);
    });

    test('tracks latency correctly', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      metrics.recordSuccess(const Duration(milliseconds: 100));
      metrics.recordSuccess(const Duration(milliseconds: 300));

      expect(metrics.minLatency, const Duration(milliseconds: 100));
      expect(metrics.maxLatency, const Duration(milliseconds: 300));
      expect(metrics.averageLatency, const Duration(milliseconds: 200));
    });
    
    test('minLatency returns zero if no requests', () {
       final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
       expect(metrics.minLatency, Duration.zero);
    });

    test('reset clears all metrics', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      metrics.recordSuccess(const Duration(milliseconds: 100));
      metrics.recordFailure(const Duration(milliseconds: 100));
      metrics.recordRejected();
      metrics.recordRetry();
      metrics.recordFallback();

      metrics.reset();
      
      expect(metrics.totalRequests, 0);
      expect(metrics.totalSuccesses, 0);
      expect(metrics.totalFailures, 0);
      expect(metrics.totalRejected, 0);
      expect(metrics.totalRetries, 0);
      expect(metrics.totalFallbacks, 0);
      expect(metrics.consecutiveFailures, 0);
      expect(metrics.consecutiveSuccesses, 0);
      expect(metrics.minLatency, Duration.zero);
      expect(metrics.maxLatency, Duration.zero);
      expect(metrics.averageLatency, Duration.zero);
    });
    
    test('toMap includes all fields', () {
      final CircuitBreakerMetrics metrics = CircuitBreakerMetrics();
      metrics.recordSuccess(const Duration(milliseconds: 100));
      
      final Map<String, dynamic> map = metrics.toMap();
      expect(map.keys, containsAll(<String>[
        'totalRequests', 'totalSuccesses', 'totalFailures', 
        'totalRejected', 'totalRetries', 'totalFallbacks',
        'successRate', 'failureRate', 'averageLatencyMs',
        'minLatencyMs', 'maxLatencyMs'
      ]));
    });
  });

  group('SlidingWindow', () {
    test('initial values are correct', () {
      final SlidingWindow window = SlidingWindow(const Duration(seconds: 1));
      expect(window.windowDuration, const Duration(seconds: 1));
      expect(window.totalCount, 0);
      expect(window.successCount, 0);
      expect(window.failureCount, 0);
      expect(window.successRate, 1.0);
      expect(window.failureRate, 0.0);
    });

    test('calculates rates correctly', () {
      fakeAsync((FakeAsync async) {
        final SlidingWindow window = SlidingWindow(const Duration(seconds: 10));
        window.recordSuccess();
        window.recordFailure();

        expect(window.totalCount, 2);
        expect(window.successRate, 0.5);
        expect(window.failureRate, 0.5);
      });
    });

    test('prunes old entries', () {
      fakeAsync((FakeAsync async) {
        final SlidingWindow window = SlidingWindow(const Duration(seconds: 10));
        
        // Add entry at T=0
        window.recordSuccess();
        expect(window.totalCount, 1);
        
        // Move to T=11 (past window)
        async.elapse(const Duration(seconds: 11));
        
        // Pruning happens on access/write
        expect(window.totalCount, 0);
        expect(window.successCount, 0);
        expect(window.failureCount, 0);
      });
    });
    
    test('prunes old entries on new record', () {
      fakeAsync((FakeAsync async) {
        final SlidingWindow window = SlidingWindow(const Duration(seconds: 10));
        
        // Add entry at T=0
        window.recordSuccess();
        
        // Move to T=11
        async.elapse(const Duration(seconds: 11));
        
        // Add new entry, old one should be pruned
        window.recordFailure();
        
        expect(window.totalCount, 1);
        expect(window.failureCount, 1);
        expect(window.successCount, 0);
      });
    });
    
    test('clear removes all entries', () {
       final SlidingWindow window = SlidingWindow(const Duration(seconds: 10));
       window.recordSuccess();
       window.clear();
       expect(window.totalCount, 0);
    });
    
    test('failureRate returns 0.0 if empty', () {
      final SlidingWindow window = SlidingWindow(const Duration(seconds: 10));
      expect(window.failureRate, 0.0);
    });

    test('successRate returns 1.0 if empty', () {
      final SlidingWindow window = SlidingWindow(const Duration(seconds: 10));
      expect(window.successRate, 1.0);
    });
  });
}