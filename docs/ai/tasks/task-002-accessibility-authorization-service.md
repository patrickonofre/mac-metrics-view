# Task: Add AccessibilityAuthorization service

Status: done
Spec: ../specs/spec-input-lock-for-cleaning.md

## Goal

Encapsular detecção/solicitação de permissão de Acessibilidade atrás de um
protocolo injetável, com fake para testes e ação de abrir o painel de Ajustes.

## Touches

- MacMetricsView/Services/AccessibilityAuthorization.swift (novo: protocolo + impl)
- MacMetricsViewTests/AccessibilityAuthorizationTests.swift (novo, usa fake)

## Steps

1. Protocolo `AccessibilityAuthorization`: `var isTrusted: Bool { get }`,
   `func openSettings()`.
2. Impl real `SystemAccessibilityAuthorization`: `AXIsProcessTrusted()` e
   abertura de `x-apple.systempreferences:...Accessibility` via `NSWorkspace`.
3. Fake testável (`isTrusted` configurável; registra chamadas de `openSettings`).

## Verification

- [ ] swift test: fake "negada" expõe `isTrusted == false`; `openSettings` é chamado
      pelo caminho de gating (verificado na task de wiring).
- [ ] Sem dependência da permissão real do sistema nos testes.
