# Plan: Remove Token Usage

Status: ready

## Objective

Remove AI token and cost tracking so Mac Metrics View focuses on local machine resources and utilities.

## Phases

1. Remove token presentation, runtime wiring, settings, and menu-bar output.
2. Remove token readers, models, formatters, stores, pricing, and their tests.
3. Remove Xcode references and update product documentation and decisions.
4. Run full validation and record residual migration risk.

## Scope

- Remove the Tokens metric, its popover card, settings, automatic refresh, samplers, readers, models, formatters, and source-specific dependencies.
- Remove token-only XCTest coverage and update mixed tests to assert machine-only behavior.
- Remove token source files from the Xcode project.
- Update current product documentation to describe a machine-resource focus.

## Non-Goals

- Do not delete Claude, Codex, Gemini, or other external tool logs.
- Do not delete existing `UserDefaults` token keys or stored values. They become inert because no production code reads them.
- Do not add replacement AI analytics, new persistence, telemetry, network calls, or resource metrics.
- Do not rewrite historical plans or validation records that document past shipped work.

## Risks

- Token code is coupled to `CPUState`, `AppDelegate`, `PopoverView`, `MetricsTab`, settings, and the Xcode project. Mitigation: compile both SwiftPM and Xcode after each layer removal.
- Existing user defaults will remain on disk. Mitigation: leave them untouched; no code path reads or displays them after removal.
- Token-only tests must be deleted as part of feature deletion. Mitigation: preserve and strengthen mixed UI tests for the machine-only metric list.

## Handoff: PM -> Dev

- Inputs: token tracking duplicates controls already available in the source tools.
- Outputs: machine-resource product focus and bounded removal scope.
- Decision: go.
- Evidence: user direction on 2026-08-26.
- Pending: validation after implementation.
