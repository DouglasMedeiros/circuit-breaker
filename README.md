# Circuit Breaker

[![Build Status](https://github.com/DouglasMedeiros/circuit-breaker/workflows/Dart%20CI/badge.svg)](https://github.com/DouglasMedeiros/circuit-breaker/actions?query=workflow%3A"Dart+CI"+branch%3Amaster)
![GitHub top language](https://img.shields.io/github/languages/top/DouglasMedeiros/circuit-breaker)


## Using

### Create

```
final http = Client();
final Request request = Request('POST', Uri.parse('http://example.com'));

final cb = CircuitBreaker(
    request: request,
    failureThreshold: 3,
    successThreshold: 5,
    timeout: Duration(seconds: 2));
```

### Results

```
await cb.execute()
    .then((value){
        print("Success breaker");
    }).catchError((error, stack){
        print("Fail breaker");
    });
```
OR
```
// 2
final result = await cb.execute();
print(result.statusCode);
print(result.body);
print(result.state);
print(result.nextAttempt);
```