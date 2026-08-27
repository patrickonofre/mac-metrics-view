# Specification: Remove Token Usage

Status: done
Plan: ../plans/plan-remove-token-usage.md

## Problem Statement

AI token tracking duplicates source-tool controls and dilutes the app's focus on machine resources. The app must no longer read AI tool files, retain token state in memory, or present token data and configuration.

## Goals

- [x] Remove all user-facing token usage and cost surfaces.
- [x] Remove all production token collection and processing code.
- [x] Keep machine-resource sampling, settings, and utilities working.
- [x] Keep prior token preferences inert without deleting user data.

## Out of Scope

| Item | Reason |
| --- | --- |
| External AI tool logs | The app does not own those files. |
| UserDefaults cleanup migration | Deleting historical local values is unnecessary for removed code and risks user data. |
| Historical documentation | It is an audit record of past product behavior. |
| New machine-resource features | Separate product work. |

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Old token preferences | Leave stored values untouched and unread. | Removal needs no migration and avoids deleting user data. | yes |
| Token-only tests | Delete them with the feature. | They test behavior the user explicitly removed. | yes |
| Product positioning | Describe machine resources and existing utilities, without Dev/AI tracking. | Matches requested focus. | yes |

**Open questions:** none - all resolved or logged above.

## User Stories

### P1: Machine-Only Monitoring

**User Story**: As a Mac Metrics View user, I want the app to show machine resources only so that the menu bar and popover stay focused.

**Why P1**: This is the requested product direction.

**Acceptance Criteria**:

1. WHEN the app starts THEN the system SHALL create no token sampler, token reader, token model, or token refresh timer.
2. WHEN the user opens the popover THEN the system SHALL show CPU, GPU, RAM, network, temperature, disk, battery, and enabled utilities without a Tokens metric card or tab entry.
3. WHEN the user opens settings THEN the system SHALL show no token visibility, provider, scope, window, budget, or reset control.
4. The system SHALL omit token usage and cost segments from the menu-bar title.

**Independent Test**: Instantiate app-facing state and presentation helpers, then assert no token types or presentation entries remain while machine metrics retain their existing list.

### P1: Remove Token Collection

**User Story**: As a maintainer, I want no production token collection code so that the app does not scan AI tool files or retain duplicate usage state.

**Why P1**: Removes the unneeded runtime work and maintenance surface.

**Acceptance Criteria**:

1. WHEN the app target builds THEN the system SHALL contain no compiled token reader, sampler, formatter, pricing, store, model, or history-backfill source file.
2. WHEN the Swift package test suite builds THEN the system SHALL contain no production reference to Claude Code, Codex, Gemini, `TokenUsage`, `TokenProvider`, or `TokenPricing`.
3. WHILE existing token `UserDefaults` values are present THEN the system SHALL neither read, display, nor delete those values.

**Independent Test**: Search the production source allowlist for removed feature identifiers and build both SwiftPM and the Xcode app target.

### P2: Focused Current Documentation

**User Story**: As a maintainer, I want current product documentation to match the machine-resource focus.

**Why P2**: Avoids promising a removed capability.

**Acceptance Criteria**:

1. WHEN a reader opens the current README, PRD, project context, or technical decisions THEN the system SHALL not describe AI token or cost tracking as a current product capability or pillar.
2. IF historical documentation mentions token tracking THEN the system SHALL retain it as historical evidence without presenting it as current behavior.

**Independent Test**: Search current product documents for removed capability claims and inspect historical records separately.

## Edge Cases

- IF an existing `UserDefaults` domain contains token values THEN the system SHALL ignore them and make no deletion attempt.
- IF a metric presentation test enumerates cards or tabs THEN the system SHALL assert the exact machine-only order after token removal.
- IF Xcode has an obsolete token file reference THEN the system SHALL fail the build until that reference is removed.

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| TOKRM-01 | P1: Machine-Only Monitoring | Validation | Passed |
| TOKRM-02 | P1: Machine-Only Monitoring | Validation | Passed |
| TOKRM-03 | P1: Machine-Only Monitoring | Validation | Passed |
| TOKRM-04 | P1: Remove Token Collection | Validation | Passed |
| TOKRM-05 | P1: Remove Token Collection | Validation | Passed |
| TOKRM-06 | P1: Remove Token Collection | Validation | Passed |
| TOKRM-07 | P2: Focused Current Documentation | Validation | Passed |
| TOKRM-08 | P2: Focused Current Documentation | Validation | Passed |

**Coverage:** 8 total, 8 mapped to tasks, 0 unmapped.

## Success Criteria

- [x] `swift test` passes after token-only code and tests are removed.
- [x] Debug Xcode build passes after project-file cleanup.
- [x] Current UI and documentation expose no token capability.
- [x] Existing token keys are neither read nor removed by production code.

## Handoff: Dev -> QA

- Inputs: removal requirements TOKRM-01 through TOKRM-08.
- Outputs: test plan uses exact machine-only presentation order, source searches, SwiftPM, and Xcode gates.
- Decision: ready for tasks.
- Evidence: source dependency inventory in the design.
- Pending: implementation and independent verification.
