# Task: Build the full-screen lock overlay

Status: done
Spec: ../specs/spec-input-lock-for-cleaning.md

## Goal

Overlay opaco que cobre todas as telas, fica acima de tudo (inclusive full-screen),
mostra a contagem regressiva e a instrução de aborto, e some ao fim da sessão.

## Touches

- MacMetricsView/UI/LockOverlayWindow.swift (novo: NSWindow host)
- MacMetricsView/UI/LockOverlayView.swift (novo: SwiftUI)

## Steps

1. `LockOverlayWindow`: `NSWindow` borderless, opaco, `level` acima do normal,
   `collectionBehavior` em todos os Spaces + sobre full-screen.
2. Criar uma janela por tela; recriar ao mudar a configuração de monitores
   (observar `NSApplication.didChangeScreenParametersNotification`).
3. `LockOverlayView` (SwiftUI): título "Bloqueado para limpeza", contador via
   `CleaningLockCountdownFormatter`, instrução do aborto (Esc 3s) com feedback de
   progresso do hold.
4. API simples `show(...)`/`hide()` dirigida pelo estado do `InputLockService`.

## Verification

- [ ] App lançado (`xcodebuild`/`swift run`): overlay cobre todas as telas e fica
      acima de apps em tela cheia.
- [ ] Contador regressa pelo menos a cada 1s; overlay some na expiração e no aborto.
