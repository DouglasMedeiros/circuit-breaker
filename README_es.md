# circuit_breaker

[Portugués Brasileño](README_pt-BR.md) | [Inglés](README.md) 

Implementación del patrón de diseño Circuit Breaker (Cortacircuitos) en Dart.

**Versión:** 3.0.0 · **Licencia:** Ver LICENSE

[![pub package](https://img.shields.io/pub/v/circuit_breaker.svg)](https://pub.dev/packages/circuit_breaker)
[![Build Status](https://github.com/DouglasMedeiros/circuit-breaker/workflows/Dart%20CI/badge.svg)](https://github.com/DouglasMedeiros/circuit-breaker/actions?query=workflow%3A"Dart+CI"+branch%3Amaster)
![GitHub top language](https://img.shields.io/github/languages/top/DouglasMedeiros/circuit-breaker)

## Por qué este proyecto

- Protege los servicios posteriores (downstream) disparándose automáticamente cuando aumentan las tasas de error.
- Soporta tasas de fallo con ventana deslizante (sliding-window), retroceso exponencial (exponential backoff), comprobaciones de salud (health checks), fallbacks, reintentos y persistencia básica.
- Biblioteca pequeña y con pocas dependencias que se integra con `package:http`.

## Características

- Estados del circuito: `closed` (cerrado), `open` (abierto), `halfOpen` (medio abierto)
- Detección de tasa de fallos con ventana deslizante
- Retroceso exponencial para tiempos de espera de recuperación
- Comprobaciones de salud opcionales y manejadores de fallback
- Políticas de reintento y límite de concurrencia (bulkhead)
- Métricas y flujo de eventos para monitoreo
- Almacenamiento conectable vía `CircuitBreakerStorage` (se incluyen ayudantes en memoria y JSON)

## Comenzando

Prerrequisitos: Dart SDK 3.0+ (ver `pubspec.yaml`).

### Ejemplo rápido

```dart
Future<void> genericExecuteExample() async {
  final CircuitBreaker cb = CircuitBreaker(
    failureThreshold: 2,
    timeout: const Duration(seconds: 2),
  );

  Future<String> fetchData(String id) async {
    // Simulate some async logic (not necessarily HTTP)
    if (id == 'fail') {
      throw Exception('Database connection error');
    }
    return 'Data for $id';
  }

  final String result = await cb.execute(() => fetchData('123'));

  try {
    await cb.execute(() => fetchData('fail'));
  } catch (e) {
    print('Caught error: $e');
  }

  try {
    await cb.execute(() => fetchData('fail'));
  } catch (e) {
    print('Caught error: $e');
  }

  print('Current state: ${cb.state}');

  // Execution when open with fallback
  final String fallbackResult = await cb.execute(
    () => fetchData('456'),
    fallback: (Object error) async => 'Cached data (fallback)',
  );
  print('Result with fallback: $fallbackResult');
}
```

### Request

```dart
import 'package:http/http.dart' as http;
import 'package:circuit_breaker/circuit_breaker.dart';

Future<void> main() async {
  // Cria um CircuitBreaker
  final CircuitBreaker cb = CircuitBreaker(
    failureThreshold: 3,
    successThreshold: 2,
  );

  final http.Request request = http.Request('GET', Uri.parse('https://api.example.com/ping'));

  try {
    final http.StreamedResponse streamed = await cb.executeRequest(request);
    final http.Response response = await http.Response.fromStream(streamed);
    print('status: ${response.statusCode}');
    print('metrics: ${cb.metrics}');
  } catch (e) {
    print('Requisição falhou: $e');
  }
}
```

### Usando un fallback

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:circuit_breaker/circuit_breaker.dart';

Future<void> main() async {
  final CircuitBreaker cb = CircuitBreaker(
    failureThreshold: 2,
    timeout: const Duration(seconds: 1),
    fallback: (http.BaseRequest request, Object? error) async {
      // Return a fallback response when circuit is open or request fails
      final Uint8List bytes = utf8.encode('{"fallback":true}');
      return http.StreamedResponse(Stream<Uint8List>.fromIterable(<Uint8List>[bytes]), 200, headers: <String, String>{
        'content-type': 'application/json',
        'content-length': bytes.length.toString(),
      });
    },
  );

  final http.Request request = http.Request('GET', Uri.parse('https://api.example.com/data'));
  final http.StreamedResponse streamed = await cb.executeRequest(request);
  final http.Response response = await http.Response.fromStream(streamed);
  print('body: ${response.body}');
}
```

### Más ejemplos

Para más ejemplos ver: `example/main.dart`

## Superficie de la API

Los principales puntos de entrada están en el archivo barril de la biblioteca: `lib/circuit_breaker.dart`. Tipos clave:

- `CircuitBreaker` — clase principal para crear/buscar cortacircuitos (`forHost`, `forEndpoint`)
- `FallbackCallback`, `HealthCheckCallback`, `StateChangeCallback`
- `RetryPolicy`, `CircuitBreakerMetrics`, `CircuitState`, `CircuitBreakerStorage`

Ver las fuentes en `lib/src/` para implementación y ejemplos de opciones avanzadas.

## Dónde obtener ayuda

- Abre un issue: https://github.com/DouglasMedeiros/circuit-breaker/issues
- Lee los archivos fuente en `lib/src/` para ejemplos de uso y comportamiento

## Mantenedores y Contribución

- Mantenedor: DouglasMedeiros — ver la página de inicio del repositorio en `pubspec.yaml`
- ¿Quieres contribuir? Por favor, abre un issue o PR. Añade pruebas y sigue el estilo de código existente.

Si planeas grandes cambios, abre un issue primero para discutir el diseño.

## Licencia

Este proyecto está disponible bajo los términos en el archivo `LICENSE` en este repositorio.

---

Biblioteca pequeña y enfocada para hacer llamadas HTTP más seguras y resilientes. Para documentación detallada de la API, consulta el código fuente en `lib/src/` y las pruebas en `test/` para patrones de uso.
