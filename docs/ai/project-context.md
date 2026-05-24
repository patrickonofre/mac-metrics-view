# Project context

## What it is

**Mac Metrics View** is a native macOS menu bar utility that answers one question at
a glance: *"Is my Mac under CPU, RAM, or network pressure right now?"* It shows
compact metric indicators near the system clock and opens a lightweight popover for
more detail. Temperature and launch-at-login are specified feature extensions.

Authoritative product source: [`docs/PRD.md`](../PRD.md). V1 implementation contract:
[`docs/SPEC_DRIVEN_DESIGN_V1.md`](../SPEC_DRIVEN_DESIGN_V1.md). Reference inspiration:
OneMenu by CoffeeBreak Software (native feel, lightweight presence) — Mac Metrics View
starts deliberately narrower.

## Users

- Developers and power users who want a constant CPU/RAM/network signal while working.
- Mac users who want to know whether sluggishness is resource-related without opening
  Activity Monitor.
- People who prefer quiet menu bar utilities over full dashboards.

## Goals

- Show current CPU %, RAM (in GB), and network throughput in the menu bar.
- Let users choose which metrics appear, and whether identifiers use compact SF Symbols
  (default) or explicit `CPU`/`RAM`/`NET` labels.
- Open a focused popover with more CPU/RAM/network/temperature context.
- Feel native, quiet, and aligned with macOS.
- Run locally — no telemetry, no accounts.
- Keep the app's own CPU/memory footprint low, especially when metrics are hidden.

## Non-goals

- A full Activity Monitor replacement.
- Disk/battery/fan monitoring (temperature is an explicitly specified extension).
- Alerts, automations, history analytics, or cloud sync.
- Cross-platform support.
- Complex customization or paid licensing.

## Hard constraints

- **Native only** — Swift, SwiftUI, AppKit interop. Not Electron/Tauri (see TD-001).
- **Local only** — network metrics come from local interface byte-counter deltas; no
  probe requests, no external endpoints, no telemetry (see TD-002).
- **Lightweight** — no high-frequency timers, heavy process scans, or needless
  main-thread work. Energy use is a product requirement.
- **menu bar-first** — accessory activation policy: no Dock icon, no main window on launch.

## Current state

V1 covers CPU, RAM, and network in the menu bar with a detail popover and per-metric
visibility plus identifier-display control. Temperature and launch-at-login are scoped
in [`docs/features/temperatura.md`](../features/temperatura.md) and
[`docs/features/inicializacao.md`](../features/inicializacao.md) and partially present
in the codebase (`TemperatureSampler`, `LaunchAtLoginManager`).

## Repository shape

Single repo, single product (not a monorepo). One executable target plus one test
target, defined in both `Package.swift` and `MacMetricsView.xcodeproj`. There is no
backend, database, CI/CD pipeline, or container infrastructure. A static marketing
page lives in `site/`.
