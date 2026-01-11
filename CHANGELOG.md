## 3.0.0

* **Breaking Change**: Renamed `execute` method to `executeRequest` for HTTP requests to distinguish from the new generic execution method.
* **New Feature**: Added `execute<T>` method to support generic asynchronous functions, allowing the circuit breaker to be used for non-HTTP operations.
* **Refactor**: Improved exception handling with a new hierarchy:
  * `CircuitBreakerException` (Base class)
  * `CircuitBreakerOpenException`
  * `CircuitBreakerTimeoutException`
  * `CircuitBreakerBulkheadException`
  * `CircuitBreakerNetworkException`
* **Refactor**: Updated `CircuitBreakerEvent` classes to support generic execution (optional `url` and `statusCode`).
* **Documentation**: Added examples for exception handling and generic execution.

## 2.0.0

* **Breaking Change**: Complete architectural rewrite using Domain-Driven Design principles.
* **New Feature**: Added `CircuitBreakerEvents` for detailed monitoring and logging.
* **New Feature**: Implemented `SlidingWindow` metrics for accurate failure rate tracking.
* **New Feature**: Added flexible `RetryPolicy` configuration.
* **New Feature**: Introduced `CircuitBreakerStorage` with in-memory and JSON persistence support.
* **Documentation**: Major update to `README.md` with detailed usage guides and architecture overview.
* **Tests**: Added comprehensive unit tests covering all new components.

## 1.0.3

* Update lint
* Update versions dependencies

## 1.0.2

* Update lint
* Remove import unused

## 1.0.1

* Clone request
* Add example

## 1.0.0

* Create project
