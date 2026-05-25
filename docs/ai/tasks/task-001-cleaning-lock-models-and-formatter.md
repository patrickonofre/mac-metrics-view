# Task: Add cleaning-lock models, settings, and counter formatter

Status: done
Spec: ../specs/spec-input-lock-for-cleaning.md

## Goal

Tipos puros e persistência prontos: duração persistida, enum de fim de sessão e
formatação defensiva do contador — tudo testável sem tocar em UI ou `CGEventTap`.

## Touches

- MacMetricsView/Models/CleaningLockSettings.swift (novo)
- MacMetricsView/Models/LockEndReason.swift (novo)
- MacMetricsView/Services/CleaningLockCountdownFormatter.swift (novo, função pura)
- MacMetricsViewTests/CleaningLockSettingsTests.swift (novo)
- MacMetricsViewTests/CleaningLockCountdownFormatterTests.swift (novo)

## Steps

1. `LockEndReason` enum: `.expired`, `.aborted`, `.terminated`.
2. `CleaningLockSettings`: presets permitidos (15, 30, 60, 120, 300s), duração
   selecionada persistida em `UserDefaults` com chave versionada; default 30s.
   Seguir o padrão de `MetricDisplaySettings` (injeção de `UserDefaults`).
3. Clamp na leitura: valor ausente/inválido/≤0/fora dos presets cai no default.
4. `CleaningLockCountdownFormatter`: função pura `string(forRemaining:total:)` →
   `m:ss` quando ≥60s, `Xs` abaixo; clamp em `[0, total]`.

## Verification

- [ ] swift test cobre persistência/recuperação de duração e fallback de valor inválido.
- [ ] swift test cobre formatação: 90→"1:30", 5→"5s", -1→"0s", >total→total.
