# Task: Wire popover controls, shared state, and terminate failsafe

Status: done
Spec: ../specs/spec-input-lock-for-cleaning.md

## Goal

Conectar tudo: controles "Modo limpeza" no popover com gating de permissão, estado
compartilhado em `CPUState`, posse do serviço/overlay no `AppDelegate`, e failsafe
de liberação no término.

## Touches

- MacMetricsView/App/CPUState.swift
- MacMetricsView/App/AppDelegate.swift
- MacMetricsView/UI/PopoverView.swift
- MacMetricsViewTests/CleaningLockStateTests.swift (novo)

## Steps

1. `CPUState`: estado do lock + `startCleaningLock(duration:)`; expõe se o início
   é permitido (depende de `AccessibilityAuthorization.isTrusted`).
2. `AppDelegate`: possui `InputLockService` + `LockOverlayWindow`; faz wiring
   start→overlay e `onEnd`→teardown; implementa failsafe em
   `applicationWillTerminate` (`stop(.terminated)`).
3. `PopoverView`: seção "Modo limpeza" com seletor de duração (presets) + botão
   **Iniciar**; quando sem permissão, botão desabilitado + aviso com **"Abrir
   Ajustes"** (`openSettings`). Iniciar fecha o popover.
4. Persistir a última duração via `CleaningLockSettings`.

## Verification

- [ ] swift test: com `AccessibilityAuthorization` fake "negada",
      `startCleaningLock` não inicia e o estado desabilita o botão.
- [ ] swift test: com permissão concedida, `startCleaningLock` move o estado para
      `.locked` (usando `InputLockService` fake).
- [ ] App lançado: Iniciar bloqueia, overlay aparece; expiração e aborto liberam;
      quit durante o bloqueio não deixa o sistema travado.
