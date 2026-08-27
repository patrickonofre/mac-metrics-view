# Plan: RAM Used / Total Only

Status: done

## Objective

Make RAM visibility clearer by showing one menu-bar value only: real used memory over physical total, formatted like `6.3/8 GB`.

## Scope

- Keep the menu-bar RAM segment compact and icon-first.
- Remove the user-facing RAM metric chooser.
- Ignore old RAM metric preferences so legacy `appMemory` or `pressure` values cannot change the menu-bar RAM value.
- Keep RAM collection local and lightweight.

## Handoffs

### PM

- Inputs: user request and screenshot showing `memorychip 6.3/8 GB`.
- Outputs: one focused outcome, RAM used/total only.
- Decision: go.
- Evidence: user explicitly rejected multiple RAM display options.
- Pending: none.

### Dev

- Inputs: RAM sampler/formatter/settings code.
- Outputs: implementation scoped to RAM presentation and tests.
- Decision: go.
- Evidence: see `docs/ai/validation/validation-ram-used-total-only.md`.
- Pending: none.

### QA

- Inputs: spec acceptance criteria.
- Outputs: unit coverage for formatting, legacy preference handling, and RAM calculation.
- Decision: go.
- Evidence: `swift test`.
- Pending: manual app launch remains optional visual confirmation.

### SecOps

- Inputs: local RAM sampling code.
- Outputs: no new network, telemetry, account, or secret handling.
- Decision: n/a.
- Evidence: changed code reads existing local VM stats only.
- Pending: none.

### DBA

- Inputs: old `UserDefaults` RAM metric key.
- Outputs: backward-compatible ignore path, no migration needed.
- Decision: go.
- Evidence: tests set legacy key and verify menu-bar output stays used/total.
- Pending: none.

### DevOps

- Inputs: Swift package app.
- Outputs: build/test validation.
- Decision: go.
- Evidence: `swift test`.
- Pending: no release packaging in this task.

