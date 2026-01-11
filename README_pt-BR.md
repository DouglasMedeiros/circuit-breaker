# circuit_breaker

[Inglês](README.md) | [Espanhol](README_es.md)

Implementação do padrão de design Circuit Breaker (Disjuntor) em Dart.

**Versão:** 2.0.0 · **Licença:** Veja LICENSE

[![pub package](https://img.shields.io/pub/v/circuit_breaker.svg)](https://pub.dev/packages/circuit_breaker)
[![Build Status](https://github.com/DouglasMedeiros/circuit-breaker/workflows/Dart%20CI/badge.svg)](https://github.com/DouglasMedeiros/circuit-breaker/actions?query=workflow%3A"Dart+CI"+branch%3Amaster)
![GitHub top language](https://img.shields.io/github/languages/top/DouglasMedeiros/circuit-breaker)

## Por que este projeto

- Protege serviços a jusante (downstream) desarmando automaticamente quando as taxas de erro aumentam.
- Suporta taxas de falha com janela deslizante (sliding-window), backoff exponencial, verificações de saúde (health checks), fallbacks, tentativas de reenvio (retries) e persistência básica.
- Biblioteca pequena e com poucas dependências que se integra com `package:http`.

## Funcionalidades

- Estados do circuito: `closed` (fechado), `open` (aberto), `halfOpen` (meio-aberto)
- Detecção de taxa de falha com janela deslizante
- Backoff exponencial para timeouts de recuperação
- Verificações de saúde opcionais e manipuladores de fallback
- Políticas de reenvio (retry) e limite de concorrência (bulkhead)
- Métricas e fluxo de eventos para monitoramento
- Armazenamento plugável via `CircuitBreakerStorage` (helpers em memória e JSON incluídos)

## Começando

Pré-requisitos: Dart SDK 3.0+ (veja `pubspec.yaml`).

### Exemplo rápido

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

### Usando um fallback

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

### Mais exemplos

Para mais exemplos veja: `example/main.dart`

## Superfície da API

Os principais pontos de entrada estão no arquivo barrel da biblioteca: `lib/circuit_breaker.dart`. Tipos principais:

- `CircuitBreaker` — classe principal para criar/buscar disjuntores (`forHost`, `forEndpoint`)
- `FallbackCallback`, `HealthCheckCallback`, `StateChangeCallback`
- `RetryPolicy`, `CircuitBreakerMetrics`, `CircuitState`, `CircuitBreakerStorage`

Veja os fontes em `lib/src/` para implementação e exemplos de opções avançadas.

## Onde obter ajuda

- Abra uma issue: https://github.com/DouglasMedeiros/circuit-breaker/issues
- Leia os arquivos fonte em `lib/src/` para exemplos de uso e comportamento

## Mantenedores & Contribuição

- Mantenedor: DouglasMedeiros — veja a página inicial do repositório em `pubspec.yaml`
- Quer contribuir? Por favor, abra uma issue ou PR. Adicione testes e siga o estilo de código existente.

Se você planeja grandes mudanças, abra uma issue primeiro para discutir o design.

## Licença

Este projeto está disponível sob os termos no arquivo `LICENSE` neste repositório.

---

Biblioteca pequena e focada para tornar chamadas HTTP mais seguras e resilientes. Para documentação detalhada da API, consulte o código fonte em `lib/src/` e os testes em `test/` para padrões de uso.
