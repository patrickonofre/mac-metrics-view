# Tasks: Remove Token Usage

Status: in_progress
Spec: ../specs/spec-remove-token-usage.md
Design: ../specs/design-remove-token-usage.md

## Gate Check Commands

- Quick: `swift test --filter 'PopoverTabPresentationTests|MetricsTabLayoutTests|MetricVisibilitySettingsTests|CPUStatePopoverTests'`
- Full: `swift test`
- Build: `xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Debug -destination platform=macOS -derivedDataPath .build/DerivedData build`

## Execution Plan

1. T1 Remove all token integration and presentation while preserving buildability.
2. T2 Delete the now-unreferenced token collection implementation and token-only tests.
3. T3 Remove Xcode references to deleted source.
4. T4 Update current product documentation and technical decision.
5. T5 Run full validation and independent review.

## Task Breakdown

### T1: Remove token integration and presentation

**Status**: completed

**What**: Remove token samplers, callbacks, state, menu-bar output, popover lifecycle, metric card, settings controls, visibility, presentation enum entry, and localization while retaining all non-token machine surfaces.
**Where**: app integration and presentation boundary: `MacMetricsView/App/`, `MacMetricsView/UI/Popover/`, affected settings/models, and mixed XCTest coverage.
**Depends on**: none.
**Requirement**: TOKRM-01, TOKRM-02, TOKRM-03.
**Done when**: app-facing code has no token lifecycle or UI surface; presentation tests assert CPU, GPU, RAM, network, temperature, disk, and battery only.
**Tests**: XCTest unit.
**Gate**: Quick.
**Commit**: `refactor(tokens): remove app integration`

**Evidence**: `swift test --filter 'PopoverTabPresentationTests|MetricsTabLayoutTests|MetricVisibilitySettingsTests|CPUStatePopoverTests'` passed 59 tests on 2026-08-26. Token-only localization remains temporarily because the token implementation still compiles until T2; no app-facing call site reaches it.

### T2: Delete token collection stack

**Status**: completed

**What**: Delete all token readers, samplers, models, stores, calculations, formatters, and token-only tests. Remove now-orphaned helpers only when they were exclusively token code.
**Where**: token files under `MacMetricsView/App`, `MacMetricsView/Models`, `MacMetricsView/Services`, and token-only `MacMetricsViewTests` files.
**Depends on**: T1.
**Requirement**: TOKRM-04, TOKRM-05, TOKRM-06.
**Done when**: no production source implements AI usage tracking or reads legacy token preferences; token-only tests are deleted as intentional feature removal.
**Tests**: SwiftPM compilation and production-source search.
**Gate**: Full.
**Commit**: `refactor(tokens): delete collection stack`

**Evidence**: `swift test` passed 719 tests on 2026-08-26. Production-source searches returned no `TokenUsage`, `TokenProvider`, `TokenPricing`, Claude Code, Codex, Gemini, or legacy token preference reads/removals.

### T3: Remove Xcode token references

**Status**: pending

**What**: Remove deleted token file references and source build entries from the Xcode project.
**Where**: `MacMetricsView.xcodeproj/project.pbxproj`.
**Depends on**: T2.
**Requirement**: TOKRM-04.
**Done when**: project contains no token source file reference or source build entry and Debug app builds.
**Tests**: Xcode build.
**Gate**: Build.
**Commit**: `build(tokens): remove xcode source entries`

### T4: Update current product documentation

**Status**: pending

**What**: Remove current token/cost capability claims and supersede the dev/AI product-pillar decision with machine-resource focus. Preserve historical records.
**Where**: current product documentation.
**Depends on**: T3.
**Requirement**: TOKRM-07, TOKRM-08.
**Done when**: current docs describe machine resources and utilities without token tracking; historical documents remain unchanged.
**Tests**: Targeted text search.
**Gate**: Full.
**Commit**: `docs(tokens): remove current capability claims`

### T5: Validate removal

**Status**: pending

**What**: Run full SwiftPM and Xcode gates, run source/document searches, launch the Debug app, and record independent verification.
**Where**: `docs/ai/validation/validation-remove-token-usage.md`.
**Depends on**: T4.
**Requirement**: TOKRM-01, TOKRM-02, TOKRM-03, TOKRM-04, TOKRM-05, TOKRM-06, TOKRM-07, TOKRM-08.
**Done when**: every requirement has evidence, test counts are explained, and residual inert `UserDefaults` values are recorded.
**Tests**: Full suite, Xcode Debug build, app launch, independent verifier.
**Gate**: Build.
**Commit**: `docs(validation): record token removal evidence`

## Execution Map

```
T1 -> T2 -> T3 -> T4 -> T5
```

## Test Coverage Matrix

| Requirement | Task | Evidence |
| --- | --- | --- |
| TOKRM-01 | T1 | App wiring has no token sampler/model/refresh references. |
| TOKRM-02 | T1 | `PopoverTabPresentationTests` asserts machine-only order. |
| TOKRM-03 | T1 | Settings and visibility tests assert no token configuration. |
| TOKRM-04 | T2, T3 | Production source search and Xcode build. |
| TOKRM-05 | T2 | Production source search and SwiftPM build. |
| TOKRM-06 | T2 | Search confirms no legacy token key reads or removal. |
| TOKRM-07 | T4 | Current-doc text search. |
| TOKRM-08 | T4 | Historical documentation stays outside touched files. |
