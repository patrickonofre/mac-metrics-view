# Task: Implement InputLockService (CGEventTap engine)

Status: done
Spec: ../specs/spec-input-lock-for-cleaning.md

## Goal

Motor de bloqueio isolado e testável: instala o `CGEventTap`, suprime
teclado/ponteiro, conta o tempo, reabilita o tap em timeout, trata o aborto e
notifica o fim — tudo atrás de um protocolo com fake.

## Touches

- MacMetricsView/Services/InputLockService.swift (novo: protocolo + estado)
- MacMetricsView/Services/CGEventTapInputLock.swift (novo: impl real)
- MacMetricsViewTests/InputLockServiceTests.swift (novo, usa fake do tap + relógio)

## Steps

1. Protocolo `InputLockService` (`@MainActor`): `start(duration:)`,
   `stop(reason:)`, estado observável `phase (.idle/.locked)` e `remaining`,
   callback `onEnd(reason:)`.
2. Separar a lógica de tempo/estado (relógio injetável, reusar
   `MainRunLoopTimer`/equivalente) da camada do `CGEventTap`, para testar
   expiração e aborto com fakes.
3. `CGEventTapInputLock`: tap em `.cgSessionEventTap`, máscara teclado + mouse +
   scroll + gestos; callback retorna `nil` (consome) exceto o caminho do aborto.
4. Reabilitar o tap em `kCGEventTapDisabledByTimeout`/`...ByUserInput`; callback
   enxuto.
5. Aborto: detectar Esc sustentado por 3s (não suprimir esse caminho) → encerrar
   com `.aborted`.
6. `stop(.terminated)` desfaz o tap e zera estado.

## Verification

- [ ] swift test (fake): `start` → `.locked`, `remaining` decresce até 0 e dispara
      `onEnd(.expired)`.
- [ ] swift test: injetar `kCGEventTapDisabledByTimeout` reinstala o tap e mantém a sessão.
- [ ] swift test: hold de Esc 3s → `onEnd(.aborted)`; <3s não desbloqueia.
- [ ] swift test: `stop(.terminated)` → `phase == .idle`.
- [ ] `start` chamado já `.locked` é no-op (idempotente).
